# src/PipelineOrchestrator.jl - Pipeline Orchestration
# Design Specification v2.4 Implementation
# Main processing loop integrating all pipeline stages
# Session 6: Enhanced with PipelineManager and per-tick metrics

"""
PipelineMetrics - Accumulated pipeline statistics

# Fields
- `ticks_processed::Int64`: Total ticks processed
- `broadcasts_sent::Int32`: Total successful broadcasts
- `errors::Int32`: Total errors encountered
- `total_latency_us::Int64`: Cumulative latency (microseconds)
- `signal_processing_time_us::Int64`: Cumulative signal processing time
- `broadcast_time_us::Int64`: Cumulative broadcast time
- `max_latency_us::Int32`: Maximum observed latency
- `min_latency_us::Int32`: Minimum observed latency (excluding zero)
"""
mutable struct PipelineMetrics
    ticks_processed::Int64
    broadcasts_sent::Int32
    errors::Int32
    total_latency_us::Int64
    signal_processing_time_us::Int64
    broadcast_time_us::Int64
    max_latency_us::Int32
    min_latency_us::Int32

    function PipelineMetrics()
        new(Int64(0), Int32(0), Int32(0), Int64(0), Int64(0), Int64(0),
            Int32(0), typemax(Int32))
    end
end

"""
PipelineManager - Orchestrates all pipeline components

Maintains pipeline state, configuration, and statistics.

# Fields
- `config::PipelineConfig`: Pipeline configuration
- `tickhotloop_state::TickHotLoopState`: Signal processing state
- `split_manager::TripleSplitManager`: Broadcasting manager
- `metrics::PipelineMetrics`: Accumulated statistics
- `is_running::Bool`: Pipeline running status
- `completion_callback::Union{Function, Nothing}`: Optional completion callback
"""
mutable struct PipelineManager
    config::PipelineConfig
    tickhotloop_state::TickHotLoopState
    split_manager::TripleSplitManager
    metrics::PipelineMetrics
    is_running::Bool
    completion_callback::Union{Function, Nothing}
end

"""
    create_pipeline_manager(config, split_manager)

Create pipeline manager with configuration and broadcasting manager.

# Arguments
- `config::PipelineConfig`: Pipeline configuration
- `split_manager::TripleSplitManager`: Pre-configured broadcasting manager

# Returns
- `PipelineManager`: Ready-to-use pipeline manager

# Example
```julia
config = create_default_config()
manager = create_triple_split_manager()
subscribe_consumer!(manager, "consumer1", PRIORITY)

pipeline_mgr = create_pipeline_manager(config, manager)
```
"""
function create_pipeline_manager(
    config::PipelineConfig,
    split_manager::TripleSplitManager
)::PipelineManager
    return PipelineManager(
        config,
        create_tickhotloop_state(),
        split_manager,
        PipelineMetrics(),
        false,
        nothing
    )
end

"""
    process_single_tick_through_pipeline!(pipeline_manager, msg)

Process single tick through all pipeline stages with metrics.

Internal function for per-tick processing with latency tracking.

# Arguments
- `pipeline_manager::PipelineManager`: Pipeline manager
- `msg::BroadcastMessage`: Message to process (modified in-place)

# Returns
- `NamedTuple`: Per-tick metrics
  - `success::Bool`: Processing succeeded
  - `total_latency_us::Int32`: Total latency (microseconds)
  - `signal_processing_time_us::Int32`: Signal processing time
  - `broadcast_time_us::Int32`: Broadcast time
  - `consumers_reached::Int32`: Successful consumer deliveries
  - `status_flag::UInt8`: Final message status
"""
function process_single_tick_through_pipeline!(
    pipeline_manager::PipelineManager,
    msg::BroadcastMessage
)::NamedTuple
    pipeline_start = time_ns()

    # Stage 2: Signal processing (TickHotLoopF32)
    signal_start = time_ns()

    try
        sp = pipeline_manager.config.signal_processing
        process_tick_signal!(
            msg,
            pipeline_manager.tickhotloop_state,
            sp.agc_alpha,
            sp.agc_min_scale,
            sp.agc_max_scale,
            sp.winsorize_threshold,
            sp.min_price,
            sp.max_price,
            sp.max_jump
        )
    catch e
        @warn "Signal processing error: $e"
        return (
            success = false,
            total_latency_us = Int32(0),
            signal_processing_time_us = Int32(0),
            broadcast_time_us = Int32(0),
            consumers_reached = Int32(0),
            status_flag = msg.status_flag
        )
    end

    signal_time_us = Int32((time_ns() - signal_start) ÷ Int64(1000))

    # Stage 3: Broadcasting
    broadcast_start = time_ns()
    (total, successful, dropped) = broadcast_to_all!(pipeline_manager.split_manager, msg)
    broadcast_time_us = Int32((time_ns() - broadcast_start) ÷ Int64(1000))

    total_time_us = Int32((time_ns() - pipeline_start) ÷ Int64(1000))

    # Update metrics
    pipeline_manager.metrics.total_latency_us += Int64(total_time_us)
    pipeline_manager.metrics.signal_processing_time_us += Int64(signal_time_us)
    pipeline_manager.metrics.broadcast_time_us += Int64(broadcast_time_us)

    if total_time_us > pipeline_manager.metrics.max_latency_us
        pipeline_manager.metrics.max_latency_us = total_time_us
    end

    if total_time_us > Int32(0) && total_time_us < pipeline_manager.metrics.min_latency_us
        pipeline_manager.metrics.min_latency_us = total_time_us
    end

    return (
        success = true,
        total_latency_us = total_time_us,
        signal_processing_time_us = signal_time_us,
        broadcast_time_us = broadcast_time_us,
        consumers_reached = successful,
        status_flag = msg.status_flag
    )
end

"""
    run_pipeline(config, manager; max_ticks)

Run complete tick processing pipeline (simple interface).

Integrates all stages:
1. VolumeExpansion: Read and expand ticks → Channel{BroadcastMessage}
2. TickHotLoopF32: Signal processing (in-place updates)
3. TripleSplitSystem: Broadcast to all consumers

# Arguments
- `config::PipelineConfig`: Pipeline configuration
- `manager::TripleSplitManager`: Broadcasting manager with subscribed consumers
- `max_ticks::Int64`: Maximum ticks to process (default: typemax(Int64))

# Returns
- `NamedTuple`: Statistics (ticks_processed, broadcasts_sent, errors)

# Example
```julia
config = create_default_config()
manager = create_triple_split_manager()
subscribe_consumer!(manager, "consumer1", PRIORITY)

stats = run_pipeline(config, manager, max_ticks=1000)
```
"""
function run_pipeline(
    config::PipelineConfig,
    manager::TripleSplitManager;
    max_ticks::Int64 = typemax(Int64)
)::NamedTuple
    # Initialize state
    state = create_tickhotloop_state()
    ticks_processed = Int64(0)
    broadcasts_sent = Int32(0)
    errors = Int32(0)

    println("Starting pipeline:")
    println("  Tick file: $(config.tick_file_path)")
    println("  Flow delay: $(config.flow_control.delay_ms)ms")
    println("  Consumers: $(length(manager.consumers))")

    try
        # Stage 1: VolumeExpansion - Stream ticks
        tick_channel = stream_expanded_ticks(config.tick_file_path, config.flow_control.delay_ms)

        # Main processing loop
        for msg in tick_channel
            if ticks_processed >= max_ticks
                break
            end

            # Stage 2: TickHotLoopF32 - Signal processing (in-place)
            try
                sp = config.signal_processing
                process_tick_signal!(
                    msg,
                    state,
                    sp.agc_alpha,
                    sp.agc_min_scale,
                    sp.agc_max_scale,
                    sp.winsorize_threshold,
                    sp.min_price,
                    sp.max_price,
                    sp.max_jump
                )
            catch e
                @warn "Signal processing error: $e"
                errors += Int32(1)
                continue
            end

            # Stage 3: TripleSplitSystem - Broadcast
            try
                (total, successful, dropped) = broadcast_to_all!(manager, msg)
                if successful > Int32(0)
                    broadcasts_sent += Int32(1)
                end
            catch e
                @warn "Broadcast error: $e"
                errors += Int32(1)
            end

            ticks_processed += Int64(1)

            # Progress reporting
            if ticks_processed % 10000 == 0
                println("  Processed: $ticks_processed ticks")
            end
        end

    catch e
        @error "Pipeline error: $e"
        errors += Int32(1)
    end

    println("Pipeline completed:")
    println("  Ticks processed: $ticks_processed")
    println("  Broadcasts sent: $broadcasts_sent")
    println("  Errors: $errors")

    return (
        ticks_processed = ticks_processed,
        broadcasts_sent = broadcasts_sent,
        errors = errors,
        state = state
    )
end

"""
    run_pipeline!(pipeline_manager; max_ticks)

Run pipeline using PipelineManager with enhanced metrics and lifecycle control.

# Arguments
- `pipeline_manager::PipelineManager`: Pre-configured pipeline manager
- `max_ticks::Int64`: Maximum ticks to process (default: typemax(Int64))

# Returns
- `NamedTuple`: Enhanced statistics
  - `ticks_processed::Int64`: Total ticks processed
  - `broadcasts_sent::Int32`: Successful broadcasts
  - `errors::Int32`: Total errors
  - `avg_latency_us::Float32`: Average per-tick latency
  - `max_latency_us::Int32`: Maximum observed latency
  - `min_latency_us::Int32`: Minimum observed latency
  - `avg_signal_time_us::Float32`: Average signal processing time
  - `avg_broadcast_time_us::Float32`: Average broadcast time
  - `state::TickHotLoopState`: Final signal processing state

# Example
```julia
config = create_default_config()
split_mgr = create_triple_split_manager()
subscribe_consumer!(split_mgr, "consumer1", PRIORITY)

pipeline_mgr = create_pipeline_manager(config, split_mgr)
stats = run_pipeline!(pipeline_mgr, max_ticks = 10000)

println("Avg latency: \$(stats.avg_latency_us)μs")
println("Max latency: \$(stats.max_latency_us)μs")
```
"""
function run_pipeline!(
    pipeline_manager::PipelineManager;
    max_ticks::Int64 = typemax(Int64)
)::NamedTuple
    pipeline_manager.is_running = true
    pipeline_manager.metrics = PipelineMetrics()  # Reset metrics

    println("Starting pipeline:")
    println("  Tick file: $(pipeline_manager.config.tick_file_path)")
    println("  Flow delay: $(pipeline_manager.config.flow_control.delay_ms)ms")
    println("  Consumers: $(length(pipeline_manager.split_manager.consumers))")

    try
        # Stage 1: VolumeExpansion - Stream ticks
        tick_channel = stream_expanded_ticks(
            pipeline_manager.config.tick_file_path,
            pipeline_manager.config.flow_control.delay_ms
        )

        # Main processing loop
        for msg in tick_channel
            if !pipeline_manager.is_running || pipeline_manager.metrics.ticks_processed >= max_ticks
                break
            end

            # Process through pipeline with metrics
            result = process_single_tick_through_pipeline!(pipeline_manager, msg)

            # Update accumulated metrics
            pipeline_manager.metrics.ticks_processed += Int64(1)

            if result.success
                pipeline_manager.metrics.broadcasts_sent += Int32(1)
            else
                pipeline_manager.metrics.errors += Int32(1)
            end

            # Progress reporting
            if pipeline_manager.metrics.ticks_processed % Int64(10000) == Int64(0)
                println("  Processed: $(pipeline_manager.metrics.ticks_processed) ticks")
            end
        end

    catch e
        @error "Pipeline error: $e"
        pipeline_manager.metrics.errors += Int32(1)
    end

    pipeline_manager.is_running = false

    # Calculate averages
    ticks = pipeline_manager.metrics.ticks_processed
    avg_latency_us = ticks > Int64(0) ?
        Float32(pipeline_manager.metrics.total_latency_us) / Float32(ticks) :
        Float32(0.0)

    avg_signal_time_us = ticks > Int64(0) ?
        Float32(pipeline_manager.metrics.signal_processing_time_us) / Float32(ticks) :
        Float32(0.0)

    avg_broadcast_time_us = ticks > Int64(0) ?
        Float32(pipeline_manager.metrics.broadcast_time_us) / Float32(ticks) :
        Float32(0.0)

    # Fix min_latency if no ticks processed
    min_latency = pipeline_manager.metrics.min_latency_us == typemax(Int32) ?
        Int32(0) : pipeline_manager.metrics.min_latency_us

    println("Pipeline completed:")
    println("  Ticks processed: $(pipeline_manager.metrics.ticks_processed)")
    println("  Broadcasts sent: $(pipeline_manager.metrics.broadcasts_sent)")
    println("  Errors: $(pipeline_manager.metrics.errors)")
    println("  Avg latency: $(round(avg_latency_us, digits=2))μs")
    println("  Max latency: $(pipeline_manager.metrics.max_latency_us)μs")
    println("  Min latency: $(min_latency)μs")

    # Call completion callback if set
    if pipeline_manager.completion_callback !== nothing
        pipeline_manager.completion_callback(pipeline_manager.metrics.ticks_processed)
    end

    return (
        ticks_processed = pipeline_manager.metrics.ticks_processed,
        broadcasts_sent = pipeline_manager.metrics.broadcasts_sent,
        errors = pipeline_manager.metrics.errors,
        avg_latency_us = avg_latency_us,
        max_latency_us = pipeline_manager.metrics.max_latency_us,
        min_latency_us = min_latency,
        avg_signal_time_us = avg_signal_time_us,
        avg_broadcast_time_us = avg_broadcast_time_us,
        state = pipeline_manager.tickhotloop_state
    )
end

"""
    stop_pipeline!(pipeline_manager)

Stop running pipeline gracefully.

Sets is_running flag to false, causing pipeline to exit after current tick.

# Arguments
- `pipeline_manager::PipelineManager`: Pipeline manager to stop

# Example
```julia
# Start pipeline in background task
task = @async run_pipeline!(pipeline_mgr)

# ... later ...
stop_pipeline!(pipeline_mgr)
wait(task)
```
"""
function stop_pipeline!(pipeline_manager::PipelineManager)
    pipeline_manager.is_running = false
    println("Pipeline stop requested")
end

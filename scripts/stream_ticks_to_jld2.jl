#!/usr/bin/env julia

# Stream all ticks from YM tick file through TickDataPipeline to JLD2 file
# Usage: julia --project=. scripts/stream_ticks_to_jld2.jl

using TickDataPipeline
using JLD2
using Dates

# Configuration
const TICK_FILE = "data/raw/YM 06-25.Last.txt"
const TICK_DELAY_MS = Float64(0.0)  # Full speed - no delay
const COUNTER_INTERVAL = Int64(10000)

# Generate timestamped output filename
const OUTPUT_FILE = "data/jld2/processed_ticks_$(Dates.format(now(), "yyyymmdd_HHMMSS")).jld2"

# Storage for unpacked BroadcastMessage fields
mutable struct TickDataCollector
    tick_idx::Vector{Int32}
    timestamp::Vector{Int64}
    raw_price::Vector{Int32}
    price_delta::Vector{Int32}
    normalization::Vector{Float32}
    complex_signal_real::Vector{Float32}
    complex_signal_imag::Vector{Float32}
    status_flag::Vector{UInt8}
    count::Int64
end

function create_collector()::TickDataCollector
    return TickDataCollector(
        Int32[],
        Int64[],
        Int32[],
        Int32[],
        Float32[],
        Float32[],
        Float32[],
        UInt8[],
        Int64(0)
    )
end

function collect_message!(collector::TickDataCollector, msg::BroadcastMessage)
    push!(collector.tick_idx, msg.tick_idx)
    push!(collector.timestamp, msg.timestamp)
    push!(collector.raw_price, msg.raw_price)
    push!(collector.price_delta, msg.price_delta)
    push!(collector.normalization, msg.normalization)
    push!(collector.complex_signal_real, real(msg.complex_signal))
    push!(collector.complex_signal_imag, imag(msg.complex_signal))
    push!(collector.status_flag, msg.status_flag)
    collector.count += Int64(1)

    # Display counter every COUNTER_INTERVAL ticks
    if collector.count % COUNTER_INTERVAL == 0
        println(stderr, collector.count)
        flush(stderr)
    end
end

function save_to_jld2(collector::TickDataCollector, output_path::String)
    jldopen(output_path, "w") do file
        file["tick_idx"] = collector.tick_idx
        file["timestamp"] = collector.timestamp
        file["raw_price"] = collector.raw_price
        file["price_delta"] = collector.price_delta
        file["normalization"] = collector.normalization
        file["complex_signal_real"] = collector.complex_signal_real
        file["complex_signal_imag"] = collector.complex_signal_imag
        file["status_flag"] = collector.status_flag
        file["total_ticks"] = collector.count
    end
end

# Main execution
function main()
    # Create configuration with 1ms tick delay
    config = PipelineConfig(
        tick_file_path = TICK_FILE,
        flow_control = FlowControlConfig(delay_ms = TICK_DELAY_MS)
    )

    # Create triple split manager
    split_mgr = create_triple_split_manager()

    # Subscribe ProductionFilterConsumer (MONITORING = non-blocking)
    # Use large buffer to minimize drops
    consumer = subscribe_consumer!(split_mgr, "jld2_writer", MONITORING, Int32(65536))

    # Create data collector
    collector = create_collector()

    # Create pipeline manager
    pipeline_mgr = create_pipeline_manager(config, split_mgr)

    # Start pipeline in background (capture ALL ticks - full speed)
    pipeline_task = @async run_pipeline!(pipeline_mgr)

    # Consumer task: collect all messages
    consumer_task = @async begin
        try
            for msg in consumer.channel
                collect_message!(collector, msg)
            end
        catch e
            # Channel closed, finish gracefully
            if !isa(e, InvalidStateException)
                @warn "Consumer error" exception=e
            end
        end
        println(stderr, "Consumer finished: $(collector.count) messages collected")
        flush(stderr)
    end

    # Wait for pipeline to complete
    wait(pipeline_task)

    # Give consumer a moment to drain remaining messages
    sleep(1.0)

    # Close the channel to signal consumer to finish
    close(consumer.channel)

    # Wait for consumer to finish
    wait(consumer_task)

    # Save all collected data to JLD2 after BOTH tasks complete
    println(stderr, "Saving $(collector.count) ticks to $(OUTPUT_FILE)...")
    flush(stderr)
    save_to_jld2(collector, OUTPUT_FILE)
    println(stderr, "Save complete!")
    flush(stderr)

    # Final count display
    println(stderr, "Final count: $(collector.count)")
    flush(stderr)

    return collector.count
end

# Run
main()

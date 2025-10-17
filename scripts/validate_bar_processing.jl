# scripts/validate_bar_processing.jl - Full System Validation for Bar Processing
# Comprehensive validation with large dataset (5.8M ticks)

using TickDataPipeline
using Printf

println("="^80)
println("Bar Processing Full System Validation")
println("="^80)
println()

# Configuration
const TICK_FILE = "data/raw/YM 06-25.Last.txt"
const MAX_TICKS = Int64(50000)  # Process subset for validation (50k ticks = ~347 bars)
const TICKS_PER_BAR = Int32(144)

# Note: For full dataset validation (5.8M ticks), set MAX_TICKS = Int64(0)
# This will take ~5-10 minutes to complete

println("Configuration:")
println("  Tick file: $TICK_FILE")
println("  Ticks per bar: $TICKS_PER_BAR")
println("  Max ticks: ", MAX_TICKS == Int64(0) ? "ALL" : MAX_TICKS)
println()

# Validation counters
mutable struct ValidationStats
    total_ticks::Int64
    total_bars::Int64
    bar_completion_ticks::Int64
    ohlc_violations::Int32
    metadata_errors::Int32
    signal_errors::Int32
    flag_clipped_count::Int32
    first_bar_idx::Union{Int64, Nothing}
    last_bar_idx::Union{Int64, Nothing}
    min_bar_range::Int32
    max_bar_range::Int32
    sum_bar_range::Int64
end

function create_validation_stats()
    return ValidationStats(
        Int64(0), Int64(0), Int64(0), Int32(0), Int32(0), Int32(0), Int32(0),
        nothing, nothing, typemax(Int32), typemin(Int32), Int64(0)
    )
end

function validate_message!(msg::BroadcastMessage, stats::ValidationStats)
    stats.total_ticks += Int64(1)

    if msg.bar_idx !== nothing
        stats.total_bars += Int64(1)
        stats.bar_completion_ticks += Int64(1)

        # Track bar indices
        if stats.first_bar_idx === nothing
            stats.first_bar_idx = msg.bar_idx
        end
        stats.last_bar_idx = msg.bar_idx

        # Validate OHLC relationships
        if !(msg.bar_high_raw >= msg.bar_low_raw)
            @warn "OHLC violation: high < low" bar_idx=msg.bar_idx high=msg.bar_high_raw low=msg.bar_low_raw
            stats.ohlc_violations += Int32(1)
        end

        if !(msg.bar_high_raw >= msg.bar_open_raw)
            @warn "OHLC violation: high < open" bar_idx=msg.bar_idx high=msg.bar_high_raw open=msg.bar_open_raw
            stats.ohlc_violations += Int32(1)
        end

        if !(msg.bar_high_raw >= msg.bar_close_raw)
            @warn "OHLC violation: high < close" bar_idx=msg.bar_idx high=msg.bar_high_raw close=msg.bar_close_raw
            stats.ohlc_violations += Int32(1)
        end

        if !(msg.bar_low_raw <= msg.bar_open_raw)
            @warn "OHLC violation: low > open" bar_idx=msg.bar_idx low=msg.bar_low_raw open=msg.bar_open_raw
            stats.ohlc_violations += Int32(1)
        end

        if !(msg.bar_low_raw <= msg.bar_close_raw)
            @warn "OHLC violation: low > close" bar_idx=msg.bar_idx low=msg.bar_low_raw close=msg.bar_close_raw
            stats.ohlc_violations += Int32(1)
        end

        # Validate metadata
        if msg.bar_ticks != TICKS_PER_BAR
            @warn "Metadata error: bar_ticks mismatch" bar_idx=msg.bar_idx expected=TICKS_PER_BAR actual=msg.bar_ticks
            stats.metadata_errors += Int32(1)
        end

        if msg.bar_volume != TICKS_PER_BAR
            @warn "Metadata error: bar_volume mismatch" bar_idx=msg.bar_idx expected=TICKS_PER_BAR actual=msg.bar_volume
            stats.metadata_errors += Int32(1)
        end

        # Validate signals
        if msg.bar_normalization <= Float32(0)
            @warn "Signal error: invalid normalization" bar_idx=msg.bar_idx norm=msg.bar_normalization
            stats.signal_errors += Int32(1)
        end

        if isnan(real(msg.bar_complex_signal)) || isnan(imag(msg.bar_complex_signal))
            @warn "Signal error: NaN in complex signal" bar_idx=msg.bar_idx signal=msg.bar_complex_signal
            stats.signal_errors += Int32(1)
        end

        # Track bar range statistics
        bar_range = msg.bar_high_raw - msg.bar_low_raw
        stats.min_bar_range = min(stats.min_bar_range, bar_range)
        stats.max_bar_range = max(stats.max_bar_range, bar_range)
        stats.sum_bar_range += Int64(bar_range)

        # Track flags
        if (msg.bar_flags & FLAG_CLIPPED) != 0
            stats.flag_clipped_count += Int32(1)
        end
    end
end

function print_validation_report(stats::ValidationStats, pipeline_stats, bar_state::BarProcessorState)
    println()
    println("="^80)
    println("VALIDATION REPORT")
    println("="^80)
    println()

    println("Tick Processing:")
    println("  Total ticks processed: $(stats.total_ticks)")
    println("  Ticks with bar data: $(stats.bar_completion_ticks)")
    println("  Ticks without bar data: $(stats.total_ticks - stats.bar_completion_ticks)")
    println("  Bar completion rate: $(round(100.0 * stats.bar_completion_ticks / stats.total_ticks, digits=3))%")
    println()

    println("Bar Statistics:")
    println("  Total bars completed: $(stats.total_bars)")
    println("  First bar index: $(stats.first_bar_idx)")
    println("  Last bar index: $(stats.last_bar_idx)")
    println("  Expected bars: $(div(stats.total_ticks, TICKS_PER_BAR))")
    println("  Partial bar ticks: $(bar_state.tick_count)")
    println()

    println("Bar Range Statistics:")
    if stats.total_bars > Int64(0)
        avg_range = Float32(stats.sum_bar_range) / Float32(stats.total_bars)
        println("  Minimum bar range: $(stats.min_bar_range)")
        println("  Maximum bar range: $(stats.max_bar_range)")
        println("  Average bar range: $(round(avg_range, digits=2))")
    else
        println("  No bars completed")
    end
    println()

    println("Validation Results:")
    println("  OHLC violations: $(stats.ohlc_violations)")
    println("  Metadata errors: $(stats.metadata_errors)")
    println("  Signal errors: $(stats.signal_errors)")
    println("  Clipped bars: $(stats.flag_clipped_count)")
    println()

    println("Bar State (Final):")
    println("  Bars completed: $(bar_state.bars_completed)")
    println("  Current bar index: $(bar_state.bar_idx)")
    println("  Current tick count: $(bar_state.tick_count)")
    println("  Normalization factor: $(round(bar_state.cached_bar_normalization, digits=2))")
    println("  Ticks since recalc: $(bar_state.ticks_since_recalc)")
    println("  Sum high: $(bar_state.sum_bar_average_high)")
    println("  Sum low: $(bar_state.sum_bar_average_low)")
    println()

    println("Pipeline Performance:")
    println("  Ticks processed: $(pipeline_stats.ticks_processed)")
    println("  Broadcasts sent: $(pipeline_stats.broadcasts_sent)")
    println("  Errors: $(pipeline_stats.errors)")
    println("  Average latency: $(round(pipeline_stats.avg_latency_us, digits=2))μs")
    println("  Maximum latency: $(pipeline_stats.max_latency_us)μs")
    println("  Minimum latency: $(pipeline_stats.min_latency_us)μs")
    println("  Avg signal time: $(round(pipeline_stats.avg_signal_time_us, digits=2))μs")
    println("  Avg broadcast time: $(round(pipeline_stats.avg_broadcast_time_us, digits=2))μs")
    println()

    # Overall validation result
    all_passed = (stats.ohlc_violations == Int32(0)) &&
                 (stats.metadata_errors == Int32(0)) &&
                 (stats.signal_errors == Int32(0)) &&
                 (stats.total_bars == div(stats.total_ticks, TICKS_PER_BAR)) &&
                 (bar_state.bars_completed == stats.total_bars)

    println("="^80)
    if all_passed
        println("✓ VALIDATION PASSED - All checks successful")
    else
        println("✗ VALIDATION FAILED - See errors above")
    end
    println("="^80)
    println()

    return all_passed
end

# Test 1: Full dataset with bar processing enabled
println("Test 1: Full Dataset Validation (Bar Processing Enabled)")
println("-"^80)

config_enabled = PipelineConfig(
    tick_file_path = TICK_FILE,
    bar_processing = BarProcessingConfig(
        enabled = true,
        ticks_per_bar = TICKS_PER_BAR,
        normalization_window_bars = Int32(24),
        winsorize_bar_threshold = Int32(50),
        max_bar_jump = Int32(100),
        bar_derivative_imag_scale = Float32(4.0)
    )
)

split_mgr_enabled = create_triple_split_manager()
consumer_enabled = subscribe_consumer!(split_mgr_enabled, "validator_enabled", MONITORING, Int32(8192))
pipeline_mgr_enabled = create_pipeline_manager(config_enabled, split_mgr_enabled)

# Start pipeline
println("Starting pipeline...")
pipeline_task = @async run_pipeline!(pipeline_mgr_enabled, max_ticks=MAX_TICKS)

# Consume and validate
println("Validating messages...")
stats_enabled = create_validation_stats()

progress_interval = Int64(10000)

for msg in consumer_enabled.channel
    validate_message!(msg, stats_enabled)

    # Progress reporting
    if stats_enabled.total_ticks % progress_interval == Int64(0)
        println("  Progress: $(stats_enabled.total_ticks) ticks, $(stats_enabled.total_bars) bars")
    end
end

# Wait for pipeline
wait(pipeline_task)

# Get pipeline stats
pipeline_stats_enabled = (
    ticks_processed = pipeline_mgr_enabled.metrics.ticks_processed,
    broadcasts_sent = pipeline_mgr_enabled.metrics.broadcasts_sent,
    errors = pipeline_mgr_enabled.metrics.errors,
    avg_latency_us = Float32(pipeline_mgr_enabled.metrics.total_latency_us) / Float32(pipeline_mgr_enabled.metrics.ticks_processed),
    max_latency_us = pipeline_mgr_enabled.metrics.max_latency_us,
    min_latency_us = pipeline_mgr_enabled.metrics.min_latency_us == typemax(Int32) ? Int32(0) : pipeline_mgr_enabled.metrics.min_latency_us,
    avg_signal_time_us = Float32(pipeline_mgr_enabled.metrics.signal_processing_time_us) / Float32(pipeline_mgr_enabled.metrics.ticks_processed),
    avg_broadcast_time_us = Float32(pipeline_mgr_enabled.metrics.broadcast_time_us) / Float32(pipeline_mgr_enabled.metrics.ticks_processed)
)

# Print report
validation_passed = print_validation_report(stats_enabled, pipeline_stats_enabled, pipeline_mgr_enabled.bar_state)

# Test 2: Compare with bar processing disabled (baseline performance)
println()
println("Test 2: Baseline Performance (Bar Processing Disabled)")
println("-"^80)

# Use smaller subset for baseline (10k ticks for quick comparison)
baseline_ticks = min(Int64(10000), MAX_TICKS)

config_disabled = PipelineConfig(
    tick_file_path = TICK_FILE,
    bar_processing = BarProcessingConfig(
        enabled = false,
        ticks_per_bar = TICKS_PER_BAR
    )
)

split_mgr_disabled = create_triple_split_manager()
consumer_disabled = subscribe_consumer!(split_mgr_disabled, "validator_disabled", MONITORING, Int32(8192))
pipeline_mgr_disabled = create_pipeline_manager(config_disabled, split_mgr_disabled)

# Start pipeline
println("Starting baseline pipeline ($(baseline_ticks) ticks for comparison)...")
pipeline_task_disabled = @async run_pipeline!(pipeline_mgr_disabled, max_ticks=baseline_ticks)

# Consume (no validation needed)
stats_disabled = create_validation_stats()
for msg in consumer_disabled.channel
    stats_disabled.total_ticks += Int64(1)

    # Progress reporting
    if stats_disabled.total_ticks % progress_interval == Int64(0)
        println("  Progress: $(stats_disabled.total_ticks) ticks")
    end
end

wait(pipeline_task_disabled)

# Get pipeline stats
pipeline_stats_disabled = (
    ticks_processed = pipeline_mgr_disabled.metrics.ticks_processed,
    broadcasts_sent = pipeline_mgr_disabled.metrics.broadcasts_sent,
    errors = pipeline_mgr_disabled.metrics.errors,
    avg_latency_us = Float32(pipeline_mgr_disabled.metrics.total_latency_us) / Float32(pipeline_mgr_disabled.metrics.ticks_processed),
    max_latency_us = pipeline_mgr_disabled.metrics.max_latency_us,
    min_latency_us = pipeline_mgr_disabled.metrics.min_latency_us == typemax(Int32) ? Int32(0) : pipeline_mgr_disabled.metrics.min_latency_us
)

println()
println("Baseline Results:")
println("  Ticks processed: $(pipeline_stats_disabled.ticks_processed)")
println("  Average latency: $(round(pipeline_stats_disabled.avg_latency_us, digits=2))μs")
println("  Maximum latency: $(pipeline_stats_disabled.max_latency_us)μs")
println()

# Performance comparison
println("="^80)
println("PERFORMANCE COMPARISON")
println("="^80)
println()

overhead_ratio = pipeline_stats_enabled.avg_latency_us / max(pipeline_stats_disabled.avg_latency_us, Float32(0.01))

println("Latency Comparison:")
println("  Baseline (disabled): $(round(pipeline_stats_disabled.avg_latency_us, digits=2))μs")
println("  With bar processing: $(round(pipeline_stats_enabled.avg_latency_us, digits=2))μs")
println("  Overhead ratio: $(round(overhead_ratio, digits=2))x")
println("  Overhead acceptable: ", overhead_ratio < Float32(3.0) ? "✓ YES" : "✗ NO")
println()

println("Throughput Comparison:")
baseline_tps = Float32(1_000_000) / max(pipeline_stats_disabled.avg_latency_us, Float32(0.01))
enabled_tps = Float32(1_000_000) / max(pipeline_stats_enabled.avg_latency_us, Float32(0.01))
println("  Baseline throughput: $(round(baseline_tps, digits=0)) ticks/sec")
println("  With bar processing: $(round(enabled_tps, digits=0)) ticks/sec")
println()

# Final summary
println("="^80)
println("FINAL SUMMARY")
println("="^80)
println()

println("Validation: ", validation_passed ? "✓ PASSED" : "✗ FAILED")
println("Performance: ", overhead_ratio < Float32(3.0) ? "✓ ACCEPTABLE" : "✗ UNACCEPTABLE")
println("Errors: ", pipeline_stats_enabled.errors == Int32(0) ? "✓ NONE" : "✗ $(pipeline_stats_enabled.errors) errors")
println()

if validation_passed && overhead_ratio < Float32(3.0) && pipeline_stats_enabled.errors == Int32(0)
    println("="^80)
    println("✓✓✓ ALL TESTS PASSED ✓✓✓")
    println("="^80)
    exit(0)
else
    println("="^80)
    println("✗✗✗ SOME TESTS FAILED ✗✗✗")
    println("="^80)
    exit(1)
end

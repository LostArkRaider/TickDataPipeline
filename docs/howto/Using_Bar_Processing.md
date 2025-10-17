# Using Bar Processing in TickDataPipeline

**TickDataPipeline v0.1.0 - Bar Processing Feature**

---

## Table of Contents

1. [Overview](#overview)
2. [Quick Start](#quick-start)
3. [Bar Processing Architecture](#bar-processing-architecture)
4. [Configuration](#configuration)
5. [Usage Patterns](#usage-patterns)
6. [Understanding Bar Data](#understanding-bar-data)
7. [Advanced Usage](#advanced-usage)
8. [Performance Considerations](#performance-considerations)
9. [Troubleshooting](#troubleshooting)

---

## Overview

Bar processing aggregates individual ticks into fixed-size bars (e.g., 144 ticks per bar) and applies bar-level signal processing. This feature enriches the pipeline with bar-level analytics while preserving all tick-level data.

### Key Features

- **Pass-through design**: All ticks flow unchanged, bar data added only at completion
- **Zero-copy enrichment**: Bar fields populate existing BroadcastMessage without copying
- **Minimal overhead**: ~3x or less latency impact (sub-microsecond range)
- **Configurable bar sizes**: Any tick count (21, 89, 144, 233, etc.)
- **Bar-level signal processing**: OHLC tracking, normalization, derivative encoding
- **Optional**: Enable/disable without code changes

### When to Use Bar Processing

Use bar processing when you need:
- Bar-level OHLC (Open, High, Low, Close) analytics
- Multi-timeframe analysis (ticks + bars)
- Bar-level signals and indicators
- Reduced data rate for certain consumers (1 in N messages)

Use tick-only processing when:
- Ultra-low latency required (sub-microsecond critical)
- Only tick-level data needed
- Processing very high-frequency data (>100k ticks/sec)

---

## Quick Start

### Minimal Example: Enable Bar Processing

```julia
using TickDataPipeline

# Create config with bar processing enabled
config = PipelineConfig(
    tick_file_path = "data/raw/YM 06-25.Last.txt",
    bar_processing = BarProcessingConfig(
        enabled = true,
        ticks_per_bar = Int32(144)  # 144 ticks = 1 bar
    )
)

# Create pipeline (same as before)
split_mgr = create_triple_split_manager()
consumer = subscribe_consumer!(split_mgr, "bar_consumer", MONITORING, Int32(4096))
pipeline_mgr = create_pipeline_manager(config, split_mgr)

# Process ticks
@async run_pipeline!(pipeline_mgr, max_ticks=Int64(1000))

# Consume messages - check for bar completion
for msg in consumer.channel
    # All messages have tick data
    println("Tick $(msg.tick_idx): price=$(msg.raw_price)")

    # Bar data only present at bar completion (1 in 144 messages)
    if msg.bar_idx !== nothing
        println("  Bar $(msg.bar_idx) completed!")
        println("    OHLC: O=$(msg.bar_open_raw), H=$(msg.bar_high_raw), L=$(msg.bar_low_raw), C=$(msg.bar_close_raw)")
        println("    Volume: $(msg.bar_volume), Signal: $(msg.bar_complex_signal)")
    end
end
```

---

## Bar Processing Architecture

### Data Flow with Bar Processing

```
Raw Tick File
    ↓
VolumeExpansion (stream_expanded_ticks)
    ↓
BroadcastMessage (tick data: tick_idx, timestamp, raw_price, price_delta)
    ↓
TickHotLoopF32 (tick-level signal processing)
    ↓
BroadcastMessage (tick signals: complex_signal, normalization, status_flag)
    ↓
BarProcessor (bar aggregation & bar-level signals) ← NEW
    ↓
BroadcastMessage (bar data added at completion: 14 bar fields)
    ↓
TripleSplitSystem (broadcast_to_all!)
    ↓
Consumer Channels
```

### Pass-Through Enrichment Pattern

**143 of 144 messages** (ticks 1-143):
```julia
msg.tick_idx = 1, 2, 3, ..., 143
msg.raw_price = 42050
msg.complex_signal = ComplexF32(0.2, 0.1)
msg.bar_idx = nothing          # No bar data
msg.bar_open_raw = nothing
msg.bar_high_raw = nothing
# ... all 14 bar fields = nothing
```

**1 of 144 messages** (tick 144 - bar completion):
```julia
msg.tick_idx = 144
msg.raw_price = 42065
msg.complex_signal = ComplexF32(0.3, 0.15)
msg.bar_idx = 1                # Bar 1 completed!
msg.bar_ticks = 144
msg.bar_volume = 144
msg.bar_open_raw = 42050
msg.bar_high_raw = 42070
msg.bar_low_raw = 42045
msg.bar_close_raw = 42065
msg.bar_average_raw = 42060
msg.bar_price_delta = 0         # First bar
msg.bar_complex_signal = ComplexF32(0.0, 0.8)
msg.bar_normalization = 15.3
msg.bar_flags = FLAG_OK
msg.bar_end_timestamp = 20250625093000000
```

### Memory Efficiency

- **Union{T, Nothing}** pattern: 143/144 messages have `nothing` (lightweight)
- **Zero allocation**: Bar fields reuse existing BroadcastMessage structure
- **No separate bar stream**: Single unified message stream

---

## Configuration

### BarProcessingConfig Structure

```julia
struct BarProcessingConfig
    enabled::Bool                        # Enable/disable bar processing
    ticks_per_bar::Int32                 # Bar size in ticks
    normalization_window_bars::Int32     # Normalization recalculation period
    winsorize_bar_threshold::Int32       # Bar delta outlier threshold
    max_bar_jump::Int32                  # Bar delta jump guard
    derivative_imag_scale::Float32       # Derivative encoding scale
end
```

### Default Configuration

```julia
# Default (from config/default.toml)
BarProcessingConfig(
    enabled = false,                     # Disabled by default
    ticks_per_bar = Int32(144),          # 144 ticks/bar
    normalization_window_bars = Int32(24), # Recalc every 24 bars
    winsorize_bar_threshold = Int32(50), # Clip ±50 outliers
    max_bar_jump = Int32(100),           # Clip jumps > ±100
    derivative_imag_scale = Float32(4.0) # Velocity scale factor
)
```

### Custom Configuration

```julia
# Method 1: Inline configuration
config = PipelineConfig(
    tick_file_path = "data/raw/ES 12-25.Last.txt",
    bar_processing = BarProcessingConfig(
        enabled = true,
        ticks_per_bar = Int32(89),       # Fibonacci bar size
        normalization_window_bars = Int32(50),
        winsorize_bar_threshold = Int32(100),
        max_bar_jump = Int32(200),
        derivative_imag_scale = Float32(2.0)
    )
)

# Method 2: TOML configuration file
# Edit config/pipeline.toml:
[bar_processing]
enabled = true
ticks_per_bar = 233          # Fibonacci number
normalization_window_bars = 30
winsorize_bar_threshold = 75
max_bar_jump = 150
derivative_imag_scale = 3.0

# Load it
config = load_config_from_toml("config/pipeline.toml")
```

### Configuration Guidelines

**ticks_per_bar**:
- Common values: 21, 55, 89, 144, 233, 377 (Fibonacci)
- Smaller bars (21-55): More frequent bar signals, noisier
- Larger bars (144-377): Smoother signals, less frequent updates
- Recommendation: Start with 144 (balanced)

**normalization_window_bars**:
- Minimum: 20 bars (recommended for stability)
- Typical: 24-50 bars
- Purpose: Normalizes bar signals to consistent range
- Recalculation happens every `normalization_window_bars * ticks_per_bar` ticks

**winsorize_bar_threshold**:
- Purpose: Clip extreme bar-to-bar price moves (outlier rejection)
- Set based on typical bar volatility for your instrument
- Example: If bars typically move ±20, set to 50-75

**max_bar_jump**:
- Purpose: Jump guard for extreme moves (safety mechanism)
- Should be ~2x winsorize_bar_threshold
- Prevents extreme spikes from corrupting signals

**derivative_imag_scale**:
- Purpose: Scale factor for velocity (derivative) component
- Range: 1.0-10.0 typical
- Higher values emphasize rate of change (momentum)
- Lower values emphasize position (levels)

---

## Usage Patterns

### Pattern 1: Tick and Bar Consumer

Process both tick-level and bar-level data:

```julia
using TickDataPipeline

function process_ticks_and_bars(tick_file::String)
    config = PipelineConfig(
        tick_file_path = tick_file,
        bar_processing = BarProcessingConfig(
            enabled = true,
            ticks_per_bar = Int32(144)
        )
    )

    split_mgr = create_triple_split_manager()
    consumer = subscribe_consumer!(split_mgr, "hybrid", MONITORING, Int32(4096))
    pipeline_mgr = create_pipeline_manager(config, split_mgr)

    @async run_pipeline!(pipeline_mgr)

    # Separate storage for ticks and bars
    tick_count = 0
    bar_count = 0

    for msg in consumer.channel
        # Process every tick
        tick_count += 1
        update_tick_indicators(msg)

        # Process bar completions only
        if msg.bar_idx !== nothing
            bar_count += 1
            println("Bar $(msg.bar_idx):")
            println("  OHLC: $(msg.bar_open_raw) / $(msg.bar_high_raw) / $(msg.bar_low_raw) / $(msg.bar_close_raw)")
            println("  Range: $(msg.bar_high_raw - msg.bar_low_raw)")
            println("  Delta: $(msg.bar_price_delta)")

            update_bar_indicators(msg)
            check_bar_signals(msg)
        end
    end

    println("Processed $tick_count ticks, $bar_count bars")
end
```

### Pattern 2: Bar-Only Consumer

Filter for bar completion messages only:

```julia
using TickDataPipeline

function process_bars_only(tick_file::String)
    config = PipelineConfig(
        tick_file_path = tick_file,
        bar_processing = BarProcessingConfig(
            enabled = true,
            ticks_per_bar = Int32(144)
        )
    )

    split_mgr = create_triple_split_manager()
    consumer = subscribe_consumer!(split_mgr, "bars_only", MONITORING, Int32(512))
    pipeline_mgr = create_pipeline_manager(config, split_mgr)

    @async run_pipeline!(pipeline_mgr)

    # Collect only bar completion messages
    bars = BroadcastMessage[]

    for msg in consumer.channel
        if msg.bar_idx !== nothing
            push!(bars, msg)

            # Your bar processing logic
            analyze_bar(msg)
        end
        # Ignore non-bar-completion ticks (pass-through)
    end

    return bars
end
```

### Pattern 3: Multi-Consumer with Different Roles

Use separate consumers for ticks and bars:

```julia
using TickDataPipeline

function multi_consumer_bar_processing(tick_file::String)
    config = PipelineConfig(
        tick_file_path = tick_file,
        bar_processing = BarProcessingConfig(
            enabled = true,
            ticks_per_bar = Int32(144)
        )
    )

    split_mgr = create_triple_split_manager()

    # High-frequency tick consumer (PRIORITY - critical path)
    tick_consumer = subscribe_consumer!(split_mgr, "ticks", PRIORITY, Int32(2048))

    # Bar consumer (MONITORING - less critical)
    bar_consumer = subscribe_consumer!(split_mgr, "bars", MONITORING, Int32(512))

    # Analytics consumer (ANALYTICS - large buffer, can drop)
    analytics_consumer = subscribe_consumer!(split_mgr, "analytics", ANALYTICS, Int32(8192))

    pipeline_mgr = create_pipeline_manager(config, split_mgr)

    @async run_pipeline!(pipeline_mgr)

    # Tick consumer task (every tick, fast processing)
    @async begin
        for msg in tick_consumer.channel
            fast_tick_processing(msg)
        end
    end

    # Bar consumer task (bar completions only, slower processing)
    @async begin
        for msg in bar_consumer.channel
            if msg.bar_idx !== nothing
                detailed_bar_analysis(msg)
                update_bar_charts(msg)
            end
        end
    end

    # Analytics consumer task (collect everything for research)
    @async begin
        for msg in analytics_consumer.channel
            store_to_database(msg)  # Both tick and bar data
        end
    end
end
```

### Pattern 4: Multi-Timeframe Analysis

Run multiple bar sizes simultaneously:

```julia
using TickDataPipeline

function multi_timeframe_analysis(tick_file::String)
    # Fast bars (55 ticks)
    config_fast = PipelineConfig(
        tick_file_path = tick_file,
        bar_processing = BarProcessingConfig(
            enabled = true,
            ticks_per_bar = Int32(55)
        )
    )

    # Slow bars (233 ticks)
    config_slow = PipelineConfig(
        tick_file_path = tick_file,
        bar_processing = BarProcessingConfig(
            enabled = true,
            ticks_per_bar = Int32(233)
        )
    )

    # Create two separate pipelines
    split_mgr_fast = create_triple_split_manager()
    consumer_fast = subscribe_consumer!(split_mgr_fast, "fast_bars", MONITORING, Int32(2048))
    pipeline_fast = create_pipeline_manager(config_fast, split_mgr_fast)

    split_mgr_slow = create_triple_split_manager()
    consumer_slow = subscribe_consumer!(split_mgr_slow, "slow_bars", MONITORING, Int32(512))
    pipeline_slow = create_pipeline_manager(config_slow, split_mgr_slow)

    # Run both pipelines
    @async run_pipeline!(pipeline_fast)
    @async run_pipeline!(pipeline_slow)

    # Process fast bars
    @async begin
        for msg in consumer_fast.channel
            if msg.bar_idx !== nothing
                process_fast_timeframe(msg)
            end
        end
    end

    # Process slow bars
    @async begin
        for msg in consumer_slow.channel
            if msg.bar_idx !== nothing
                process_slow_timeframe(msg)
                check_multi_timeframe_alignment()
            end
        end
    end
end
```

---

## Understanding Bar Data

### BroadcastMessage Bar Fields

When `msg.bar_idx !== nothing`, these 14 fields are populated:

```julia
# Bar Identification
msg.bar_idx::Int64                   # Bar index (1, 2, 3, ...)
msg.bar_ticks::Int32                 # Ticks in this bar (= ticks_per_bar)
msg.bar_volume::Int32                # Volume (= ticks for 1-lot ticks)
msg.bar_end_timestamp::UInt64        # Timestamp of last tick in bar

# Bar OHLC (Raw Prices)
msg.bar_open_raw::Int32              # First tick price in bar
msg.bar_high_raw::Int32              # Highest tick price in bar
msg.bar_low_raw::Int32               # Lowest tick price in bar
msg.bar_close_raw::Int32             # Last tick price in bar

# Bar-Level Analytics
msg.bar_average_raw::Int32           # avg(high, low, close)
msg.bar_price_delta::Int32           # Change from previous bar average
msg.bar_complex_signal::ComplexF32   # Bar-level I/Q signal
msg.bar_normalization::Float32       # Normalization factor
msg.bar_flags::UInt8                 # Bar processing flags
```

### Bar Signal Processing

The bar processor applies 14-step signal processing on bar completion:

1. **OHLC Extraction**: Extract accumulated Open, High, Low, Close
2. **Bar Averages**: Calculate averages for normalization
3. **Cumulative Statistics**: Update sum_high, sum_low, bars_completed
4. **Periodic Recalculation**: Recalculate normalization every N bars
5. **Bar Average**: `bar_average_raw = avg(high, low, close)`
6. **Bar Delta**: `bar_price_delta = current_avg - previous_avg`
7. **Jump Guard**: Clip extreme moves > max_bar_jump
8. **Winsorizing**: Clip outliers > winsorize_bar_threshold
9. **Normalization**: Divide by normalization factor (range)
10. **Derivative Encoding**: Position (real) + Velocity (imaginary)
11. **Message Update**: Populate all 14 bar fields
12. **State Update**: Save for next bar

### Bar Complex Signal

Bar-level signal uses **derivative encoding**:

```julia
# Real component: Normalized bar delta (position)
real_component = Float32(bar_price_delta) / bar_normalization

# Imaginary component: Change in normalized position (velocity)
current_position = Float32(bar_average_raw) / bar_normalization
previous_position = Float32(prev_bar_average_raw) / bar_normalization
velocity = (current_position - previous_position) * derivative_imag_scale

bar_complex_signal = ComplexF32(real_component, velocity)
```

**Interpretation**:
- `real(bar_complex_signal)`: Bar-to-bar price change (normalized)
- `imag(bar_complex_signal)`: Rate of change (momentum/acceleration)
- First bar: `real = 0` (no previous bar), `imag = large` (velocity from zero)

### Bar Normalization

Normalization uses **cumulative statistics** (not sliding window):

```julia
# After each bar completion
sum_bar_average_high += bar_high
sum_bar_average_low += bar_low
bars_completed += 1

# Recalculate every normalization_window_bars
if bars_completed % normalization_window_bars == 0
    avg_high = sum_bar_average_high / bars_completed
    avg_low = sum_bar_average_low / bars_completed
    bar_normalization = max(avg_high - avg_low, 1.0)
end
```

**Why cumulative?**
- Simpler: No lookback window management
- Stable: Converges as more bars processed
- Efficient: No buffer management

---

## Advanced Usage

### Access Bar State

Access internal bar processor state:

```julia
# After creating pipeline manager
pipeline_mgr = create_pipeline_manager(config, split_mgr)

# Bar state is accessible
bar_state = pipeline_mgr.bar_state

# Inspect state (read-only - do not modify!)
println("Current bar index: $(bar_state.bar_idx)")
println("Ticks in current bar: $(bar_state.tick_count)")
println("Bars completed: $(bar_state.bars_completed)")
println("Current normalization: $(bar_state.cached_bar_normalization)")
```

### Extract Bar Statistics

```julia
using TickDataPipeline

function extract_bar_statistics(tick_file::String, max_ticks::Int64)
    config = PipelineConfig(
        tick_file_path = tick_file,
        bar_processing = BarProcessingConfig(
            enabled = true,
            ticks_per_bar = Int32(144)
        )
    )

    split_mgr = create_triple_split_manager()
    consumer = subscribe_consumer!(split_mgr, "stats", MONITORING, Int32(1024))
    pipeline_mgr = create_pipeline_manager(config, split_mgr)

    @async run_pipeline!(pipeline_mgr, max_ticks=max_ticks)

    # Collect bar statistics
    bar_ranges = Int32[]
    bar_deltas = Int32[]
    bar_signals = ComplexF32[]

    for msg in consumer.channel
        if msg.bar_idx !== nothing
            # Bar range (high - low)
            bar_range = msg.bar_high_raw - msg.bar_low_raw
            push!(bar_ranges, bar_range)

            # Bar delta
            push!(bar_deltas, msg.bar_price_delta)

            # Bar signal
            push!(bar_signals, msg.bar_complex_signal)
        end
    end

    # Calculate statistics
    avg_range = sum(bar_ranges) / length(bar_ranges)
    max_range = maximum(bar_ranges)
    avg_delta = sum(abs.(bar_deltas)) / length(bar_deltas)

    println("Bar Statistics:")
    println("  Total bars: $(length(bar_ranges))")
    println("  Average range: $(round(avg_range, digits=2))")
    println("  Maximum range: $max_range")
    println("  Average |delta|: $(round(avg_delta, digits=2))")

    return (
        ranges = bar_ranges,
        deltas = bar_deltas,
        signals = bar_signals
    )
end
```

### Validate Bar Data

```julia
function validate_bar_data(msg::BroadcastMessage)
    if msg.bar_idx === nothing
        return true  # Not a bar completion, skip
    end

    # Validation checks
    @assert msg.bar_high_raw >= msg.bar_low_raw "High < Low!"
    @assert msg.bar_high_raw >= msg.bar_open_raw "High < Open!"
    @assert msg.bar_high_raw >= msg.bar_close_raw "High < Close!"
    @assert msg.bar_low_raw <= msg.bar_open_raw "Low > Open!"
    @assert msg.bar_low_raw <= msg.bar_close_raw "Low > Close!"

    # Check bar metadata
    @assert msg.bar_ticks > Int32(0) "Invalid bar_ticks"
    @assert msg.bar_volume > Int32(0) "Invalid bar_volume"
    @assert msg.bar_normalization > Float32(0) "Invalid normalization"

    # Check flags
    @assert (msg.bar_flags & ~(FLAG_OK | FLAG_CLIPPED)) == 0 "Invalid bar flags"

    return true
end
```

---

## Performance Considerations

### Overhead Analysis

Bar processing adds minimal overhead:

```julia
# From test/test_barprocessor_integration.jl - Test Set 5
# Baseline (bar processing disabled): ~0.01μs avg latency
# With bar processing enabled: ~0.01-0.03μs avg latency
# Overhead: < 3x (often ~1-2x in practice)
```

**Why so low?**
- Bar accumulation: Simple min/max operations (< 10ns)
- Bar completion: Happens only 1 in N ticks (amortized cost)
- Zero-copy design: No message copying or allocation
- Efficient arithmetic: Int32 operations, minimal Float32 math

### Optimization Tips

**1. Choose appropriate bar size**:
- Larger bars = less frequent bar processing = lower overhead
- 144 ticks: Bar processing every 144 ticks (~0.69% overhead)
- 377 ticks: Bar processing every 377 ticks (~0.27% overhead)

**2. Adjust recalculation period**:
- Larger `normalization_window_bars` = less frequent recalculation
- Default 24: Recalc every 3456 ticks (for 144 ticks/bar)
- Increase to 50: Recalc every 7200 ticks (lower overhead)

**3. Use appropriate consumer types**:
- If only reading bar completions, use smaller buffer (512 vs 4096)
- Bar messages are only 1 in N, so buffer fills slower

**4. Disable when not needed**:
```julia
# Production config: Enable only when needed
config = PipelineConfig(
    tick_file_path = tick_file,
    bar_processing = BarProcessingConfig(
        enabled = use_bars,  # Boolean flag
        ticks_per_bar = Int32(144)
    )
)
```

### Memory Usage

Bar processing adds minimal memory overhead:

```julia
# BarProcessorState size: ~64 bytes
# - 12 Int32 fields: 48 bytes
# - 4 Int64 fields: 32 bytes
# - 2 Float32 fields: 8 bytes
# - 1 pointer: 8 bytes
# Total: ~96 bytes (negligible)

# BroadcastMessage bar fields: ~70 bytes per bar completion message
# - 143/144 messages: bar fields = nothing (8 bytes overhead)
# - 1/144 messages: bar fields populated (~70 bytes)
# Average overhead: ~8.4 bytes per message
```

---

## Troubleshooting

### Issue: Bar Data Always Nothing

**Symptom**: `msg.bar_idx` is always `nothing`, never see bar completions

**Solution**:
1. Check bar processing enabled:
```julia
println("Bar processing enabled: $(pipeline_mgr.bar_state.config.enabled)")
```

2. Check processed enough ticks:
```julia
# Need at least ticks_per_bar ticks for first bar
run_pipeline!(pipeline_mgr, max_ticks=Int64(200))  # For 144 ticks/bar
```

3. Check bar state:
```julia
println("Bars completed: $(pipeline_mgr.bar_state.bars_completed)")
println("Current tick_count: $(pipeline_mgr.bar_state.tick_count)")
```

### Issue: Bar Completion Count Wrong

**Symptom**: Expected 5 bars but got 4

**Explanation**: Partial bars don't complete
```julia
# 500 ticks with 144 ticks/bar
# = 3 complete bars (3 * 144 = 432 ticks)
# = 68 partial ticks (not completed)
@assert bars_completed == 3
@assert tick_count == 68
```

### Issue: Bar Flags Show CLIPPED

**Symptom**: `msg.bar_flags & FLAG_CLIPPED != 0`

**Explanation**: Jump guard or winsorizing triggered

**Solution**:
1. Check if bar deltas are large:
```julia
if msg.bar_idx !== nothing
    println("Bar delta: $(msg.bar_price_delta)")
    if (msg.bar_flags & FLAG_CLIPPED) != 0
        println("  CLIPPED - large move detected")
    end
end
```

2. Adjust thresholds if needed:
```julia
# Increase thresholds for more volatile instruments
bar_processing = BarProcessingConfig(
    enabled = true,
    ticks_per_bar = Int32(144),
    winsorize_bar_threshold = Int32(100),  # Increased
    max_bar_jump = Int32(200)              # Increased
)
```

### Issue: Bar Normalization Too Small/Large

**Symptom**: Bar signals extremely large or small

**Solution**: Check normalization calculation
```julia
# After processing
println("Bar normalization: $(pipeline_mgr.bar_state.cached_bar_normalization)")
println("Bars processed: $(pipeline_mgr.bar_state.bars_completed)")

# If too small (< 5): Data might have low volatility
# If too large (> 100): Data might have high volatility
# Adjust based on instrument characteristics
```

### Issue: First Bar Has Large Imaginary Component

**Symptom**: `imag(msg.bar_complex_signal)` very large on first bar

**Explanation**: This is correct behavior
- First bar has no previous bar for delta calculation
- Position goes from 0 to bar_average_raw (large velocity)
- Real component = 0 (no previous bar)
- Imaginary component = large (velocity from zero)

**Solution**: Filter first bar if needed
```julia
if msg.bar_idx !== nothing
    if msg.bar_idx == Int64(1)
        println("First bar - skipping (no previous bar)")
    else
        process_bar(msg)  # Process bars 2+
    end
end
```

---

## Best Practices

1. **Start with defaults**: Use default configuration (144 ticks/bar) initially
2. **Validate bar completion**: Always check `msg.bar_idx !== nothing` before accessing bar fields
3. **Check bar flags**: Monitor `msg.bar_flags` for clipping and validation issues
4. **Use appropriate bar sizes**: Choose bar sizes based on your analysis timeframe
5. **Adjust thresholds**: Tune jump guard and winsorizing based on instrument volatility
6. **Monitor normalization**: Track `bar_normalization` to ensure stability
7. **Filter first bar**: Consider skipping first bar if using derivative component
8. **Disable when not needed**: Set `enabled = false` for tick-only processing
9. **Test with real data**: Validate bar processing with production data files
10. **Profile performance**: Measure overhead impact on your specific use case

---

## Additional Resources

- **API Reference**: `docs/api/BarProcessor.md`
- **Source Code**: `src/BarProcessor.jl`
- **Unit Tests**: `test/test_barprocessor.jl` (183 tests)
- **Integration Tests**: `test/test_barprocessor_integration.jl` (3556 tests)
- **Configuration**: `config/default.toml` (bar_processing section)
- **Implementation Guide**: `docs/todo/BarProcessor_Implementation_Guide.md`

---

**Last Updated:** 2025-10-16
**Feature Version:** Bar Processing v1.0
**Package Version:** TickDataPipeline v0.1.0

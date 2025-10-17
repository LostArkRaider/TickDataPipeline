# BarProcessor API Reference

**Module**: `TickDataPipeline.BarProcessor`
**File**: `src/BarProcessor.jl`
**Version**: 1.0

---

## Table of Contents

1. [Overview](#overview)
2. [Exported Types](#exported-types)
3. [Exported Functions](#exported-functions)
4. [Internal Functions](#internal-functions)
5. [Message Fields](#message-fields)
6. [Configuration](#configuration)
7. [State Management](#state-management)
8. [Signal Processing Pipeline](#signal-processing-pipeline)
9. [Examples](#examples)

---

## Overview

The BarProcessor module provides bar-level aggregation and signal processing for tick data. It implements a pass-through enrichment pattern where all ticks flow unchanged, with bar fields populated only at bar completion (1 in N messages).

### Design Principles

- **Pass-through**: All ticks preserved, bar data added on completion
- **Zero-copy**: Bar fields reuse existing BroadcastMessage structure
- **In-place updates**: Modifies messages without allocation
- **Stateful processing**: Maintains OHLC accumulation and normalization statistics
- **Configurable**: Enable/disable without code changes

### Integration Point

Bar processing integrates into the pipeline between tick signal processing and broadcasting.

**Recommended Usage Patterns**:

1. **High-Level Interface** (Recommended for most use cases):
```julia
# Use run_pipeline! - handles everything internally
stats = run_pipeline!(pipeline_mgr, max_ticks=1000)
```

2. **Manual Component Assembly** (For custom pipelines):
```julia
# Build your own loop with component functions
tick_channel = stream_expanded_ticks(tick_file, 0.0)
tick_state = create_tickhotloop_state()
bar_state = create_bar_processor_state(config)

for msg in tick_channel
    process_tick_signal!(msg, tick_state, ...)      # Tick signals
    process_tick_for_bars!(msg, bar_state)          # Bar processing (NEW)
    broadcast_to_all!(split_manager, msg)           # Broadcasting
end
```

**Note**: `process_single_tick_through_pipeline!` is an internal function (not exported). Use the patterns above instead.

---

## Exported Types

### BarProcessorState

Maintains state for bar aggregation and signal processing.

```julia
mutable struct BarProcessorState
    # Current bar accumulation (reset every bar)
    tick_count::Int32
    bar_idx::Int64
    bar_open_raw::Int32
    bar_high_raw::Int32
    bar_low_raw::Int32
    bar_close_raw::Int32

    # Normalization statistics (cumulative across all bars)
    sum_bar_average_high::Int64
    sum_bar_average_low::Int64
    bars_completed::Int64
    cached_bar_normalization::Float32
    ticks_since_recalc::Int32

    # Derivative encoding state
    prev_bar_average_raw::Union{Int32, Nothing}

    # Configuration
    config::BarProcessingConfig
end
```

#### Fields

**Current Bar Accumulation** (reset after each bar completion):

- `tick_count::Int32`: Ticks accumulated in current bar (0 to ticks_per_bar-1)
- `bar_idx::Int64`: Current bar index (1, 2, 3, ...) - incremented on completion
- `bar_open_raw::Int32`: First tick raw_price in bar
- `bar_high_raw::Int32`: Maximum raw_price in bar (tracks high)
- `bar_low_raw::Int32`: Minimum raw_price in bar (tracks low)
- `bar_close_raw::Int32`: Last tick raw_price in bar (updated each tick)

**Normalization Statistics** (cumulative across all bars):

- `sum_bar_average_high::Int64`: Cumulative sum of all bar high values
- `sum_bar_average_low::Int64`: Cumulative sum of all bar low values
- `bars_completed::Int64`: Total bars completed since start
- `cached_bar_normalization::Float32`: Current normalization factor (range = avg_high - avg_low)
- `ticks_since_recalc::Int32`: Ticks since last normalization recalculation

**Derivative Encoding State**:

- `prev_bar_average_raw::Union{Int32, Nothing}`: Previous bar average for delta calculation
  - `nothing` before first bar completion
  - Set to `bar_average_raw` after each bar

**Configuration**:

- `config::BarProcessingConfig`: Bar processing configuration (immutable reference)

#### Initialization

```julia
state = create_bar_processor_state(config)

# Initial values:
# tick_count = 0 (no ticks yet)
# bar_idx = 0 (first bar will be 1)
# bar_high_raw = typemin(Int32) (will track maximum)
# bar_low_raw = typemax(Int32) (will track minimum)
# bars_completed = 0
# cached_bar_normalization = 1.0 (preload to avoid div-by-zero)
# prev_bar_average_raw = nothing (no previous bar)
```

---

## Exported Functions

### create_bar_processor_state

Create bar processor state with configuration.

```julia
create_bar_processor_state(config::BarProcessingConfig)::BarProcessorState
```

#### Arguments

- `config::BarProcessingConfig`: Bar processing configuration

#### Returns

- `BarProcessorState`: Initialized state ready for processing

#### Example

```julia
config = BarProcessingConfig(
    enabled = true,
    ticks_per_bar = Int32(144),
    normalization_window_bars = Int32(24)
)
state = create_bar_processor_state(config)

# State is ready to process ticks
@assert state.tick_count == Int32(0)
@assert state.bar_idx == Int64(0)
@assert state.bars_completed == Int64(0)
```

#### Notes

- Always use this function to create state (don't construct manually)
- State is mutable and will be modified by `process_tick_for_bars!`
- Each pipeline should have its own state instance

---

### process_tick_for_bars!

Process single tick for bar aggregation. Updates message in-place on bar completion.

```julia
process_tick_for_bars!(msg::BroadcastMessage, state::BarProcessorState)
```

#### Arguments

- `msg::BroadcastMessage`: Message to process (modified in-place on bar completion)
- `state::BarProcessorState`: Bar processor state (modified in-place every call)

#### Returns

- `Nothing` (modifies arguments in-place)

#### Behavior

**Called for EVERY tick** in the pipeline:

1. **Early exit** if bar processing disabled (`state.config.enabled == false`)
2. **First tick of bar** (`tick_count == 0`):
   - Initialize OHLC from current tick price
   - Set `bar_open_raw = bar_high_raw = bar_low_raw = bar_close_raw = msg.raw_price`
3. **Subsequent ticks** (`tick_count > 0`):
   - Update `bar_high_raw = max(bar_high_raw, msg.raw_price)`
   - Update `bar_low_raw = min(bar_low_raw, msg.raw_price)`
   - Update `bar_close_raw = msg.raw_price`
4. **Increment** `tick_count`
5. **Check bar completion** (`tick_count >= ticks_per_bar`):
   - Call `populate_bar_data!(msg, state)` to populate 14 bar fields
   - Reset `tick_count = 0` for next bar
   - Increment `bar_idx`

**On non-completion ticks**: Bar fields remain `nothing` (pass-through)

#### Message Flow

**Ticks 1-143** (assuming 144 ticks/bar):
```julia
# Input: msg.raw_price = 42050
process_tick_for_bars!(msg, state)
# Output: msg.bar_idx = nothing (all bar fields = nothing)
```

**Tick 144** (bar completion):
```julia
# Input: msg.raw_price = 42065
process_tick_for_bars!(msg, state)
# Output: msg.bar_idx = 1 (all 14 bar fields populated)
```

#### Example

```julia
# In pipeline message loop
tick_channel = stream_expanded_ticks(tick_file, 0.0)
tick_state = create_tickhotloop_state()
bar_state = create_bar_processor_state(bar_config)

for msg in tick_channel
    # Stage 2: Tick-level signal processing
    process_tick_signal!(msg, tick_state, ...)

    # Stage 2.5: Bar-level aggregation (NEW)
    process_tick_for_bars!(msg, bar_state)

    # Stage 3: Broadcasting
    broadcast_to_all!(split_manager, msg)
end
```

#### Performance

- **Ticks 1-143**: ~5-10ns overhead (min/max operations only)
- **Tick 144**: ~100-500ns (bar completion processing)
- **Amortized**: ~10-20ns per tick (< 0.02μs)

#### Thread Safety

- **Not thread-safe**: State is mutable and not synchronized
- **Safe in pipeline**: Pipeline is single-threaded (one task)
- **Multiple pipelines**: Each pipeline needs its own state instance

---

## Internal Functions

### populate_bar_data!

Populate bar fields in message on bar completion. **Internal function** - called by `process_tick_for_bars!`.

```julia
populate_bar_data!(msg::BroadcastMessage, state::BarProcessorState)
```

#### Arguments

- `msg::BroadcastMessage`: Message to populate (modified in-place)
- `state::BarProcessorState`: Bar processor state (modified in-place)

#### Returns

- `Nothing` (modifies arguments in-place)

#### Processing Steps

Performs 12-step bar signal processing:

1. **Extract OHLC**: Read bar_open_raw, bar_high_raw, bar_low_raw, bar_close_raw from state
2. **Calculate bar averages**: Use high and low for normalization (volatility measure)
3. **Update cumulative statistics**: Add to sum_bar_average_high, sum_bar_average_low, increment bars_completed
4. **Recalculation check**: Every `normalization_window_bars`, recalculate normalization factor
5. **Bar average calculation**: `bar_average_raw = avg(high, low, close)`
6. **Bar delta calculation**: `bar_price_delta = current_avg - previous_avg` (0 for first bar)
7. **Jump guard**: Clip extreme moves > `max_bar_jump`, set FLAG_CLIPPED
8. **Winsorizing**: Clip outliers > `winsorize_bar_threshold`, set FLAG_CLIPPED
9. **Normalization**: Divide by `cached_bar_normalization`
10. **Derivative encoding**: Position (real) + Velocity (imaginary)
11. **Message update**: Populate all 14 bar fields in msg
12. **State update**: Save `prev_bar_average_raw` for next bar

#### Normalization Calculation

```julia
# After each bar completion (step 3)
sum_bar_average_high += bar_high
sum_bar_average_low += bar_low
bars_completed += 1
ticks_since_recalc += ticks_per_bar

# Recalculate every normalization_window_bars (step 4)
recalc_period = normalization_window_bars * ticks_per_bar
if ticks_since_recalc >= recalc_period
    avg_high = Float32(sum_bar_average_high) / Float32(bars_completed)
    avg_low = Float32(sum_bar_average_low) / Float32(bars_completed)
    cached_bar_normalization = max(avg_high - avg_low, Float32(1.0))
    ticks_since_recalc = Int32(0)
end
```

#### Derivative Encoding

```julia
# Step 5: Bar average
bar_average_raw = Int32(round(Float32(bar_high + bar_low + bar_close) / Float32(3.0)))

# Step 6: Bar delta
bar_price_delta = if prev_bar_average_raw !== nothing
    bar_average_raw - prev_bar_average_raw
else
    Int32(0)  # First bar
end

# Steps 7-9: Jump guard, winsorizing, normalization
# (applied to bar_price_delta)

# Step 10: Derivative encoding
normalized_bar_delta = Float32(bar_price_delta) / cached_bar_normalization

prev_normalized = if prev_bar_average_raw !== nothing
    Float32(prev_bar_average_raw) / cached_bar_normalization
else
    Float32(0.0)
end

current_normalized = Float32(bar_average_raw) / cached_bar_normalization
derivative = current_normalized - prev_normalized
scaled_derivative = derivative * config.derivative_imag_scale

bar_complex_signal = ComplexF32(normalized_bar_delta, scaled_derivative)
```

#### Example Output

**First Bar** (bar_idx = 1):
```julia
msg.bar_idx = Int64(1)
msg.bar_ticks = Int32(144)
msg.bar_volume = Int32(144)
msg.bar_open_raw = Int32(42050)
msg.bar_high_raw = Int32(42070)
msg.bar_low_raw = Int32(42045)
msg.bar_close_raw = Int32(42065)
msg.bar_average_raw = Int32(42060)
msg.bar_price_delta = Int32(0)  # No previous bar
msg.bar_complex_signal = ComplexF32(0.0, 2.8)  # real=0, imag=velocity from zero
msg.bar_normalization = Float32(1.0)  # Default until first recalc
msg.bar_flags = FLAG_OK
msg.bar_end_timestamp = UInt64(20250625093000000)
```

**Second Bar** (bar_idx = 2):
```julia
msg.bar_idx = Int64(2)
msg.bar_average_raw = Int32(42070)
msg.bar_price_delta = Int32(10)  # 42070 - 42060
msg.bar_complex_signal = ComplexF32(0.65, 0.8)  # Normalized delta + velocity
msg.bar_normalization = Float32(15.3)  # Updated
```

---

## Message Fields

### Bar Fields in BroadcastMessage

When bar processing is enabled, BroadcastMessage includes 14 bar fields (all `Union{T, Nothing}`):

```julia
# Bar Identification
bar_idx::Union{Int64, Nothing}
bar_ticks::Union{Int32, Nothing}
bar_volume::Union{Int32, Nothing}
bar_end_timestamp::Union{UInt64, Nothing}

# Bar OHLC
bar_open_raw::Union{Int32, Nothing}
bar_high_raw::Union{Int32, Nothing}
bar_low_raw::Union{Int32, Nothing}
bar_close_raw::Union{Int32, Nothing}

# Bar Analytics
bar_average_raw::Union{Int32, Nothing}
bar_price_delta::Union{Int32, Nothing}
bar_complex_signal::Union{ComplexF32, Nothing}
bar_normalization::Union{Float32, Nothing}
bar_flags::Union{UInt8, Nothing}
```

#### Field Semantics

**bar_idx**: Bar index (1-based)
- First bar: `bar_idx = 1`
- Second bar: `bar_idx = 2`
- `nothing` on non-completion ticks

**bar_ticks**: Number of ticks in bar
- Always equals `config.ticks_per_bar`
- Useful for validation

**bar_volume**: Volume in bar
- Equals `ticks_per_bar` for 1-lot ticks
- Could be different if volume expansion changes

**bar_end_timestamp**: Timestamp of last tick in bar
- Copied from `msg.timestamp` of completion tick
- UInt64 encoded timestamp

**bar_open_raw**: First tick price in bar
- Raw price (not normalized)
- Always `<= bar_high_raw` and `>= bar_low_raw`

**bar_high_raw**: Highest tick price in bar
- Raw price (not normalized)
- Always `>= bar_low_raw`

**bar_low_raw**: Lowest tick price in bar
- Raw price (not normalized)
- Always `<= bar_high_raw`

**bar_close_raw**: Last tick price in bar
- Raw price (not normalized)
- May equal open, high, or low

**bar_average_raw**: Representative bar price
- Calculated as `avg(high, low, close)`
- Used for delta calculation

**bar_price_delta**: Change from previous bar
- `current_bar_average - previous_bar_average`
- `0` for first bar (no previous bar)
- May be clipped by jump guard or winsorizing

**bar_complex_signal**: Bar-level I/Q signal
- Real: Normalized bar delta (position)
- Imaginary: Velocity (derivative * scale)
- ComplexF32 format

**bar_normalization**: Normalization factor
- Range = `avg_high - avg_low` across all bars
- Recalculated every `normalization_window_bars`
- Minimum value: 1.0

**bar_flags**: Processing flags
- `FLAG_OK` (0x00): Normal processing
- `FLAG_CLIPPED` (0x04): Jump guard or winsorizing applied
- Other flags not used in bar processing

#### Usage Pattern

```julia
for msg in consumer.channel
    # Check for bar completion
    if msg.bar_idx !== nothing
        # Access bar fields (safe - all non-nothing)
        println("Bar $(msg.bar_idx):")
        println("  OHLC: $(msg.bar_open_raw) / $(msg.bar_high_raw) / $(msg.bar_low_raw) / $(msg.bar_close_raw)")
        println("  Range: $(msg.bar_high_raw - msg.bar_low_raw)")
        println("  Delta: $(msg.bar_price_delta)")
        println("  Signal: I=$(real(msg.bar_complex_signal)), Q=$(imag(msg.bar_complex_signal))")

        # Check flags
        if (msg.bar_flags & FLAG_CLIPPED) != 0
            println("  WARNING: Bar delta clipped")
        end
    end
    # msg.bar_idx === nothing for 143/144 ticks
end
```

---

## Configuration

### BarProcessingConfig

Configuration for bar-level processing.

```julia
struct BarProcessingConfig
    enabled::Bool
    ticks_per_bar::Int32
    normalization_window_bars::Int32
    winsorize_bar_threshold::Int32
    max_bar_jump::Int32
    derivative_imag_scale::Float32
end
```

#### Fields

**enabled**: Enable bar processing
- Type: `Bool`
- Default: `false`
- If `false`, `process_tick_for_bars!` returns immediately (no overhead)

**ticks_per_bar**: Bar size in ticks
- Type: `Int32`
- Default: `144`
- Valid range: `> 0` (typically 21-377)
- Common values: 21, 55, 89, 144, 233, 377 (Fibonacci)
- Validation: Must be positive

**normalization_window_bars**: Recalculation period in bars
- Type: `Int32`
- Default: `24`
- Valid range: `≥ 20` (recommended)
- Recalculation happens every `normalization_window_bars * ticks_per_bar` ticks
- Higher values = more stable normalization, less frequent updates

**winsorize_bar_threshold**: Bar delta outlier threshold
- Type: `Int32`
- Default: `50`
- Valid range: `> 0`
- Clips bar deltas > ±threshold
- Set based on typical bar volatility (e.g., 2-3x typical range)

**max_bar_jump**: Bar delta jump guard
- Type: `Int32`
- Default: `100`
- Valid range: `> 0`
- Clips bar deltas > ±max_bar_jump
- Should be ~2x winsorize_bar_threshold
- Safety mechanism for extreme moves

**derivative_imag_scale**: Derivative encoding scale factor
- Type: `Float32`
- Default: `4.0`
- Valid range: `> 0.0` (typically 1.0-10.0)
- Scales velocity (imaginary) component
- Higher values emphasize rate of change

#### Constructor

```julia
# Default constructor
BarProcessingConfig(;
    enabled = false,
    ticks_per_bar = Int32(144),
    normalization_window_bars = Int32(24),
    winsorize_bar_threshold = Int32(50),
    max_bar_jump = Int32(100),
    derivative_imag_scale = Float32(4.0)
)
```

#### Validation Rules

```julia
# From PipelineConfig.validate_config
if config.bar_processing.enabled
    if config.bar_processing.ticks_per_bar <= Int32(0)
        push!(errors, "Bar processing: ticks_per_bar must be positive")
    end

    if config.bar_processing.normalization_window_bars < Int32(20)
        push!(errors, "Bar processing: normalization_window_bars should be >= 20 for stability")
    end

    if config.bar_processing.winsorize_bar_threshold <= Int32(0)
        push!(errors, "Bar processing: winsorize_bar_threshold must be positive")
    end

    if config.bar_processing.max_bar_jump <= Int32(0)
        push!(errors, "Bar processing: max_bar_jump must be positive")
    end

    if config.bar_processing.derivative_imag_scale <= Float32(0.0)
        push!(errors, "Bar processing: derivative_imag_scale must be positive")
    end
end
```

#### Example

```julia
# Enable bar processing with custom settings
config = PipelineConfig(
    tick_file_path = "data/raw/ES 12-25.Last.txt",
    bar_processing = BarProcessingConfig(
        enabled = true,
        ticks_per_bar = Int32(233),
        normalization_window_bars = Int32(30),
        winsorize_bar_threshold = Int32(75),
        max_bar_jump = Int32(150),
        derivative_imag_scale = Float32(3.0)
    )
)
```

---

## State Management

### State Lifecycle

```julia
# 1. Create state
config = BarProcessingConfig(enabled = true, ticks_per_bar = Int32(144))
state = create_bar_processor_state(config)

# 2. Process ticks (state mutated in-place)
for msg in tick_channel
    process_tick_for_bars!(msg, state)
    # state.tick_count increments
    # state OHLC tracks min/max
    # state.bars_completed increments on completion
end

# 3. Inspect state (read-only)
println("Bars completed: $(state.bars_completed)")
println("Current bar tick count: $(state.tick_count)")
println("Normalization: $(state.cached_bar_normalization)")

# 4. State persists for entire pipeline run
# Do not reset or recreate during processing
```

### State Invariants

These conditions always hold:

```julia
# Tick count bounds
@assert 0 <= state.tick_count < state.config.ticks_per_bar

# Bar index consistency
@assert state.bar_idx == state.bars_completed

# OHLC bounds (after first tick)
if state.tick_count > 0
    @assert state.bar_low_raw <= state.bar_close_raw <= state.bar_high_raw
    @assert state.bar_low_raw <= state.bar_open_raw <= state.bar_high_raw
end

# Normalization positive
@assert state.cached_bar_normalization > Float32(0.0)

# Cumulative statistics consistent
@assert state.sum_bar_average_high > Int64(0) if state.bars_completed > 0
@assert state.sum_bar_average_low > Int64(0) if state.bars_completed > 0
```

### State Reset

**Do not reset state during pipeline run.** State accumulates across all bars for correct normalization.

If you need fresh state:
```julia
# Create new state instance
new_state = create_bar_processor_state(config)
pipeline_mgr.bar_state = new_state  # Replace (advanced usage only)
```

---

## Signal Processing Pipeline

### 14-Step Bar Completion Processing

When `tick_count >= ticks_per_bar`, the following processing occurs:

```
Step 1: Extract OHLC
    ↓ bar_open_raw, bar_high_raw, bar_low_raw, bar_close_raw
Step 2: Calculate bar averages
    ↓ bar_average_high = bar_high, bar_average_low = bar_low
Step 3: Update cumulative statistics
    ↓ sum_bar_average_high, sum_bar_average_low, bars_completed
Step 4: Check recalculation period
    ↓ If ticks_since_recalc >= recalc_period:
Step 4a: Recalculate normalization
    ↓ cached_bar_normalization = avg_high - avg_low
Step 5: Calculate bar_average_raw
    ↓ avg(high, low, close)
Step 6: Calculate bar_price_delta
    ↓ current_avg - previous_avg (0 if first bar)
Step 7: Apply jump guard
    ↓ Clip if |delta| > max_bar_jump, set FLAG_CLIPPED
Step 8: Winsorize
    ↓ Clip if |delta| > winsorize_bar_threshold, set FLAG_CLIPPED
Step 9: Normalize
    ↓ normalized_delta = delta / cached_bar_normalization
Step 10: Derivative encoding
    ↓ real = normalized_delta
    ↓ imag = velocity * derivative_imag_scale
Step 11: Update message
    ↓ Populate all 14 bar fields
Step 12: Update state
    ↓ prev_bar_average_raw = bar_average_raw
```

### Mathematical Formulas

**Bar Average**:
```julia
bar_average_raw = (bar_high_raw + bar_low_raw + bar_close_raw) / 3
```

**Bar Delta** (with jump guard and winsorizing):
```julia
raw_delta = bar_average_raw - prev_bar_average_raw

# Jump guard
if abs(raw_delta) > max_bar_jump
    raw_delta = sign(raw_delta) * max_bar_jump
    bar_flags |= FLAG_CLIPPED
end

# Winsorize
if abs(raw_delta) > winsorize_bar_threshold
    raw_delta = sign(raw_delta) * winsorize_bar_threshold
    bar_flags |= FLAG_CLIPPED
end

bar_price_delta = raw_delta
```

**Normalization** (cumulative statistics):
```julia
# After each bar
sum_bar_average_high += bar_high_raw
sum_bar_average_low += bar_low_raw
bars_completed += 1

# Every normalization_window_bars
avg_high = sum_bar_average_high / bars_completed
avg_low = sum_bar_average_low / bars_completed
cached_bar_normalization = max(avg_high - avg_low, 1.0)
```

**Derivative Encoding** (position + velocity):
```julia
# Position (normalized bar delta)
normalized_bar_delta = Float32(bar_price_delta) / cached_bar_normalization

# Velocity (change in normalized position)
prev_pos = Float32(prev_bar_average_raw) / cached_bar_normalization
curr_pos = Float32(bar_average_raw) / cached_bar_normalization
velocity = (curr_pos - prev_pos) * derivative_imag_scale

# Complex signal
bar_complex_signal = ComplexF32(normalized_bar_delta, velocity)
```

---

## Examples

### Example 1: Basic Bar Processing

```julia
using TickDataPipeline

# Setup
config = PipelineConfig(
    tick_file_path = "data/raw/YM 06-25.Last.txt",
    bar_processing = BarProcessingConfig(
        enabled = true,
        ticks_per_bar = Int32(144)
    )
)

split_mgr = create_triple_split_manager()
consumer = subscribe_consumer!(split_mgr, "bars", MONITORING, Int32(1024))
pipeline_mgr = create_pipeline_manager(config, split_mgr)

# Process
@async run_pipeline!(pipeline_mgr, max_ticks=Int64(500))

# Consume
for msg in consumer.channel
    if msg.bar_idx !== nothing
        println("Bar $(msg.bar_idx): OHLC $(msg.bar_open_raw)/$(msg.bar_high_raw)/$(msg.bar_low_raw)/$(msg.bar_close_raw)")
    end
end
```

### Example 2: Manual Bar State Creation

```julia
using TickDataPipeline

# Create state manually
bar_config = BarProcessingConfig(
    enabled = true,
    ticks_per_bar = Int32(89),
    normalization_window_bars = Int32(30)
)

bar_state = create_bar_processor_state(bar_config)

# Use in custom processing loop
tick_channel = stream_expanded_ticks("data/raw/ticks.txt", 0.0)

for msg in tick_channel
    # Your custom tick processing
    custom_processing(msg)

    # Add bar processing
    process_tick_for_bars!(msg, bar_state)

    if msg.bar_idx !== nothing
        handle_bar_completion(msg)
    end
end
```

### Example 3: Inspect Bar State

```julia
using TickDataPipeline

config = PipelineConfig(
    tick_file_path = "data/raw/YM 06-25.Last.txt",
    bar_processing = BarProcessingConfig(enabled = true, ticks_per_bar = Int32(144))
)

split_mgr = create_triple_split_manager()
pipeline_mgr = create_pipeline_manager(config, split_mgr)

# Run pipeline
stats = run_pipeline!(pipeline_mgr, max_ticks=Int64(1000))

# Inspect bar state after completion
bar_state = pipeline_mgr.bar_state

println("Bar Processing Results:")
println("  Bars completed: $(bar_state.bars_completed)")
println("  Partial bar ticks: $(bar_state.tick_count)")
println("  Current bar index: $(bar_state.bar_idx)")
println("  Normalization factor: $(bar_state.cached_bar_normalization)")
println("  Ticks since recalc: $(bar_state.ticks_since_recalc)")

# Calculate partial bar percentage
if bar_state.tick_count > Int32(0)
    partial_pct = 100.0 * Float32(bar_state.tick_count) / Float32(bar_state.config.ticks_per_bar)
    println("  Partial bar: $(round(partial_pct, digits=1))% complete")
end
```

### Example 4: Validate Bar Completion

```julia
using TickDataPipeline

function validate_bars(tick_file::String, max_ticks::Int64)
    config = PipelineConfig(
        tick_file_path = tick_file,
        bar_processing = BarProcessingConfig(
            enabled = true,
            ticks_per_bar = Int32(144)
        )
    )

    split_mgr = create_triple_split_manager()
    consumer = subscribe_consumer!(split_mgr, "validator", MONITORING, Int32(1024))
    pipeline_mgr = create_pipeline_manager(config, split_mgr)

    @async run_pipeline!(pipeline_mgr, max_ticks=max_ticks)

    bar_count = 0
    tick_count = 0

    for msg in consumer.channel
        tick_count += 1

        if msg.bar_idx !== nothing
            bar_count += 1

            # Validate OHLC
            @assert msg.bar_high_raw >= msg.bar_low_raw
            @assert msg.bar_high_raw >= msg.bar_open_raw
            @assert msg.bar_high_raw >= msg.bar_close_raw
            @assert msg.bar_low_raw <= msg.bar_open_raw
            @assert msg.bar_low_raw <= msg.bar_close_raw

            # Validate metadata
            @assert msg.bar_ticks == Int32(144)
            @assert msg.bar_volume == Int32(144)
            @assert msg.bar_idx == Int64(bar_count)

            # Validate signals
            @assert msg.bar_normalization > Float32(0)
            @assert !isnan(real(msg.bar_complex_signal))
            @assert !isnan(imag(msg.bar_complex_signal))

            println("✓ Bar $(bar_count) validated")
        end
    end

    # Validate bar count
    expected_bars = div(max_ticks, 144)
    @assert bar_count == expected_bars

    println("All bars validated: $bar_count bars from $tick_count ticks")
end

validate_bars("data/raw/YM 06-25.Last.txt", Int64(1000))
```

---

## Performance Notes

### Computational Complexity

- **Tick accumulation**: O(1) per tick (min/max operations)
- **Bar completion**: O(1) per bar (fixed arithmetic operations)
- **Normalization recalc**: O(1) every N bars (division operations)
- **Overall**: O(n) where n = number of ticks

### Memory Usage

- **BarProcessorState**: ~96 bytes per pipeline instance
- **Message overhead**: ~8 bytes per tick (Union{T, Nothing} pointer)
- **Bar completion**: ~70 bytes per bar completion message
- **Average**: ~8.5 bytes per message (143/144 ticks have nothing)

### Cache Efficiency

- State fields fit in single cache line (64 bytes)
- OHLC updates are sequential (cache-friendly)
- Normalization cached (reused across many bars)
- No heap allocations in hot path

---

**Last Updated:** 2025-10-16
**Module Version:** 1.0
**Package Version:** TickDataPipeline v0.1.0

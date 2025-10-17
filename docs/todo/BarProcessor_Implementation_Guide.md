# Bar Processor Implementation Guide
## Design Specification and Implementation Plan

**Document Version:** 1.0  
**Created:** 2025-10-16  
**Status:** Ready for Implementation

---

## Executive Summary

This document provides a complete design specification and implementation guide for adding bar processing capabilities to TickDataPipeline. The bar processor sits between TickHotLoop and consumers, enriching BroadcastMessage with bar-level data alongside existing tick-level data.

### Key Design Principles

1. **In-place updates**: Bar properties are added to BroadcastMessage in-place (like TickHotLoop)
2. **Pass-through architecture**: Every tick flows through; bar data populated only on bar completion
3. **Dual signals**: Tick-level and bar-level signals coexist in same message
4. **Rolling normalization**: Bar normalization uses rolling window (mirroring tick normalization)
5. **Configurable**: All bar parameters driven by configuration

---

## Architecture Overview

### Message Flow

```
VolumeExpander.jl
    ↓ (creates BroadcastMessage)
TickHotLoop.jl
    ↓ (updates: complex_signal, normalization, flags)
BarProcessor.jl ← NEW
    ↓ (updates: bar_idx, bar_complex_signal, bar_* fields when bar completes)
Consumers
    ↓ (receive enriched BroadcastMessage)
```

### Key Characteristics

- **143 out of 144 ticks**: Bar fields = `nothing` (pass-through)
- **1 out of 144 ticks**: Bar fields populated (bar completion)
- **No tick consumption**: All ticks continue to consumers
- **Independent normalization**: Bar normalization separate from tick normalization

---

## Part 1: Data Structure Modifications

### 1.1 BroadcastMessage Extensions

**File:** `src/types.jl`

Add the following fields to the `BroadcastMessage` mutable struct:

```julia
# Bar data fields (only populated at bar completion)
bar_idx::Union{Int64, Nothing}                    # Bar sequence number (1, 2, 3, ...)
bar_ticks::Union{Int32, Nothing}                  # Ticks per bar (from config)
bar_volume::Union{Int32, Nothing}                 # Same as bar_ticks (1 contract/tick)

# OHLC from raw prices
bar_open_raw::Union{Int32, Nothing}               # First tick raw_price in bar
bar_high_raw::Union{Int32, Nothing}               # Max raw_price in bar
bar_low_raw::Union{Int32, Nothing}                # Min raw_price in bar
bar_close_raw::Union{Int32, Nothing}              # Last tick raw_price in bar

# Bar statistics
bar_average_raw::Union{Int32, Nothing}            # avg(high, low, close)
bar_price_delta::Union{Int32, Nothing}            # average_raw - prev_average_raw

# Bar signal processing (parallel to tick signals)
bar_complex_signal::Union{ComplexF32, Nothing}    # Derivative encoded bar signal
bar_normalization::Union{Float32, Nothing}        # Bar normalization factor
bar_flags::Union{UInt8, Nothing}                  # Processing flags for bar

bar_end_timestamp::Union{UInt64, Nothing}         # Timestamp of final tick
```

**Constructor Update:**

Update the `BroadcastMessage` constructor to initialize all bar fields to `nothing`:

```julia
function BroadcastMessage(
    tick_idx::Int64,
    timestamp::UInt64,
    raw_price::Int32,
    price_delta::Int32,
    complex_signal::ComplexF32,
    normalization::Float32,
    flags::UInt8
)
    return BroadcastMessage(
        tick_idx,
        timestamp,
        raw_price,
        price_delta,
        complex_signal,
        normalization,
        flags,
        # Bar fields initialized to nothing
        nothing,  # bar_idx
        nothing,  # bar_ticks
        nothing,  # bar_volume
        nothing,  # bar_open_raw
        nothing,  # bar_high_raw
        nothing,  # bar_low_raw
        nothing,  # bar_close_raw
        nothing,  # bar_average_raw
        nothing,  # bar_price_delta
        nothing,  # bar_complex_signal
        nothing,  # bar_normalization
        nothing,  # bar_flags
        nothing   # bar_end_timestamp
    )
end
```

### 1.2 Configuration Structure

**File:** `src/config.jl`

Add new configuration struct for bar processing:

```julia
"""
Configuration for bar-level signal processing.

Bar processing aggregates ticks into bars and applies signal processing
(normalization, jump guard, winsorizing, derivative encoding) at bar level.

# Fields
- `enabled::Bool`: Enable/disable bar processing (default: false)
- `ticks_per_bar::Int32`: Number of ticks per bar (e.g., 21, 144, 610)
- `normalization_window_ticks::Int32`: Window for normalization in ticks (e.g., 2584)
- `winsorize_bar_threshold::Int32`: Clip bar deltas to ±threshold (e.g., 50)
- `max_bar_jump::Int32`: Maximum allowed bar-to-bar delta (e.g., 100)
- `derivative_imag_scale::Float32`: Scaling for bar velocity component (e.g., 4.0)

# Normalization Window
The normalization window should be significantly larger than a single bar:
- For 21-tick bars: use ~120 bars
- For 144-tick bars: use ~24 bars
- For 233-tick bars: use ~20 bars
- General rule: normalization_window_bars ≥ 20

The normalization is recalculated every N bars (where N = normalization_window_bars).

# Example
```julia
bar_processing = BarProcessingConfig(
    enabled = true,
    ticks_per_bar = Int32(21),
    normalization_window_bars = Int32(120),
    winsorize_bar_threshold = Int32(50),
    max_bar_jump = Int32(100),
    derivative_imag_scale = Float32(4.0)
)
```
"""
struct BarProcessingConfig
    enabled::Bool
    ticks_per_bar::Int32
    normalization_window_bars::Int32
    winsorize_bar_threshold::Int32
    max_bar_jump::Int32
    derivative_imag_scale::Float32
end

# Default constructor
function BarProcessingConfig(;
    enabled::Bool = false,
    ticks_per_bar::Int32 = Int32(144),
    normalization_window_bars::Int32 = Int32(24),
    winsorize_bar_threshold::Int32 = Int32(50),
    max_bar_jump::Int32 = Int32(100),
    derivative_imag_scale::Float32 = Float32(4.0)
)
    return BarProcessingConfig(
        enabled,
        ticks_per_bar,
        normalization_window_bars,
        winsorize_bar_threshold,
        max_bar_jump,
        derivative_imag_scale
    )
end

# Helper function - no longer needed since we store bars directly
# Kept for backward compatibility if needed
normalization_window_bars(config::BarProcessingConfig)::Int32 = 
    config.normalization_window_bars
```

**Add to PipelineConfig:**

```julia
struct PipelineConfig
    tick_file_path::String
    signal_processing::SignalProcessingConfig
    bar_processing::BarProcessingConfig  # NEW
    flow_control::FlowControlConfig
    channels::ChannelConfig
    performance::PerformanceConfig
    pipeline_name::String
    description::String
    version::VersionNumber
end
```

**Update TOML loading** in `src/config.jl`:

```julia
function load_config_from_toml(path::String)::PipelineConfig
    config = TOML.parsefile(path)
    
    # ... existing code ...
    
    # Bar processing configuration (optional section)
    bar_processing = if haskey(config, "bar_processing")
        bp = config["bar_processing"]
        BarProcessingConfig(
            enabled = get(bp, "enabled", false),
            ticks_per_bar = Int32(get(bp, "ticks_per_bar", 144)),
            normalization_window_bars = Int32(get(bp, "normalization_window_bars", 24)),
            winsorize_bar_threshold = Int32(get(bp, "winsorize_bar_threshold", 50)),
            max_bar_jump = Int32(get(bp, "max_bar_jump", 100)),
            derivative_imag_scale = Float32(get(bp, "derivative_imag_scale", 4.0))
        )
    else
        BarProcessingConfig()  # Default (disabled)
    end
    
    return PipelineConfig(
        # ... existing fields ...
        bar_processing,  # NEW
        # ... remaining fields ...
    )
end
```

### 1.3 Configuration File (TOML)

**File:** `config/default.toml`

Add new section:

```toml
[bar_processing]
# Enable bar processing (false = disabled)
enabled = false

# Bar size in ticks
ticks_per_bar = 144

# Normalization window in bars (should be >> 1)
# Normalization is recalculated every N bars
# Rule of thumb: normalization_window_bars ≥ 20
normalization_window_bars = 24

# Winsorize bar deltas (clip to ±threshold)
winsorize_bar_threshold = 50

# Maximum allowed bar-to-bar delta (jump guard)
max_bar_jump = 100

# Derivative encoding: imaginary component scaling
derivative_imag_scale = 4.0
```

---

## Part 2: Bar Processor Implementation

### 2.1 Bar Processor State

**File:** `src/barprocessor.jl` (NEW FILE)

```julia
# barprocessor.jl - Bar aggregation and signal processing
# Sits between TickHotLoop and consumers in the message flow
# Accumulates ticks into bars, applies bar-level signal processing

"""
State for bar processing - accumulates ticks and tracks normalization statistics.

Mirrors TickHotLoopState pattern for consistency.
"""
mutable struct BarProcessorState
    # Bar accumulation (current bar being built)
    current_bar_tick_count::Int32           # Ticks accumulated in current bar (0 to ticks_per_bar-1)
    current_bar_open_raw::Int32             # First tick raw_price
    current_bar_high_raw::Int32             # Max raw_price so far
    current_bar_low_raw::Int32              # Min raw_price so far
    current_bar_close_raw::Int32            # Most recent raw_price
    
    # Bar normalization (rolling window statistics)
    bar_count::Int64                        # Total bars completed
    sum_bar_average_high::Int64             # Σ bar.average_high across all bars
    sum_bar_average_low::Int64              # Σ bar.average_low across all bars
    cached_bar_inv_norm_Q16::Int32          # Bar normalization reciprocal (Q16 fixed-point)
    
    # Bar derivative encoding state
    prev_bar_average_raw::Union{Int32, Nothing}     # Previous bar's average_raw
    prev_bar_normalized_ratio::Float32              # Previous bar's normalized price_delta
    
    # Configuration reference
    config::BarProcessingConfig
end

"""
Create and initialize bar processor state.

Preloads cached_bar_inv_norm_Q16 with reasonable default (1/8.67 in Q16).
This will be updated after first bar completes.
"""
function create_bar_processor_state(config::BarProcessingConfig)::BarProcessorState
    return BarProcessorState(
        Int32(0),           # current_bar_tick_count
        Int32(0),           # current_bar_open_raw (will be set on first tick)
        Int32(0),           # current_bar_high_raw
        Int32(0),           # current_bar_low_raw
        Int32(0),           # current_bar_close_raw
        Int64(0),           # bar_count
        Int64(0),           # sum_bar_average_high
        Int64(0),           # sum_bar_average_low
        Int32(7560),        # cached_bar_inv_norm_Q16 preload (1/8.67 in Q16)
        nothing,            # prev_bar_average_raw (no previous bar yet)
        Float32(0.0),       # prev_bar_normalized_ratio
        config
    )
end
```

### 2.2 Main Processing Function

```julia
"""
Process a tick through bar aggregator.

Updates msg in-place with bar properties when bar completes.
Most ticks pass through unchanged (bar fields remain nothing).
Only the final tick of each bar gets bar properties populated.

# Arguments
- `msg::BroadcastMessage`: Message to process (modified in-place)
- `state::BarProcessorState`: Bar processor state (modified in-place)

# Returns
- `nothing`: All updates are in-place

# Processing Flow
1. Accumulate tick into current bar (update open/high/low/close)
2. Check if bar is complete (tick_count >= ticks_per_bar)
3. If complete: populate bar data in message and reset accumulator
4. If not complete: message passes through unchanged
"""
function process_tick_for_bars!(
    msg::BroadcastMessage,
    state::BarProcessorState
)::Nothing
    # If bar processing disabled, skip
    if !state.config.enabled
        return nothing
    end
    
    # Accumulate tick into current bar
    if state.current_bar_tick_count == Int32(0)
        # Starting new bar
        state.current_bar_open_raw = msg.raw_price
        state.current_bar_high_raw = msg.raw_price
        state.current_bar_low_raw = msg.raw_price
    else
        # Update running min/max
        state.current_bar_high_raw = max(state.current_bar_high_raw, msg.raw_price)
        state.current_bar_low_raw = min(state.current_bar_low_raw, msg.raw_price)
    end
    
    # Always update close with most recent price
    state.current_bar_close_raw = msg.raw_price
    state.current_bar_tick_count += Int32(1)
    
    # Check if bar is complete
    if state.current_bar_tick_count >= state.config.ticks_per_bar
        # Update bar properties IN-PLACE on this message
        populate_bar_data!(msg, state)
        
        # Reset accumulator for next bar
        state.current_bar_tick_count = Int32(0)
    end
    
    return nothing
end
```

### 2.3 Bar Data Population

```julia
"""
Populate bar properties in BroadcastMessage (called only when bar completes).

Applies full signal processing pipeline to bar:
1. Calculate OHLC and bar statistics
2. Update rolling normalization window
3. Calculate bar price delta
4. Apply jump guard and winsorizing
5. Normalize using Q16 fixed-point
6. Apply derivative encoding
7. Update message in-place with all bar data

# Arguments
- `msg::BroadcastMessage`: Message to populate (modified in-place)
- `state::BarProcessorState`: Bar state (modified in-place)
"""
function populate_bar_data!(msg::BroadcastMessage, state::BarProcessorState)::Nothing
    state.bar_count += Int64(1)
    
    # Step 1: Extract bar OHLC from accumulated state
    bar_open = state.current_bar_open_raw
    bar_high = state.current_bar_high_raw
    bar_low = state.current_bar_low_raw
    bar_close = state.current_bar_close_raw
    
    # Step 2: Calculate bar averages for normalization
    # These track the typical high and low of bars over time
    bar_average_high = max(bar_high, bar_close)
    bar_average_low = min(bar_low, bar_close)
    
    # Step 3: Update rolling normalization statistics
    state.sum_bar_average_high += Int64(bar_average_high)
    state.sum_bar_average_low += Int64(bar_average_low)
    
    # Step 4: Recalculate normalization periodically (every N bars)
    # Only update cached normalization at bar multiples of normalization_window_bars
    # This provides stable normalization that changes infrequently
    if state.bar_count % Int64(state.config.normalization_window_bars) == Int64(0)
        # Calculate normalization using cumulative statistics from ALL bars
        avg_high = Float32(state.sum_bar_average_high) / Float32(state.bar_count)
        avg_low = Float32(state.sum_bar_average_low) / Float32(state.bar_count)
        bar_normalization_range = max(avg_high - avg_low, Float32(1.0))
        
        # Step 5: Cache normalization reciprocal in Q16 fixed-point
        # Q16: 65536 = 2^16, provides good precision for integer math
        state.cached_bar_inv_norm_Q16 = Int32(round(Float32(65536) / bar_normalization_range))
    end
    # Otherwise use cached value from previous calculation
    
    # Step 6: Calculate bar average_raw (typical price)
    # Simple average of high, low, close (equal weighting)
    bar_average_raw = Int32(round(Float32(bar_high + bar_low + bar_close) / Float32(3.0)))
    
    # Step 7: Calculate bar price delta (bar-to-bar change)
    bar_price_delta = if state.prev_bar_average_raw !== nothing
        bar_average_raw - state.prev_bar_average_raw
    else
        Int32(0)  # First bar has no previous bar
    end
    
    # Step 8: Apply jump guard (clip extreme bar moves)
    bar_price_delta_processed = bar_price_delta
    bar_flags = FLAG_OK
    
    if abs(bar_price_delta_processed) > state.config.max_bar_jump
        bar_price_delta_processed = clamp(
            bar_price_delta_processed,
            -state.config.max_bar_jump,
            state.config.max_bar_jump
        )
        bar_flags |= FLAG_CLIPPED
    end
    
    # Step 9: Winsorize bar delta (clip outliers)
    if abs(bar_price_delta_processed) > state.config.winsorize_bar_threshold
        bar_price_delta_processed = sign(bar_price_delta_processed) * 
                                   state.config.winsorize_bar_threshold
        bar_flags |= FLAG_CLIPPED
    end
    
    # Step 10: Normalize using Q16 fixed-point (fast integer multiply)
    normalized_Q16 = bar_price_delta_processed * state.cached_bar_inv_norm_Q16
    bar_normalized_ratio = Float32(normalized_Q16) * Float32(1.52587890625e-5)  # 1/(2^16)
    
    # Step 11: Derivative encoding for bar (position + velocity)
    # Real component: normalized position (bar price delta)
    # Imaginary component: normalized velocity (change in bar price delta)
    bar_velocity = bar_normalized_ratio - state.prev_bar_normalized_ratio
    bar_complex_signal = ComplexF32(
        bar_normalized_ratio,
        bar_velocity * state.config.derivative_imag_scale
    )
    
    # Step 12: Calculate bar normalization factor (for recovery)
    # Recovery: bar_complex_signal_real × bar_normalization ≈ bar_price_delta
    bar_normalization = Float32(1.0) / (Float32(state.cached_bar_inv_norm_Q16) * 
                                        Float32(1.52587890625e-5))
    
    # Step 13: UPDATE MESSAGE IN-PLACE with all bar data
    msg.bar_idx = state.bar_count
    msg.bar_ticks = state.config.ticks_per_bar
    msg.bar_volume = state.config.ticks_per_bar  # 1 contract per tick
    msg.bar_open_raw = bar_open
    msg.bar_high_raw = bar_high
    msg.bar_low_raw = bar_low
    msg.bar_close_raw = bar_close
    msg.bar_average_raw = bar_average_raw
    msg.bar_price_delta = bar_price_delta
    msg.bar_complex_signal = bar_complex_signal
    msg.bar_normalization = bar_normalization
    msg.bar_flags = bar_flags
    msg.bar_end_timestamp = msg.timestamp  # Timestamp from final tick
    
    # Step 14: Update state for next bar
    state.prev_bar_average_raw = bar_average_raw
    state.prev_bar_normalized_ratio = bar_normalized_ratio
    
    return nothing
end
```

### 2.4 Module Exports

Add at the top of `src/barprocessor.jl`:

```julia
# Export bar processing types and functions
export BarProcessingConfig
export BarProcessorState
export create_bar_processor_state
export process_tick_for_bars!
export normalization_window_bars
```

---

## Part 3: Pipeline Integration

### 3.1 Main Module Updates

**File:** `src/TickDataPipeline.jl`

Add new include and exports:

```julia
# Include bar processor module
include("barprocessor.jl")

# Export bar processing
export BarProcessingConfig
export BarProcessorState
export create_bar_processor_state
export process_tick_for_bars!
export normalization_window_bars
```

### 3.2 Pipeline Manager Integration

**File:** `src/pipelinemanager.jl`

Update `PipelineManager` struct to include bar processor state:

```julia
mutable struct PipelineManager
    config::PipelineConfig
    tick_state::TickHotLoopState
    bar_state::BarProcessorState        # NEW
    split_manager::Union{ChannelSplitManager, Nothing}
    volume_expander::VolumeExpander
    stats::PipelineStatistics
    status::PipelineStatus
end
```

Update `create_pipeline_manager` function:

```julia
function create_pipeline_manager(
    config::PipelineConfig,
    split_manager::Union{ChannelSplitManager, Nothing} = nothing
)::PipelineManager
    
    # Create tick processing state
    tick_state = create_tickhotloop_state()
    
    # Initialize AMC carrier if using AMC encoding
    if config.signal_processing.encoder_type == "amc"
        carrier_period = config.signal_processing.amc_carrier_period
        tick_state.amc_carrier_increment_Q32 = Int32(round(Float32(2^32) / Float32(carrier_period)))
    end
    
    # Create bar processing state (NEW)
    bar_state = create_bar_processor_state(config.bar_processing)
    
    # Create volume expander
    volume_expander = VolumeExpander(
        Int32(1),
        config.tick_file_path
    )
    
    # Create statistics tracker
    stats = PipelineStatistics(
        Int64(0), Int64(0), Int64(0), Int64(0), Int64(0), Float64(0.0)
    )
    
    return PipelineManager(
        config,
        tick_state,
        bar_state,    # NEW
        split_manager,
        volume_expander,
        stats,
        PipelineStatus(false, false, false, nothing)
    )
end
```

### 3.3 Message Processing Integration

**File:** `src/pipelinemanager.jl`

Update the main processing loop in `run_pipeline!`:

```julia
# In the main message processing loop:
for message in volume_expander.channel
    try
        # Step 1: Tick-level signal processing
        process_tick_signal!(
            message,
            pipeline.tick_state,
            pipeline.config.signal_processing.agc_alpha,
            pipeline.config.signal_processing.agc_min_scale,
            pipeline.config.signal_processing.agc_max_scale,
            pipeline.config.signal_processing.winsorize_delta_threshold,
            pipeline.config.signal_processing.min_price,
            pipeline.config.signal_processing.max_price,
            pipeline.config.signal_processing.max_jump,
            pipeline.config.signal_processing.encoder_type,
            pipeline.config.signal_processing.cpm_modulation_index,
            pipeline.config.signal_processing.derivative_imag_scale
        )
        
        # Step 2: Bar-level processing (NEW)
        # Only processes if bar_processing.enabled = true
        # Updates bar fields in-place when bar completes
        process_tick_for_bars!(message, pipeline.bar_state)
        
        # Step 3: Broadcast to consumers
        if pipeline.split_manager !== nothing
            broadcast_message!(pipeline.split_manager, message)
        end
        
        # Update statistics
        pipeline.stats.ticks_processed += Int64(1)
        
    catch e
        pipeline.stats.errors += Int64(1)
        @warn "Pipeline processing error" exception=e
        # Continue processing remaining ticks
    end
end
```

---

## Part 4: Testing Strategy

### 4.1 Unit Tests

**File:** `test/test_barprocessor.jl` (NEW FILE)

```julia
using Test
using TickDataPipeline

@testset "BarProcessor Tests" begin
    
    @testset "Configuration" begin
        # Test default configuration
        config = BarProcessingConfig()
        @test config.enabled == false
        @test config.ticks_per_bar == Int32(144)
        
        # Test custom configuration
        config = BarProcessingConfig(
            enabled = true,
            ticks_per_bar = Int32(21),
            normalization_window_bars = Int32(120),
            winsorize_bar_threshold = Int32(50),
            max_bar_jump = Int32(100),
            derivative_imag_scale = Float32(4.0)
        )
        @test config.enabled == true
        @test config.ticks_per_bar == Int32(21)
        @test normalization_window_bars(config) == Int32(120)
    end
    
    @testset "State Initialization" begin
        config = BarProcessingConfig(enabled = true, ticks_per_bar = Int32(21))
        state = create_bar_processor_state(config)
        
        @test state.current_bar_tick_count == Int32(0)
        @test state.bar_count == Int64(0)
        @test state.prev_bar_average_raw === nothing
        @test state.prev_bar_normalized_ratio == Float32(0.0)
        @test state.cached_bar_inv_norm_Q16 == Int32(7560)  # Preload value
    end
    
    @testset "Bar Accumulation" begin
        config = BarProcessingConfig(
            enabled = true,
            ticks_per_bar = Int32(3)  # Small bar for testing
        )
        state = create_bar_processor_state(config)
        
        # Create test messages
        msg1 = BroadcastMessage(
            Int64(1), UInt64(1000), Int32(100), Int32(0),
            ComplexF32(0, 0), Float32(1.0), UInt8(0)
        )
        msg2 = BroadcastMessage(
            Int64(2), UInt64(2000), Int32(105), Int32(5),
            ComplexF32(0.5, 0), Float32(1.0), UInt8(0)
        )
        msg3 = BroadcastMessage(
            Int64(3), UInt64(3000), Int32(102), Int32(-3),
            ComplexF32(-0.3, 0), Float32(1.0), UInt8(0)
        )
        
        # Process first tick (bar start)
        process_tick_for_bars!(msg1, state)
        @test state.current_bar_tick_count == Int32(1)
        @test state.current_bar_open_raw == Int32(100)
        @test state.current_bar_high_raw == Int32(100)
        @test state.current_bar_low_raw == Int32(100)
        @test msg1.bar_idx === nothing  # Bar not complete
        
        # Process second tick
        process_tick_for_bars!(msg2, state)
        @test state.current_bar_tick_count == Int32(2)
        @test state.current_bar_high_raw == Int32(105)  # Updated
        @test msg2.bar_idx === nothing  # Bar not complete
        
        # Process third tick (bar completion)
        process_tick_for_bars!(msg3, state)
        @test state.current_bar_tick_count == Int32(0)  # Reset
        @test state.bar_count == Int64(1)
        @test msg3.bar_idx == Int64(1)  # Bar complete!
        @test msg3.bar_open_raw == Int32(100)
        @test msg3.bar_high_raw == Int32(105)
        @test msg3.bar_low_raw == Int32(100)
        @test msg3.bar_close_raw == Int32(102)
        @test msg3.bar_ticks == Int32(3)
    end
    
    @testset "Bar Normalization" begin
        config = BarProcessingConfig(
            enabled = true,
            ticks_per_bar = Int32(2),
            normalization_window_bars = Int32(2)  # 2 bars in window
        )
        state = create_bar_processor_state(config)
        
        # First bar
        msg1 = create_test_message(Int64(1), Int32(100), Int32(0))
        msg2 = create_test_message(Int64(2), Int32(110), Int32(10))
        process_tick_for_bars!(msg1, state)
        process_tick_for_bars!(msg2, state)
        
        @test msg2.bar_idx == Int64(1)
        first_bar_norm = msg2.bar_normalization
        
        # Second bar
        msg3 = create_test_message(Int64(3), Int32(105), Int32(-5))
        msg4 = create_test_message(Int64(4), Int32(115), Int32(10))
        process_tick_for_bars!(msg3, state)
        process_tick_for_bars!(msg4, state)
        
        @test msg4.bar_idx == Int64(2)
        second_bar_norm = msg4.bar_normalization
        
        # Normalization should be based on rolling window
        @test second_bar_norm !== first_bar_norm
    end
    
    @testset "Jump Guard and Winsorizing" begin
        config = BarProcessingConfig(
            enabled = true,
            ticks_per_bar = Int32(2),
            max_bar_jump = Int32(50),
            winsorize_bar_threshold = Int32(30)
        )
        state = create_bar_processor_state(config)
        
        # First bar (establishes baseline)
        msg1 = create_test_message(Int64(1), Int32(100), Int32(0))
        msg2 = create_test_message(Int64(2), Int32(110), Int32(10))
        process_tick_for_bars!(msg1, state)
        process_tick_for_bars!(msg2, state)
        
        # Second bar with large jump (should be clipped)
        msg3 = create_test_message(Int64(3), Int32(200), Int32(90))
        msg4 = create_test_message(Int64(4), Int32(210), Int32(10))
        process_tick_for_bars!(msg3, state)
        process_tick_for_bars!(msg4, state)
        
        @test msg4.bar_flags & FLAG_CLIPPED != 0  # Clipping flag set
    end
    
    @testset "Derivative Encoding" begin
        config = BarProcessingConfig(
            enabled = true,
            ticks_per_bar = Int32(2),
            derivative_imag_scale = Float32(4.0)
        )
        state = create_bar_processor_state(config)
        
        # Create two bars with known deltas
        # First bar
        msg1 = create_test_message(Int64(1), Int32(100), Int32(0))
        msg2 = create_test_message(Int64(2), Int32(110), Int32(10))
        process_tick_for_bars!(msg1, state)
        process_tick_for_bars!(msg2, state)
        
        # Second bar
        msg3 = create_test_message(Int64(3), Int32(115), Int32(5))
        msg4 = create_test_message(Int64(4), Int32(125), Int32(10))
        process_tick_for_bars!(msg3, state)
        process_tick_for_bars!(msg4, state)
        
        # Check derivative encoding (velocity in imaginary component)
        @test msg4.bar_complex_signal !== nothing
        @test real(msg4.bar_complex_signal) ≈ msg4.bar_price_delta / msg4.bar_normalization atol=0.1
        @test imag(msg4.bar_complex_signal) != 0.0  # Velocity component present
    end
    
    @testset "Disabled Bar Processing" begin
        config = BarProcessingConfig(enabled = false)
        state = create_bar_processor_state(config)
        
        msg = create_test_message(Int64(1), Int32(100), Int32(0))
        process_tick_for_bars!(msg, state)
        
        @test msg.bar_idx === nothing  # No bar data populated
        @test state.bar_count == Int64(0)
    end
end

# Helper function for creating test messages
function create_test_message(tick_idx::Int64, raw_price::Int32, price_delta::Int32)
    return BroadcastMessage(
        tick_idx,
        UInt64(tick_idx * 1000),
        raw_price,
        price_delta,
        ComplexF32(0, 0),
        Float32(1.0),
        UInt8(0)
    )
end
```

### 4.2 Integration Tests

**File:** `test/test_barprocessor_integration.jl` (NEW FILE)

```julia
using Test
using TickDataPipeline

@testset "BarProcessor Integration Tests" begin
    
    @testset "Pipeline with Bar Processing" begin
        # Create config with bar processing enabled
        config = PipelineConfig(
            tick_file_path = "test/data/sample_ticks.bin",
            signal_processing = SignalProcessingConfig(),
            bar_processing = BarProcessingConfig(
                enabled = true,
                ticks_per_bar = Int32(144)
            ),
            flow_control = FlowControlConfig(),
            channels = ChannelConfig(),
            performance = PerformanceConfig(),
            pipeline_name = "test_pipeline",
            description = "Test pipeline with bars",
            version = v"1.0.0"
        )
        
        # Create pipeline manager
        split_mgr = create_triple_split_manager()
        consumer = subscribe_consumer!(split_mgr, "test", PRIORITY, Int32(1000))
        pipeline = create_pipeline_manager(config, split_mgr)
        
        # Run pipeline with limited ticks
        pipeline_task = @async run_pipeline!(pipeline, max_ticks=Int64(1000))
        
        # Collect messages
        messages = BroadcastMessage[]
        bar_messages = BroadcastMessage[]
        
        consumer_task = @async begin
            for msg in consumer.channel
                push!(messages, msg)
                if msg.bar_idx !== nothing
                    push!(bar_messages, msg)
                end
            end
        end
        
        # Wait for completion
        wait(pipeline_task)
        sleep(0.1)
        close(consumer.channel)
        wait(consumer_task)
        
        # Verify results
        @test length(messages) == 1000
        @test length(bar_messages) > 0  # Should have some complete bars
        
        # Verify bar properties
        for bar_msg in bar_messages
            @test bar_msg.bar_idx !== nothing
            @test bar_msg.bar_ticks == Int32(144)
            @test bar_msg.bar_open_raw !== nothing
            @test bar_msg.bar_high_raw >= bar_msg.bar_low_raw
            @test bar_msg.bar_complex_signal !== nothing
            @test bar_msg.bar_normalization !== nothing
        end
        
        # Verify tick data still present on bar messages
        for bar_msg in bar_messages
            @test bar_msg.complex_signal !== nothing  # Tick signal
            @test bar_msg.normalization !== nothing   # Tick normalization
        end
    end
    
    @testset "Multiple Bar Sizes" begin
        # Test different bar sizes
        for ticks_per_bar in [21, 55, 144, 233]
            config = create_test_config(ticks_per_bar)
            state = create_bar_processor_state(config.bar_processing)
            
            # Process enough ticks for several bars
            num_ticks = ticks_per_bar * 5
            bar_count = 0
            
            for i in 1:num_ticks
                msg = create_test_message(Int64(i), Int32(100 + i), Int32(1))
                process_tick_for_bars!(msg, state)
                
                if msg.bar_idx !== nothing
                    bar_count += 1
                end
            end
            
            @test bar_count == 5  # Should have 5 complete bars
            @test state.bar_count == Int64(5)
        end
    end
end

function create_test_config(ticks_per_bar::Int32)
    return PipelineConfig(
        tick_file_path = "test/data/sample_ticks.bin",
        signal_processing = SignalProcessingConfig(),
        bar_processing = BarProcessingConfig(
            enabled = true,
            ticks_per_bar = ticks_per_bar
        ),
        flow_control = FlowControlConfig(),
        channels = ChannelConfig(),
        performance = PerformanceConfig(),
        pipeline_name = "test",
        description = "test",
        version = v"1.0.0"
    )
end
```

### 4.3 Test Execution

Update `test/runtests.jl`:

```julia
using Test
using TickDataPipeline

@testset "TickDataPipeline.jl" begin
    # Existing tests
    include("test_types.jl")
    include("test_config.jl")
    include("test_volumeexpander.jl")
    include("test_tickhotloop.jl")
    
    # New bar processor tests
    include("test_barprocessor.jl")
    include("test_barprocessor_integration.jl")
end
```

---

## Part 5: Documentation

### 5.1 User Guide

**File:** `docs/howto/Using_Bar_Processing.md` (NEW FILE)

```markdown
# Using Bar Processing in TickDataPipeline

## Overview

Bar processing aggregates ticks into bars and applies signal processing at the bar level, providing dual-timeframe analysis capabilities.

## Enabling Bar Processing

### 1. Configuration File

Edit `config/default.toml`:

```toml
[bar_processing]
enabled = true
ticks_per_bar = 144
normalization_window_bars = 24
winsorize_bar_threshold = 50
max_bar_jump = 100
derivative_imag_scale = 4.0
```

### 2. Programmatic Configuration

```julia
using TickDataPipeline

config = load_config_from_toml("config/default.toml")

# Or create config programmatically
config = PipelineConfig(
    # ... other fields ...
    bar_processing = BarProcessingConfig(
        enabled = true,
        ticks_per_bar = Int32(144),
        normalization_window_bars = Int32(24),
        winsorize_bar_threshold = Int32(50),
        max_bar_jump = Int32(100),
        derivative_imag_scale = Float32(4.0)
    )
)
```

## Using Bar Data in Consumers

```julia
# Subscribe to pipeline
split_mgr = create_triple_split_manager()
consumer = subscribe_consumer!(split_mgr, "my_consumer", PRIORITY, Int32(4096))

# Process messages
for msg in consumer.channel
    # Every message has tick-level data
    tick_signal = msg.complex_signal
    tick_norm = msg.normalization
    
    # Some messages have bar-level data
    if msg.bar_idx !== nothing
        bar_signal = msg.bar_complex_signal
        bar_norm = msg.bar_normalization
        
        # Bar OHLC
        println("Bar $(msg.bar_idx): O=$(msg.bar_open_raw), H=$(msg.bar_high_raw), " *
                "L=$(msg.bar_low_raw), C=$(msg.bar_close_raw)")
    end
end
```

## Choosing Bar Size and Normalization Window

### Bar Size Guidelines

- **Small bars (21-55 ticks)**: High-frequency patterns, quick reactions
- **Medium bars (144-233 ticks)**: Balance of responsiveness and stability
- **Large bars (610+ ticks)**: Long-term trends, reduced noise

### Normalization Window

Rule of thumb: `normalization_window_bars ≥ 20`

Examples:
- 21-tick bars → 120 bars window
- 144-tick bars → 24 bars window
- 233-tick bars → 20 bars window

Normalization is recalculated every N bars (where N = normalization_window_bars).

## Bar Signal Characteristics

### Derivative Encoding

Bars use derivative encoding (same as tick processing):
- **Real component**: Normalized bar position (bar price delta)
- **Imaginary component**: Normalized bar velocity (change in bar price delta)

### Normalization

Bar normalization is independent of tick normalization:
- Uses rolling window of bar statistics
- Tracks average high/low across bars
- Provides consistent scaling across instruments

## Performance Considerations

### Memory Overhead

- Minimal: Most messages have bar fields = `nothing`
- Only 1 out of N ticks carries bar data (N = ticks_per_bar)
- Bar state: ~100 bytes

### CPU Overhead

- Bar accumulation: ~5-10 CPU cycles per tick
- Bar completion: ~500-1000 CPU cycles (once per bar)
- Total: <1% overhead for typical bar sizes

## Examples

### Example 1: Basic Bar Consumer

```julia
function process_bars(consumer)
    bar_count = 0
    
    for msg in consumer.channel
        if msg.bar_idx !== nothing
            bar_count += 1
            
            println("Bar $bar_count:")
            println("  OHLC: $(msg.bar_open_raw), $(msg.bar_high_raw), " *
                   "$(msg.bar_low_raw), $(msg.bar_close_raw)")
            println("  Delta: $(msg.bar_price_delta)")
            println("  Signal: $(msg.bar_complex_signal)")
        end
    end
end
```

### Example 2: Dual-Timeframe Filter

```julia
function dual_timeframe_filter(msg)
    # High-frequency component from ticks
    tick_signal = msg.complex_signal
    
    # Low-frequency component from bars
    if msg.bar_idx !== nothing
        bar_signal = msg.bar_complex_signal
        
        # Combine signals
        combined = tick_signal + 0.5 * bar_signal
        return combined
    end
    
    return tick_signal
end
```

## Troubleshooting

### No Bar Data Appearing

1. Check `enabled = true` in config
2. Verify enough ticks processed (need at least `ticks_per_bar` ticks)
3. Check consumer is reading all messages

### Unexpected Bar Properties

1. Verify normalization window size (should be >> bar size)
2. Check winsorize/jump guard thresholds
3. Review bar accumulation logic with small bar size for debugging

## See Also

- [Signal Processing Documentation](./Signal_Processing.md)
- [Configuration Guide](./Configuration.md)
- [Consumer Implementation Guide](./Implementing_Consumers.md)
```

### 5.2 API Documentation

Add to `docs/api/BarProcessor.md`:

```markdown
# Bar Processor API Reference

## Types

### BarProcessingConfig

Configuration for bar-level signal processing.

**Fields:**
- `enabled::Bool`: Enable/disable bar processing
- `ticks_per_bar::Int32`: Number of ticks per bar
- `normalization_window_bars::Int32`: Recalculate normalization every N bars
- `winsorize_bar_threshold::Int32`: Clip bar deltas to ±threshold
- `max_bar_jump::Int32`: Maximum allowed bar-to-bar delta
- `derivative_imag_scale::Float32`: Scaling for bar velocity component

### BarProcessorState

State for bar processing - accumulates ticks and tracks normalization statistics.

**Fields:**
- `current_bar_tick_count::Int32`: Ticks accumulated in current bar
- `current_bar_open_raw::Int32`: First tick raw_price
- `current_bar_high_raw::Int32`: Max raw_price so far
- `current_bar_low_raw::Int32`: Min raw_price so far
- `current_bar_close_raw::Int32`: Most recent raw_price
- `bar_count::Int64`: Total bars completed
- `sum_bar_average_high::Int64`: Σ bar.average_high
- `sum_bar_average_low::Int64`: Σ bar.average_low
- `cached_bar_inv_norm_Q16::Int32`: Bar normalization reciprocal (Q16)
- `prev_bar_average_raw::Union{Int32, Nothing}`: Previous bar's average_raw
- `prev_bar_normalized_ratio::Float32`: Previous bar's normalized price_delta
- `config::BarProcessingConfig`: Configuration reference

## Functions

### create_bar_processor_state

```julia
create_bar_processor_state(config::BarProcessingConfig)::BarProcessorState
```

Create and initialize bar processor state.

### process_tick_for_bars!

```julia
process_tick_for_bars!(msg::BroadcastMessage, state::BarProcessorState)::Nothing
```

Process a tick through bar aggregator. Updates msg in-place with bar properties when bar completes.

### normalization_window_bars

```julia
normalization_window_bars(config::BarProcessingConfig)::Int32
```

Calculate number of bars in normalization window.

## BroadcastMessage Bar Fields

When a bar completes, these fields are populated in the final tick's BroadcastMessage:

- `bar_idx::Union{Int64, Nothing}`: Bar sequence number
- `bar_ticks::Union{Int32, Nothing}`: Ticks per bar
- `bar_volume::Union{Int32, Nothing}`: Bar volume (same as ticks)
- `bar_open_raw::Union{Int32, Nothing}`: Open price
- `bar_high_raw::Union{Int32, Nothing}`: High price
- `bar_low_raw::Union{Int32, Nothing}`: Low price
- `bar_close_raw::Union{Int32, Nothing}`: Close price
- `bar_average_raw::Union{Int32, Nothing}`: Average price
- `bar_price_delta::Union{Int32, Nothing}`: Bar-to-bar price change
- `bar_complex_signal::Union{ComplexF32, Nothing}`: Derivative encoded signal
- `bar_normalization::Union{Float32, Nothing}`: Normalization factor
- `bar_flags::Union{UInt8, Nothing}`: Processing flags
- `bar_end_timestamp::Union{UInt64, Nothing}`: Timestamp of final tick
```

---

## Part 6: Implementation Checklist

### Phase 1: Data Structures (Session 1)

- [ ] Add bar fields to `BroadcastMessage` in `src/types.jl`
- [ ] Update `BroadcastMessage` constructor
- [ ] Create `BarProcessingConfig` struct in `src/config.jl`
- [ ] Add `bar_processing` field to `PipelineConfig`
- [ ] Update TOML loading to support bar configuration
- [ ] Add bar processing section to `config/default.toml`
- [ ] Run existing tests to ensure no breakage

### Phase 2: Bar Processor Core (Session 1-2)

- [ ] Create `src/barprocessor.jl`
- [ ] Implement `BarProcessorState` struct
- [ ] Implement `create_bar_processor_state` function
- [ ] Implement `process_tick_for_bars!` function
- [ ] Implement `populate_bar_data!` function
- [ ] Implement `normalization_window_bars` helper
- [ ] Add exports to module

### Phase 3: Pipeline Integration (Session 2)

- [ ] Update `src/TickDataPipeline.jl` with includes/exports
- [ ] Add `bar_state` to `PipelineManager`
- [ ] Update `create_pipeline_manager` to initialize bar state
- [ ] Update message processing loop in `run_pipeline!`
- [ ] Run integration tests

### Phase 4: Unit Tests (Session 2-3)

- [ ] Create `test/test_barprocessor.jl`
- [ ] Test configuration creation
- [ ] Test state initialization
- [ ] Test bar accumulation (OHLC tracking)
- [ ] Test bar completion and reset
- [ ] Test normalization calculation
- [ ] Test jump guard and winsorizing
- [ ] Test derivative encoding
- [ ] Test disabled bar processing
- [ ] Run all unit tests

### Phase 5: Integration Tests (Session 3)

- [ ] Create `test/test_barprocessor_integration.jl`
- [ ] Test pipeline with bar processing enabled
- [ ] Test multiple bar sizes
- [ ] Test bar data availability in consumers
- [ ] Test tick data preservation on bar messages
- [ ] Run full test suite

### Phase 6: Documentation (Session 3)

- [ ] Create `docs/howto/Using_Bar_Processing.md`
- [ ] Create `docs/api/BarProcessor.md`
- [ ] Update main README with bar processing section
- [ ] Add examples to documentation

### Phase 7: Validation (Session 4)

- [ ] Run with real tick data (100K+ ticks)
- [ ] Verify bar properties are correct (OHLC, deltas)
- [ ] Verify normalization behavior over time
- [ ] Verify performance overhead is acceptable
- [ ] Test edge cases (first bar, very small bars, very large bars)
- [ ] Validate with different instruments

---

## Part 7: Success Criteria

### Functional Requirements

✅ **Bar Accumulation**
- Correctly tracks OHLC across tick accumulation
- Resets accumulator after bar completion
- Handles first bar initialization

✅ **Signal Processing**
- Jump guard clips extreme bar moves
- Winsorizing clips outliers
- Normalization uses rolling window
- Derivative encoding produces valid complex signals

✅ **Message Flow**
- Tick properties always present
- Bar properties only on bar completion
- Messages pass through without delay
- Consumers receive enriched messages

### Performance Requirements

✅ **Throughput**
- No significant reduction in ticks/second (<1% overhead)
- Bar completion overhead <1000 CPU cycles

✅ **Memory**
- State overhead <1KB
- Message overhead minimal (mostly nothing fields)

### Quality Requirements

✅ **Testing**
- Unit test coverage >90%
- Integration tests pass
- Edge cases handled

✅ **Documentation**
- User guide complete
- API reference complete
- Examples provided

---

## Part 8: Known Issues and Future Enhancements

### Known Limitations

1. **Fixed Window Size**: Normalization window is fixed, not adaptive
2. **No Bar History**: Only current and previous bar tracked
3. **Single Bar Size**: Only one bar size per pipeline instance

### Future Enhancements

1. **Multiple Bar Sizes**: Support multiple bar sizes simultaneously
2. **Adaptive Normalization**: Adjust window size based on volatility
3. **Bar History**: Maintain ring buffer of recent bars
4. **Bar Events**: Emit separate bar completion events
5. **Bar Filters**: Filters that consume only bar signals
6. **Time-Based Bars**: Support time-based instead of tick-based bars

---

## Part 9: Contact and Support

**Implementation Lead**: Claude Code  
**Project**: TickDataPipeline  
**Repository**: `C:\Users\Keith\source\repos\Julia\TickDataPipeline`

For questions or issues during implementation:
1. Review this specification
2. Check existing code patterns (TickHotLoop, VolumeExpander)
3. Run tests incrementally
4. Validate with small datasets first

---

## Appendix A: Code Style Guidelines

Follow existing TickDataPipeline patterns:

1. **Type Annotations**: Always specify types for struct fields
2. **Mutability**: Use `mutable struct` only when necessary
3. **In-place Updates**: Prefer `!` suffix for mutating functions
4. **Fixed-Point Math**: Use Q16 for normalization (like TickHotLoop)
5. **Error Handling**: Use `@warn` for non-fatal errors
6. **Documentation**: Add docstrings for all public functions
7. **Comments**: Explain "why" not "what"

## Appendix B: Testing Data

For integration tests, use:
- `test/data/sample_ticks.bin` (if exists)
- Or create synthetic tick data:

```julia
function create_test_ticks(count::Int)
    ticks = Int32[]
    price = Int32(10000)
    for i in 1:count
        delta = rand(-10:10)
        price += delta
        push!(ticks, price)
    end
    return ticks
end
```

## Appendix C: Reference Implementation

See existing implementations for patterns:
- **State management**: `src/tickhotloopf32.jl` → `TickHotLoopState`
- **Configuration**: `src/config.jl` → `SignalProcessingConfig`
- **In-place processing**: `src/tickhotloopf32.jl` → `process_tick_signal!`
- **Message enrichment**: `src/tickhotloopf32.jl` → `update_broadcast_message!`

---

**End of Implementation Guide**

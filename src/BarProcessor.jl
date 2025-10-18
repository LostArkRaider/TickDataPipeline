# src/BarProcessor.jl - Bar-Level Signal Processing
# Aggregates ticks into bars and applies signal processing at bar level
# Pass-through design: All ticks flow unchanged, bar data populated only at bar completion
# Supports two aggregation methods: boxcar (simple averaging) and FIR (anti-aliasing filter)

"""
BarProcessorState - State for bar aggregation and signal processing

Maintains current bar accumulation, normalization statistics, and derivative encoding state.
Supports both boxcar and FIR filtering methods.

# Fields

## Current Bar Accumulation (reset every bar)
- `tick_count::Int32`: Ticks accumulated in current bar (0 to ticks_per_bar-1)
- `bar_idx::Int64`: Current bar index (1, 2, 3, ...)
- `bar_open_raw::Int32`: First tick raw_price in bar
- `bar_high_raw::Int32`: Maximum raw_price in bar
- `bar_low_raw::Int32`: Minimum raw_price in bar
- `bar_close_raw::Int32`: Last tick raw_price in bar (updated each tick)

## FIR Filter State (only used when bar_method = "FIR")
- `fir_buffer::Vector{Int32}`: Circular buffer for FIR filtering (size = filter_length)
- `fir_coeffs::Vector{Float32}`: FIR filter coefficients
- `fir_buffer_idx::Int32`: Current write position in circular buffer
- `fir_group_delay::Int32`: Group delay of FIR filter (in samples)

## Normalization Statistics (cumulative across all bars)
- `sum_bar_average_high::Int64`: Sum of all bar high values
- `sum_bar_average_low::Int64`: Sum of all bar low values
- `bars_completed::Int64`: Total bars completed
- `cached_bar_normalization::Float32`: Current normalization factor
- `ticks_since_recalc::Int32`: Ticks since last normalization recalculation

## Derivative Encoding State
- `prev_bar_average_raw::Union{Int32, Nothing}`: Previous bar average for delta calculation

## Configuration
- `config::BarProcessingConfig`: Bar processing configuration
"""
mutable struct BarProcessorState
    # Current bar accumulation
    tick_count::Int32
    bar_idx::Int64
    bar_open_raw::Int32
    bar_high_raw::Int32
    bar_low_raw::Int32
    bar_close_raw::Int32

    # FIR filter state
    fir_buffer::Vector{Int32}
    fir_coeffs::Vector{Float32}
    fir_buffer_idx::Int32
    fir_group_delay::Int32

    # Normalization statistics
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

"""
    create_bar_processor_state(config::BarProcessingConfig)::BarProcessorState

Create bar processor state with configuration.

Initializes FIR filter if bar_method = "FIR", otherwise uses boxcar method.

# Arguments
- `config::BarProcessingConfig`: Bar processing configuration

# Returns
- `BarProcessorState`: Initialized state ready for processing

# Example
```julia
config = BarProcessingConfig(
    enabled = true,
    ticks_per_bar = Int32(144),
    normalization_window_bars = Int32(24),
    bar_method = "FIR"
)
state = create_bar_processor_state(config)
```
"""
function create_bar_processor_state(config::BarProcessingConfig)::BarProcessorState
    # Initialize FIR filter if needed
    fir_buffer = Int32[]
    fir_coeffs = Float32[]
    fir_group_delay = Int32(0)
    
    if config.enabled && config.bar_method == "FIR"
        # Design FIR filter for this decimation factor
        fir_coeffs = design_decimation_filter(config.ticks_per_bar)
        filter_length = length(fir_coeffs)
        fir_group_delay = Int32(div(filter_length - 1, 2))
        
        # Allocate circular buffer for FIR filtering
        fir_buffer = zeros(Int32, filter_length)
        
        @info "FIR filter initialized" decimation_factor=config.ticks_per_bar filter_length=filter_length group_delay=fir_group_delay
    end
    
    return BarProcessorState(
        Int32(0),           # tick_count starts at 0
        Int64(0),           # bar_idx starts at 0 (first bar will be 1)
        Int32(0),           # bar_open_raw (will be set on first tick)
        typemin(Int32),     # bar_high_raw (will track maximum)
        typemax(Int32),     # bar_low_raw (will track minimum)
        Int32(0),           # bar_close_raw (will be set on each tick)
        fir_buffer,         # FIR circular buffer
        fir_coeffs,         # FIR filter coefficients
        Int32(0),           # fir_buffer_idx
        fir_group_delay,    # fir_group_delay
        Int64(0),           # sum_bar_average_high
        Int64(0),           # sum_bar_average_low
        Int64(0),           # bars_completed
        Float32(1.0),       # cached_bar_normalization (preload to avoid div-by-zero)
        Int32(0),           # ticks_since_recalc
        nothing,            # prev_bar_average_raw (no previous bar yet)
        config              # config reference
    )
end

"""
    process_tick_for_bars!(msg::BroadcastMessage, state::BarProcessorState)

Process single tick for bar aggregation. Updates message in-place on bar completion.

This function is called for EVERY tick but only populates bar fields when a bar completes.
On non-completion ticks, bar fields remain `nothing` (pass-through).

Supports two bar aggregation methods:
- "boxcar": Simple averaging (OHLC + average)
- "FIR": Anti-aliasing filter with proper decimation

# Arguments
- `msg::BroadcastMessage`: Message to process (modified in-place on bar completion)
- `state::BarProcessorState`: Bar processor state (modified in-place)

# Message Flow
- Ticks 1-143: Bar fields remain `nothing` (pass-through)
- Tick 144: Bar fields populated with bar data (bar completion)

# Example
```julia
# In pipeline message loop
for msg in tick_channel
    process_tick_signal!(msg, tick_state, ...)     # Tick processing
    process_tick_for_bars!(msg, bar_state)         # Bar processing (NEW)
    broadcast_to_all!(split_manager, msg)          # Broadcasting
end
```
"""
function process_tick_for_bars!(msg::BroadcastMessage, state::BarProcessorState)
    # Early exit if bar processing disabled
    if !state.config.enabled
        return
    end

    # Update FIR buffer if using FIR method
    if state.config.bar_method == "FIR" && !isempty(state.fir_buffer)
        # Write to circular buffer
        state.fir_buffer_idx = mod1(state.fir_buffer_idx + 1, length(state.fir_buffer))
        state.fir_buffer[state.fir_buffer_idx] = msg.raw_price
    end

    # First tick of bar: Initialize OHLC
    if state.tick_count == Int32(0)
        state.bar_open_raw = msg.raw_price
        state.bar_high_raw = msg.raw_price
        state.bar_low_raw = msg.raw_price
        state.bar_close_raw = msg.raw_price
    else
        # Subsequent ticks: Update HLC
        state.bar_high_raw = max(state.bar_high_raw, msg.raw_price)
        state.bar_low_raw = min(state.bar_low_raw, msg.raw_price)
        state.bar_close_raw = msg.raw_price
    end

    # Increment tick counter
    state.tick_count += Int32(1)

    # Check for bar completion
    if state.tick_count >= state.config.ticks_per_bar
        # Bar is complete - populate message and reset state
        populate_bar_data!(msg, state)

        # Reset for next bar
        state.tick_count = Int32(0)
        state.bar_idx += Int64(1)
    end
    # If bar not complete, bar fields remain nothing (pass-through)
end

"""
    populate_bar_data!(msg::BroadcastMessage, state::BarProcessorState)

Populate bar fields in message on bar completion. Internal function.

Supports two bar aggregation methods:
1. "boxcar": Simple averaging (OHLC + average of high, low, close)
2. "FIR": Anti-aliasing FIR filter (convolution with filter coefficients)

Performs 14-step bar signal processing:
1. Extract OHLC from accumulated state
2. Calculate bar_average_raw based on method (boxcar or FIR)
3. Calculate bar averages (high/low) for normalization
4. Update cumulative statistics
5. Check for normalization recalculation
6. Calculate bar_price_delta = current - previous
7. Apply jump guard (clip extreme moves)
8. Winsorize (clip outliers)
9. Normalize using current normalization factor
10. Derivative encoding (position + velocity)
11. Update message in-place with bar data
12. Update state for next bar

# Arguments
- `msg::BroadcastMessage`: Message to populate (modified in-place)
- `state::BarProcessorState`: Bar processor state (modified in-place)
"""
function populate_bar_data!(msg::BroadcastMessage, state::BarProcessorState)
    # Step 1: Extract OHLC from state
    bar_open = state.bar_open_raw
    bar_high = state.bar_high_raw
    bar_low = state.bar_low_raw
    bar_close = state.bar_close_raw

    # Step 2: Calculate bar_average_raw based on method
    bar_average_raw = if state.config.bar_method == "FIR" && !isempty(state.fir_buffer)
        # FIR filtering: convolve buffer with coefficients
        calculate_fir_output(state)
    else
        # Boxcar: simple average of high, low, close
        Int32(round(Float32(bar_high + bar_low + bar_close) / Float32(3.0)))
    end

    # Step 3: Calculate bar averages for normalization
    # Use high and low for normalization (volatility measure)
    bar_average_high = bar_high
    bar_average_low = bar_low

    # Step 4: Update cumulative statistics
    state.sum_bar_average_high += Int64(bar_average_high)
    state.sum_bar_average_low += Int64(bar_average_low)
    state.bars_completed += Int64(1)

    # Step 5: Recalculate normalization every N bars
    state.ticks_since_recalc += state.config.ticks_per_bar
    recalc_period = state.config.normalization_window_bars * state.config.ticks_per_bar
    if state.ticks_since_recalc >= recalc_period
        # Calculate average high and low across all bars
        avg_high = Float32(state.sum_bar_average_high) / Float32(state.bars_completed)
        avg_low = Float32(state.sum_bar_average_low) / Float32(state.bars_completed)

        # Normalization = range = avg_high - avg_low
        state.cached_bar_normalization = max(avg_high - avg_low, Float32(1.0))

        # Reset recalculation counter
        state.ticks_since_recalc = Int32(0)
    end

    # Step 6: Calculate bar_price_delta
    bar_price_delta = if state.prev_bar_average_raw !== nothing
        bar_average_raw - state.prev_bar_average_raw
    else
        Int32(0)  # First bar has zero delta
    end

    # Step 7: Apply jump guard (clip extreme moves)
    bar_flags = FLAG_OK
    if abs(bar_price_delta) > state.config.max_bar_jump
        bar_price_delta = bar_price_delta > Int32(0) ?
            state.config.max_bar_jump :
            -state.config.max_bar_jump
        bar_flags |= FLAG_CLIPPED
    end

    # Step 8: Winsorize (clip outliers)
    if abs(bar_price_delta) > state.config.winsorize_bar_threshold
        bar_price_delta = sign(bar_price_delta) * state.config.winsorize_bar_threshold
        bar_flags |= FLAG_CLIPPED
    end

    # Step 9: Normalize using current normalization factor
    normalized_bar_delta = Float32(bar_price_delta) / state.cached_bar_normalization

    # Step 10: Derivative encoding (position + velocity)
    # Real component: normalized bar delta (position)
    # Imaginary component: change in normalized bar delta (velocity)
    prev_normalized = if state.prev_bar_average_raw !== nothing
        Float32(state.prev_bar_average_raw) / state.cached_bar_normalization
    else
        Float32(0.0)
    end

    current_normalized = Float32(bar_average_raw) / state.cached_bar_normalization
    derivative = current_normalized - prev_normalized
    scaled_derivative = derivative * state.config.bar_derivative_imag_scale

    bar_complex_signal = ComplexF32(normalized_bar_delta, scaled_derivative)

    # Step 11: Update message with bar data
    msg.bar_idx = state.bar_idx + Int64(1)  # Bar indices start at 1
    msg.bar_ticks = state.config.ticks_per_bar
    msg.bar_volume = state.config.ticks_per_bar  # 1 contract per tick
    msg.bar_open_raw = bar_open
    msg.bar_high_raw = bar_high
    msg.bar_low_raw = bar_low
    msg.bar_close_raw = bar_close
    msg.bar_average_raw = bar_average_raw
    msg.bar_price_delta = bar_price_delta
    msg.bar_complex_signal = bar_complex_signal
    msg.bar_normalization = state.cached_bar_normalization
    msg.bar_flags = bar_flags
    msg.bar_end_timestamp = UInt64(msg.timestamp)  # Current tick timestamp

    # Step 12: Update state for next bar
    state.prev_bar_average_raw = bar_average_raw
end

"""
    calculate_fir_output(state::BarProcessorState)::Int32

Calculate FIR filter output using circular buffer convolution.

Performs dot product of FIR coefficients with circular buffer.
Accounts for group delay to ensure proper alignment.

# Arguments
- `state::BarProcessorState`: Bar processor state with FIR buffer

# Returns
- `Int32`: Filtered value (rounded to nearest integer)
"""
function calculate_fir_output(state::BarProcessorState)::Int32
    filter_length = length(state.fir_coeffs)
    output = 0.0f0
    
    # Convolve filter with circular buffer
    # Start from current position and work backwards
    for i in 1:filter_length
        # Calculate buffer index (wrapping around)
        buffer_idx = mod1(state.fir_buffer_idx - i + 1, filter_length)
        output += state.fir_coeffs[i] * Float32(state.fir_buffer[buffer_idx])
    end
    
    return Int32(round(output))
end

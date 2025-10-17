# DERIVATIVE Encoder Implementation Checklist for TickHotLoopF32.jl

**Date:** October 15, 2025
 **Purpose:** Add DERIVATIVE encoding method to TickHotLoopF32.jl
 **Feature:** Phase space trajectory encoding using (normalized_ratio, acceleration)

------

## Change 1: Add State Field to TickHotLoopState

**Location:** `TickHotLoopState` struct definition (around line 48)

**Action:** Add new field after `amc_carrier_increment_Q32::Int32`

```julia
mutable struct TickHotLoopState
    last_clean::Union{Int32, Nothing}
    ema_delta::Int32
    ema_delta_dev::Int32
    has_delta_ema::Bool
    ema_abs_delta::Int32
    tick_count::Int64
    ticks_accepted::Int64

    # Bar statistics (144 ticks per bar)
    bar_tick_count::Int32
    bar_price_delta_min::Int32
    bar_price_delta_max::Int32

    # Rolling statistics across all bars
    sum_bar_min::Int64
    sum_bar_max::Int64
    bar_count::Int64

    # Cached normalization (updated at bar boundaries)
    cached_inv_norm_Q16::Int32

    # CPM encoder state (only used when encoder_type = "cpm")
    phase_accumulator_Q32::Int32

    # AMC encoder state (only used when encoder_type = "amc")
    amc_carrier_increment_Q32::Int32
    
    # DERIVATIVE encoder state (only used when encoder_type = "derivative")
    prev_normalized_ratio::Float32  # ADD THIS LINE
end
```

------

## Change 2: Initialize State Field

**Location:** `create_tickhotloop_state()` function (around line 66)

**Action:** Add initialization value in return statement

```julia
function create_tickhotloop_state()::TickHotLoopState
    return TickHotLoopState(
        nothing,      # No previous price
        Int32(0),     # ema_delta
        Int32(1),     # ema_delta_dev
        false,        # EMA not initialized
        Int32(10),    # AGC preload value (reserved)
        Int64(0),     # No ticks processed
        Int64(0),     # No ticks accepted

        # Bar statistics initialization
        Int32(0),            # bar_tick_count starts at 0
        typemax(Int32),      # bar_price_delta_min (will track minimum)
        typemin(Int32),      # bar_price_delta_max (will track maximum)

        # Rolling statistics initialization
        Int64(0),            # sum_bar_min
        Int64(0),            # sum_bar_max
        Int64(0),            # bar_count

        # Preload normalization reciprocal (data-driven: mean normalization = 8.67)
        Int32(round(Float32(65536) / Float32(8.67))),  # 1/8.67 in Q16

        # CPM state initialization
        Int32(0),  # phase_accumulator_Q32 starts at 0 radians

        # AMC state initialization
        # Default carrier period = 16 ticks (matches HEXAD16 compatibility)
        # Carrier increment = 2^32 / 16 = 268,435,456 (π/8 radians per tick)
        Int32(268435456),  # amc_carrier_increment_Q32
        
        # DERIVATIVE state initialization
        Float32(0.0)  # ADD THIS LINE - prev_normalized_ratio starts at 0
    )
end
```

------

## Change 3: Add DERIVATIVE Encoder Function

**Location:** After `process_tick_amc!()` function (around line 238)

**Action:** Insert complete new function

```julia
# DERIVATIVE encoder: Phase space trajectory encoding
# Encodes (normalized_dV, acceleration) as complex number for full 360° phase coverage
# Real part: normalized voltage change (position in normalized voltage space)
# Imaginary part: change in normalized voltage change (velocity in normalized voltage space)
#
# Arguments:
#   msg: BroadcastMessage to update (modified in-place)
#   state: TickHotLoopState containing prev_normalized_ratio (modified in-place)
#   normalized_ratio: Normalized price delta [-1, +1] typically (real component)
#   normalization_factor: Recovery factor for denormalization
#   flag: Status flags (UInt8)
#   imag_scale: Multiplier for imaginary scaling (1.0=no scale, 2.0=×2, 4.0=×4, etc.)
#
# Operation:
#   real = normalized_ratio (current normalized voltage change)
#   imag = (normalized_ratio - prev_normalized_ratio) × imag_scale (acceleration)
#   output = real + j·imag
#
# Advantages:
#   - No division required (just subtraction and multiply)
#   - Full 360° phase coverage (both components can be ±)
#   - No lookup tables or trig
#   - Physically meaningful: (position, velocity) in normalized phase space
#   - Works perfectly with event-driven sampling (dt implicit = 1 event)
#   - Consistent with other encoders (uses normalized values)
@inline function process_tick_derivative!(
    msg::BroadcastMessage,
    state::TickHotLoopState,
    normalized_ratio::Float32,
    normalization_factor::Float32,
    flag::UInt8,
    imag_scale::Float32
)
    # Compute derivative (change in normalized ratio)
    # This represents acceleration in normalized voltage space
    derivative = normalized_ratio - state.prev_normalized_ratio
    
    # Scale imaginary component for symmetry with real component
    # Typical: imag_scale = 2.0 to 4.0 for good circular symmetry
    scaled_derivative = derivative * imag_scale
    
    # Create complex signal from (normalized_ratio, scaled_derivative)
    # Both can be ± → full 360° coverage
    complex_signal = ComplexF32(normalized_ratio, scaled_derivative)
    
    # Update state for next tick
    state.prev_normalized_ratio = normalized_ratio
    
    # Update broadcast message
    update_broadcast_message!(msg, complex_signal, normalization_factor, flag)
end
```

------

## Change 4: Add Parameter to process_tick_signal!

**Location:** Function signature for `process_tick_signal!()` (around line 257)

**Action:** Add new parameter at end of parameter list

```julia
function process_tick_signal!(
    msg::BroadcastMessage,
    state::TickHotLoopState,
    agc_alpha::Float32,
    agc_min_scale::Int32,
    agc_max_scale::Int32,
    winsorize_delta_threshold::Int32,
    min_price::Int32,
    max_price::Int32,
    max_jump::Int32,
    encoder_type::String,
    cpm_modulation_index::Float32,
    derivative_imag_scale::Float32  # ADD THIS LINE
)
```

------

## Change 5: Update Encoder Selection Logic

**Location:** Step 10 in `process_tick_signal!()` - the encoder selection block (around line 355)

**Action:** Add derivative case at the beginning of the if-elseif chain

**FIND THIS CODE:**

```julia
    # Step 10: Encoder selection - HEXAD-16, CPM, or AMC
    if encoder_type == "amc"
        # AMC encoder: Amplitude-modulated continuous carrier (harmonic elimination)
        process_tick_amc!(msg, state, normalized_ratio, normalization_factor, flag)
    elseif encoder_type == "cpm"
```

**REPLACE WITH:**

```julia
    # Step 10: Encoder selection - HEXAD-16, CPM, AMC, or DERIVATIVE
    if encoder_type == "derivative"
        # DERIVATIVE encoder: Phase space (normalized_dV, acceleration) encoding
        # Uses normalized_ratio (same as other encoders for consistency)
        process_tick_derivative!(msg, state, normalized_ratio, normalization_factor, flag, derivative_imag_scale)
    elseif encoder_type == "amc"
        # AMC encoder: Amplitude-modulated continuous carrier (harmonic elimination)
        process_tick_amc!(msg, state, normalized_ratio, normalization_factor, flag)
    elseif encoder_type == "cpm"
```

------

## Change 6: Update Comments in Encoder Selection

**Location:** Same encoder selection block - update the top comment

**FIND THIS:**

```julia
    # Step 10: Encoder selection - HEXAD-16, CPM, or AMC
```

**REPLACE WITH:**

```julia
    # Step 10: Encoder selection - HEXAD-16, CPM, AMC, or DERIVATIVE
```

------

## Change 7: Update Config File (config.toml)

**Location:** Your pipeline config.toml file

**Action:** Add new parameter to encoder configuration section

```toml
[encoder]
type = "derivative"  # Options: "hexad16", "cpm", "amc", "derivative"

# HEXAD-16 encoder (no parameters)

# CPM encoder parameters
cpm_modulation_index = 0.5

# DERIVATIVE encoder parameters
derivative_imag_scale = 4.0  # ADD THIS LINE - Scaling for imaginary component (2.0-4.0 recommended)
```

------

## Change 8: Update Any Calling Code

**Location:** Any code that calls `process_tick_signal!()`

**Action:** Add the new parameter from config

**Example before:**

```julia
process_tick_signal!(
    msg, state,
    agc_alpha, agc_min, agc_max,
    winsorize_thresh,
    min_price, max_price, max_jump,
    encoder_type,
    cpm_h
)
```

**Example after:**

```julia
process_tick_signal!(
    msg, state,
    agc_alpha, agc_min, agc_max,
    winsorize_thresh,
    min_price, max_price, max_jump,
    encoder_type,
    cpm_h,
    derivative_scale  # ADD THIS LINE - from config
)
```

------

## Verification Checklist

After making all changes, verify:

- [ ] `TickHotLoopState` has `prev_normalized_ratio::Float32` field
- [ ] `create_tickhotloop_state()` initializes `Float32(0.0)` for prev_normalized_ratio
- [ ] `process_tick_derivative!()` function exists and is marked `@inline`
- [ ] `process_tick_signal!()` has `derivative_imag_scale::Float32` parameter
- [ ] Encoder selection includes `if encoder_type == "derivative"` case
- [ ] Config file has `derivative_imag_scale` parameter
- [ ] All calling code passes the new parameter

------

## Testing

Test the new encoder with a simple example:

```julia
using TickDataPipeline

# Create state
state = create_tickhotloop_state()

# Configure for derivative encoder
encoder = "derivative"
derivative_scale = Float32(4.0)

# Process some test messages
tick_channel = stream_expanded_ticks("test_data.txt", 0.0)

for msg in tick_channel
    process_tick_signal!(
        msg, state,
        Float32(0.0625),  # agc_alpha
        Int32(4),         # agc_min_scale
        Int32(50),        # agc_max_scale
        Int32(10),        # winsorize_threshold
        Int32(40000),     # min_price
        Int32(43000),     # max_price
        Int32(50),        # max_jump
        encoder,          # "derivative"
        Float32(0.5),     # cpm_h (unused)
        derivative_scale  # derivative_imag_scale
    )
    
    # Check output
    println("Tick $(msg.tick_idx): z = $(msg.complex_signal)")
    
    # Verify both real and imaginary can be positive and negative
    if msg.tick_idx > 10
        break
    end
end
```

------

## Expected Behavior

With the DERIVATIVE encoder:

1. **First tick**: `complex_signal = (0.0 + 0.0im)` - no previous value
2. **Subsequent ticks**: Both real and imaginary components can be ±
3. **Full 360° coverage**: Phase angle should span all quadrants
4. **Real component**: Equals normalized_ratio (normalized price change)
5. **Imaginary component**: Equals derivative × imag_scale (acceleration)

------

## Performance Notes

The DERIVATIVE encoder:

- **No trig calculations**: Just subtraction and multiply
- **No lookup tables**: No memory access beyond the message itself
- **No branching**: Straight-line code in hot path
- **Minimal state**: Just one Float32 value
- **Fast**: Should be the fastest of all encoders (~30-40 μs per tick)

------

## Rollback Plan

If issues occur, to rollback:

1. Remove `prev_normalized_ratio::Float32` from `TickHotLoopState`
2. Remove `Float32(0.0)` initialization
3. Delete `process_tick_derivative!()` function
4. Remove `derivative_imag_scale::Float32` parameter
5. Remove `if encoder_type == "derivative"` branch
6. Remove config file entry
7. Revert calling code to previous signature

------

**Implementation Status:** Not Started
 **Estimated Time:** 15-20 minutes
 **Testing Time:** 10-15 minutes
 **Total:** ~30 minutes
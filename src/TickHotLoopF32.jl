# src/TickHotLoopF32.jl - Ultra-Fast Signal Processing
# Design Specification v2.4 Implementation
# ZERO BRANCHING for feature enablement - all features ALWAYS ENABLED
# Updated: 2025-10-04 - Fixed QUAD-4 rotation with constant tuple

# Note: Using parent module's BroadcastMessage and FLAG constants
# This module is included in TickDataPipeline

# QUAD-4 phase rotation multipliers (0°, 90°, 180°, 270°)
const QUAD4 = (ComplexF32(1, 0), ComplexF32(0, 1), ComplexF32(-1, 0), ComplexF32(0, -1))

"""
TickHotLoopState - Stateful processing for TickHotLoopF32

Tracks EMA values and AGC state across ticks for signal processing.
All fields are mutable for in-place state updates.

# Fields
- `last_clean::Union{Int32, Nothing}`: Last accepted clean price
- `ema_delta::Int32`: EMA of price deltas
- `ema_delta_dev::Int32`: EMA of |Δ - emaΔ| for winsorization
- `has_delta_ema::Bool`: Whether EMA has been initialized
- `ema_abs_delta::Int32`: EMA of absolute delta for AGC
- `tick_count::Int64`: Total ticks processed
- `ticks_accepted::Int64`: Ticks accepted (not held)
"""
mutable struct TickHotLoopState
    # Price tracking
    last_clean::Union{Int32, Nothing}

    # EMA state for normalization
    ema_delta::Int32
    ema_delta_dev::Int32
    has_delta_ema::Bool

    # AGC state
    ema_abs_delta::Int32

    # Counters
    tick_count::Int64
    ticks_accepted::Int64
end

"""
    create_tickhotloop_state()::TickHotLoopState

Create initial TickHotLoopState with default values.

# Returns
- `TickHotLoopState` initialized for first tick
"""
function create_tickhotloop_state()::TickHotLoopState
    return TickHotLoopState(
        nothing,           # last_clean
        Int32(0),         # ema_delta
        Int32(1),         # ema_delta_dev
        false,            # has_delta_ema
        Int32(10),        # ema_abs_delta (nominal preload)
        Int64(0),         # tick_count
        Int64(0)          # ticks_accepted
    )
end

"""
    apply_quad4_rotation(normalized_value::Float32, phase_pos::Int32)::ComplexF32

Apply QUAD-4 phase rotation by multiplying scalar value by complex phasor.

# Arguments
- `normalized_value::Float32`: Normalized signal value (real scalar)
- `phase_pos::Int32`: Phase position (0, 1, 2, 3)

# Returns
- `ComplexF32`: Rotated complex signal = normalized_value × QUAD4[phase]
  - pos 0 (0°):   value × (1, 0)   → (value, 0)
  - pos 1 (90°):  value × (0, 1)   → (0, value)
  - pos 2 (180°): value × (-1, 0)  → (-value, 0)
  - pos 3 (270°): value × (0, -1)  → (0, -value)
"""
@inline function apply_quad4_rotation(normalized_value::Float32, phase_pos::Int32)::ComplexF32
    phase = (phase_pos & Int32(3)) + Int32(1)  # Bitwise AND for fast modulo-4, convert to 1-based index
    return normalized_value * QUAD4[phase]
end

"""
    phase_pos_global(tick_idx::Int64)::Int32

Calculate global phase position that cycles through 0, 1, 2, 3.

# Arguments
- `tick_idx::Int64`: Current tick index (1-based)

# Returns
- `Int32`: Phase position (0, 1, 2, 3)
"""
function phase_pos_global(tick_idx::Int64)::Int32
    return Int32((tick_idx - 1) & 3)  # Bitwise AND for fast modulo-4
end

"""
    process_tick_signal!(msg, state, agc_alpha, agc_min_scale, agc_max_scale,
                        winsorize_threshold, min_price, max_price, max_jump)

Process single tick signal with IN-PLACE BroadcastMessage update.

PERFORMANCE CRITICAL: All features ALWAYS ENABLED (zero branching for enablement).

# Algorithm
1. Absolute price validation (min_price, max_price)
2. Initialize on first good tick
3. Hard jump guard (max_jump)
4. Update EMA for normalization (alpha = 1/16)
5. AGC (Automatic Gain Control)
6. Normalize price delta
7. Winsorization (outlier clipping)
8. QUAD-4 rotation
9. Update BroadcastMessage IN-PLACE

# Arguments
- `msg::BroadcastMessage`: Message with price_delta already populated (MODIFIED IN-PLACE)
- `state::TickHotLoopState`: Stateful processing state (MODIFIED IN-PLACE)
- `agc_alpha::Float32`: AGC alpha (e.g., 0.0625 = 1/16)
- `agc_min_scale::Int32`: AGC minimum scale (prevents over-amplification)
- `agc_max_scale::Int32`: AGC maximum scale (prevents under-amplification)
- `winsorize_threshold::Float32`: Winsorization threshold (e.g., 3.0 sigma)
- `min_price::Int32`: Minimum valid price
- `max_price::Int32`: Maximum valid price
- `max_jump::Int32`: Maximum allowed price jump

# Modifies
- `msg.complex_signal`: Set to processed signal
- `msg.normalization`: Set to AGC scale factor
- `msg.status_flag`: Set to processing flags
- `state`: All fields updated
"""
function process_tick_signal!(
    msg::BroadcastMessage,
    state::TickHotLoopState,
    agc_alpha::Float32,
    agc_min_scale::Int32,
    agc_max_scale::Int32,
    winsorize_threshold::Float32,
    min_price::Int32,
    max_price::Int32,
    max_jump::Int32
)
    price_delta = msg.price_delta
    flag = FLAG_OK

    # Absolute price validation (ALWAYS ENABLED)
    if msg.raw_price < min_price || msg.raw_price > max_price
        if state.last_clean !== nothing
            flag |= FLAG_HOLDLAST
            # Use zero delta, previous signal
            normalized_ratio = Float32(0.0)
            phase = phase_pos_global(Int64(msg.tick_idx))
            z = apply_quad4_rotation(normalized_ratio, phase)

            update_broadcast_message!(msg, z, Float32(1.0), flag)
            state.ticks_accepted += Int64(1)
            return
        else
            # First tick invalid, hold
            update_broadcast_message!(msg, ComplexF32(0, 0), Float32(1.0), FLAG_OK)
            return
        end
    end

    # Initialize on first good tick
    if state.last_clean === nothing
        state.last_clean = msg.raw_price
        normalized_ratio = Float32(0.0)
        phase = phase_pos_global(Int64(msg.tick_idx))
        z = apply_quad4_rotation(normalized_ratio, phase)

        update_broadcast_message!(msg, z, Float32(1.0), FLAG_OK)
        state.ticks_accepted += Int64(1)
        return
    end

    # Get delta
    delta = price_delta

    # Hard jump guard (ALWAYS ENABLED)
    if abs(delta) > max_jump
        delta = delta > Int32(0) ? max_jump : -max_jump
        flag |= FLAG_CLIPPED
    end

    # Update EMA for normalization (ALWAYS ENABLED)
    abs_delta = abs(delta)

    if state.has_delta_ema
        # Update EMA (alpha = 1/16 = 0.0625)
        state.ema_delta = state.ema_delta + ((delta - state.ema_delta) >> 4)
        dev = abs(delta - state.ema_delta)
        state.ema_delta_dev = state.ema_delta_dev + ((dev - state.ema_delta_dev) >> 4)
    else
        state.ema_delta = delta
        state.ema_delta_dev = max(abs_delta, Int32(1))
        state.has_delta_ema = true
    end

    # AGC (ALWAYS ENABLED)
    # Update EMA of absolute delta
    state.ema_abs_delta = state.ema_abs_delta +
                         Int32(round((Float32(abs_delta) - Float32(state.ema_abs_delta)) * agc_alpha))

    # Calculate AGC scale
    agc_scale = max(state.ema_abs_delta, Int32(1))
    agc_scale = clamp(agc_scale, agc_min_scale, agc_max_scale)

    if agc_scale >= agc_max_scale
        flag |= FLAG_AGC_LIMIT
    end

    # Normalize (ALWAYS ENABLED)
    normalized_ratio = Float32(delta) / Float32(agc_scale)

    # Winsorization (ALWAYS ENABLED)
    if abs(normalized_ratio) > winsorize_threshold
        normalized_ratio = sign(normalized_ratio) * winsorize_threshold
        flag |= FLAG_CLIPPED
    end

    # Scale to ±0.5 range for price/volume symmetry (winsorize_threshold=3.0 → ±0.5)
    normalized_ratio = normalized_ratio / Float32(6.0)

    # Normalization factor includes both AGC scale and 1/6 adjustment
    # To recover price_delta: complex_signal_real × normalization_factor = price_delta
    normalization_factor = Float32(agc_scale) * Float32(6.0)

    # Apply QUAD-4 rotation (ALWAYS ENABLED)
    phase = phase_pos_global(Int64(msg.tick_idx))
    z = apply_quad4_rotation(normalized_ratio, phase)

    # Update message IN-PLACE
    update_broadcast_message!(msg, z, normalization_factor, flag)

    # Update state
    state.last_clean = msg.raw_price
    state.ticks_accepted += Int64(1)
end

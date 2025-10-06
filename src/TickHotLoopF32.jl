# TickHotLoopF32.jl - High-Performance Signal Processing
# All features always enabled - zero branching for optimal performance

# 16-phase rotation constants (22.5° increments)
# Provides fine angular resolution without trig calculations
const COS_22_5 = Float32(0.9238795325112867)   # cos(22.5°)
const SIN_22_5 = Float32(0.3826834323650898)   # sin(22.5°)
const COS_67_5 = Float32(0.3826834323650898)   # cos(67.5°)
const SIN_67_5 = Float32(0.9238795325112867)   # sin(67.5°)
const SQRT2_OVER_2 = Float32(0.7071067811865476)  # √2/2 for 45°, 135°, etc.

# HEXAD-16 phase rotation: 0°, 22.5°, 45°, 67.5°, ..., 337.5°
const HEXAD16 = (
    ComplexF32(1.0, 0.0),                        # 0°
    ComplexF32(COS_22_5, SIN_22_5),              # 22.5°
    ComplexF32(SQRT2_OVER_2, SQRT2_OVER_2),      # 45°
    ComplexF32(COS_67_5, SIN_67_5),              # 67.5°
    ComplexF32(0.0, 1.0),                        # 90°
    ComplexF32(-COS_67_5, SIN_67_5),             # 112.5°
    ComplexF32(-SQRT2_OVER_2, SQRT2_OVER_2),     # 135°
    ComplexF32(-COS_22_5, SIN_22_5),             # 157.5°
    ComplexF32(-1.0, 0.0),                       # 180°
    ComplexF32(-COS_22_5, -SIN_22_5),            # 202.5°
    ComplexF32(-SQRT2_OVER_2, -SQRT2_OVER_2),    # 225°
    ComplexF32(-COS_67_5, -SIN_67_5),            # 247.5°
    ComplexF32(0.0, -1.0),                       # 270°
    ComplexF32(COS_67_5, -SIN_67_5),             # 292.5°
    ComplexF32(SQRT2_OVER_2, -SQRT2_OVER_2),     # 315°
    ComplexF32(COS_22_5, -SIN_22_5)              # 337.5°
)

# Bar size for statistics tracking
# 144 ticks = 9 complete 16-phase cycles (perfect alignment)
const TICKS_PER_BAR = Int32(144)

# State container for signal processing across ticks
mutable struct TickHotLoopState
    last_clean::Union{Int32, Nothing}  # Last valid price
    ema_delta::Int32                   # EMA of deltas (unused, reserved)
    ema_delta_dev::Int32              # EMA of delta deviation (unused, reserved)
    has_delta_ema::Bool               # EMA initialization flag
    ema_abs_delta::Int32              # AGC: EMA of absolute delta (reserved)
    tick_count::Int64                 # Total ticks processed
    ticks_accepted::Int64             # Ticks accepted (not rejected)

    # Bar statistics (144 ticks per bar)
    bar_tick_count::Int32             # Current position in bar (0-143)
    bar_price_delta_min::Int32        # Min delta in current bar
    bar_price_delta_max::Int32        # Max delta in current bar

    # Rolling statistics across all bars
    sum_bar_min::Int64                # Sum of all bar minimums
    sum_bar_max::Int64                # Sum of all bar maximums
    bar_count::Int64                  # Total bars completed

    # Cached normalization (updated at bar boundaries)
    cached_inv_norm_Q16::Int32        # 1/normalization in Q16 fixed-point
end

# Initialize state with default values
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

        # Preload normalization reciprocal (assume range of 20 initially)
        Int32(round(Float32(65536) / Float32(20)))  # 1/20 in Q16
    )
end

# Apply HEXAD-16 rotation: scalar × complex phasor → complex output
# Maps normalized value to one of 16 phases (0° to 337.5° in 22.5° increments)
# No trig - just table lookup and complex multiply
@inline function apply_hexad16_rotation(normalized_value::Float32, phase_pos::Int32)::ComplexF32
    phase = (phase_pos & Int32(15)) + Int32(1)  # Modulo-16, convert to 1-based
    return normalized_value * HEXAD16[phase]
end

# Calculate global phase position: cycles 0,1,2,3,...,14,15,0,1,...
# 144 ticks per bar = 9 complete 16-phase cycles
function phase_pos_global(tick_idx::Int64)::Int32
    return Int32((tick_idx - 1) & 15)  # Fast modulo-16
end

# Main signal processing function - modifies msg and state in-place
# Processing chain: validation → jump guard → winsorize → bar stats → normalize → HEXAD-16 → output
function process_tick_signal!(
    msg::BroadcastMessage,
    state::TickHotLoopState,
    agc_alpha::Float32,
    agc_min_scale::Int32,
    agc_max_scale::Int32,
    winsorize_delta_threshold::Int32,
    min_price::Int32,
    max_price::Int32,
    max_jump::Int32
)
    price_delta = msg.price_delta
    flag = FLAG_OK

    # Step 1: Price validation
    if msg.raw_price < min_price || msg.raw_price > max_price
        if state.last_clean !== nothing
            # Hold last valid signal
            flag |= FLAG_HOLDLAST
            normalized_ratio = Float32(0.0)
            phase = phase_pos_global(Int64(msg.tick_idx))
            z = apply_hexad16_rotation(normalized_ratio, phase)
            update_broadcast_message!(msg, z, Float32(1.0), flag)
            state.ticks_accepted += Int64(1)
            return
        else
            # First tick invalid - output zeros
            update_broadcast_message!(msg, ComplexF32(0, 0), Float32(1.0), FLAG_OK)
            return
        end
    end

    # Step 2: First tick initialization
    if state.last_clean === nothing
        state.last_clean = msg.raw_price
        normalized_ratio = Float32(0.0)
        phase = phase_pos_global(Int64(msg.tick_idx))
        z = apply_hexad16_rotation(normalized_ratio, phase)
        update_broadcast_message!(msg, z, Float32(1.0), FLAG_OK)
        state.ticks_accepted += Int64(1)
        return
    end

    delta = price_delta

    # Step 3: Jump guard (clip extreme moves)
    if abs(delta) > max_jump
        delta = delta > Int32(0) ? max_jump : -max_jump
        flag |= FLAG_CLIPPED
    end

    # Step 4: Winsorize raw delta BEFORE bar statistics
    # Data-driven threshold (10) clips top 0.5% of deltas
    # Prevents outliers from skewing bar min/max statistics
    if abs(delta) > winsorize_delta_threshold
        delta = sign(delta) * winsorize_delta_threshold
        flag |= FLAG_CLIPPED
    end

    # Step 5: Update EMA statistics (reserved for future use)
    abs_delta = abs(delta)
    if state.has_delta_ema
        state.ema_delta = state.ema_delta + ((delta - state.ema_delta) >> 4)
        dev = abs(delta - state.ema_delta)
        state.ema_delta_dev = state.ema_delta_dev + ((dev - state.ema_delta_dev) >> 4)
    else
        state.ema_delta = delta
        state.ema_delta_dev = max(abs_delta, Int32(1))
        state.has_delta_ema = true
    end

    # Step 6: Update AGC (reserved for future use)
    state.ema_abs_delta = state.ema_abs_delta +
                         Int32(round((Float32(abs_delta) - Float32(state.ema_abs_delta)) * agc_alpha))

    # Step 7: Update bar statistics (track min/max within current bar)
    # Now uses winsorized delta - outliers already clipped
    state.bar_tick_count += Int32(1)
    state.bar_price_delta_min = min(state.bar_price_delta_min, delta)
    state.bar_price_delta_max = max(state.bar_price_delta_max, delta)

    # Step 8: Check for bar boundary (every 144 ticks)
    if state.bar_tick_count >= TICKS_PER_BAR
        # Accumulate bar statistics
        state.sum_bar_min += Int64(state.bar_price_delta_min)
        state.sum_bar_max += Int64(state.bar_price_delta_max)
        state.bar_count += Int64(1)

        # Compute rolling averages
        avg_min = state.sum_bar_min / state.bar_count
        avg_max = state.sum_bar_max / state.bar_count

        # Compute normalization range (max - min)
        normalization = max(avg_max - avg_min, Int64(1))

        # Pre-compute reciprocal in Q16 fixed-point
        # 65536 = 2^16 for Q16 fixed-point representation
        state.cached_inv_norm_Q16 = Int32(round(Float32(65536) / Float32(normalization)))

        # Reset bar counters
        state.bar_tick_count = Int32(0)
        state.bar_price_delta_min = typemax(Int32)
        state.bar_price_delta_max = typemin(Int32)
    end

    # Step 9: Normalize using Q16 fixed-point (fast integer multiply)
    normalized_Q16 = delta * state.cached_inv_norm_Q16
    normalized_ratio = Float32(normalized_Q16) * Float32(1.52587890625e-5)  # 1/(2^16)

    # Normalization factor for recovery
    # Recovery: complex_signal_real × normalization_factor = price_delta (approximately)
    # Note: With bar-based normalization, recovery uses bar statistics
    normalization_factor = Float32(1.0) / (Float32(state.cached_inv_norm_Q16) * Float32(1.52587890625e-5))

    # Step 10: Apply HEXAD-16 phase rotation
    phase = phase_pos_global(Int64(msg.tick_idx))
    z = apply_hexad16_rotation(normalized_ratio, phase)

    # Step 11: Update message with processed signal
    update_broadcast_message!(msg, z, normalization_factor, flag)

    # Update state for next tick
    state.last_clean = msg.raw_price
    state.ticks_accepted += Int64(1)
end

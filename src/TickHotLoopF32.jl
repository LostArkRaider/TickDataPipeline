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

# CPM (Continuous Phase Modulation) encoder constants
# 1024-entry complex phasor lookup table for CPM encoding
# Maps phase [0, 2π) to unit-circle complex phasors
# Used when encoder_type = "cpm" (configured in PipelineConfig)
const CPM_LUT_1024 = Tuple(
    ComplexF32(
        cos(Float32(2π * k / 1024)),
        sin(Float32(2π * k / 1024))
    ) for k in 0:1023
)

# CPM encoder processing constants
const CPM_Q32_SCALE_H05 = Float32(2^31)  # Phase increment scale for h=0.5
const CPM_INDEX_SHIFT = Int32(22)         # Bit shift for 10-bit LUT indexing
const CPM_INDEX_MASK = UInt32(0x3FF)      # 10-bit mask (1023 max index)

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

    # CPM encoder state (only used when encoder_type = "cpm")
    phase_accumulator_Q32::Int32      # Accumulated phase in Q32 format [0, 2^32) → [0, 2π)

    # AMC encoder state (only used when encoder_type = "amc")
    amc_carrier_increment_Q32::Int32  # Constant phase increment per tick for AMC carrier

    # DERIVATIVE encoder state (only used when encoder_type = "derivative")
    prev_normalized_ratio::Float32  # ADD THIS LINE
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

# CPM encoder: Continuous Phase Modulation
# Converts normalized input to phase increment, accumulates phase, generates I/Q from LUT
# Phase memory persists across ticks (true CPM with continuous phase)
#
# Arguments:
#   msg: BroadcastMessage to update (modified in-place)
#   state: TickHotLoopState containing phase accumulator (modified in-place)
#   normalized_ratio: Normalized price delta [-1, +1] typically
#   normalization_factor: Recovery factor for denormalization
#   flag: Status flags (UInt8)
#   h: Modulation index (0.5 = MSK characteristics, configurable)
#
# Operation:
#   Δθ[n] = 2πh·m[n] where m[n] = normalized_ratio
#   θ[n] = θ[n-1] + Δθ[n] (accumulated in Q32 fixed-point)
#   output = exp(j·θ[n]) = cos(θ) + j·sin(θ) (via LUT)
@inline function process_tick_cpm!(
    msg::BroadcastMessage,
    state::TickHotLoopState,
    normalized_ratio::Float32,
    normalization_factor::Float32,
    flag::UInt8,
    h::Float32
)
    # Step 1: Compute phase increment in Q32 fixed-point
    # Δθ = 2πh × normalized_ratio
    # In Q32: 2π radians = 2^32 counts, so 1 radian = 2^31/π counts
    # For efficiency: Δθ_Q32 = normalized_ratio × h × 2^32 = normalized_ratio × h × 2 × 2^31
    # Simplify: Δθ_Q32 = normalized_ratio × (2h × 2^31)
    phase_scale = Float32(2.0) * h * CPM_Q32_SCALE_H05
    # Use unsafe_trunc to handle Float32 values that exceed Int32 range (allows intentional overflow)
    delta_phase_Q32 = unsafe_trunc(Int32, round(normalized_ratio * phase_scale))

    # Step 2: Accumulate phase (automatic wraparound at ±2^31)
    # Int32 overflow provides modulo 2π behavior
    state.phase_accumulator_Q32 += delta_phase_Q32

    # Step 3: Extract 10-bit LUT index from upper bits of phase
    # Shift right 22 bits to get upper 10 bits, mask to ensure 0-1023 range
    # Use reinterpret to treat Int32 as UInt32 for bit manipulation (handles negative values)
    lut_index = Int32((reinterpret(UInt32, state.phase_accumulator_Q32) >> CPM_INDEX_SHIFT) & CPM_INDEX_MASK)

    # Step 4: Lookup complex phasor (Julia 1-based indexing)
    complex_signal = CPM_LUT_1024[lut_index + 1]

    # Step 5: Update broadcast message with CPM-encoded signal
    update_broadcast_message!(msg, complex_signal, normalization_factor, flag)
end

# AMC encoder: Amplitude-Modulated Continuous Carrier
# Encodes price delta as amplitude modulation on a constant-frequency carrier
# Eliminates HEXAD16 harmonics while preserving amplitude-based filter compatibility
#
# Arguments:
#   msg: BroadcastMessage to update (modified in-place)
#   state: TickHotLoopState containing carrier phase and increment (modified in-place)
#   normalized_ratio: Normalized price delta [-1, +1] typically (amplitude)
#   normalization_factor: Recovery factor for denormalization
#   flag: Status flags (UInt8)
#
# Operation:
#   θ[n] = θ[n-1] + ω_carrier (constant phase increment)
#   A[n] = normalized_ratio (amplitude from price delta)
#   output = A[n] × exp(j·θ[n]) = A[n] × (cos(θ) + j·sin(θ)) (via LUT)
#
# Key difference from CPM: Phase increment is CONSTANT (not modulated by price delta)
# This creates continuous carrier with amplitude modulation (AM), not frequency modulation (FM)
@inline function process_tick_amc!(
    msg::BroadcastMessage,
    state::TickHotLoopState,
    normalized_ratio::Float32,
    normalization_factor::Float32,
    flag::UInt8
)
    # Step 1: Advance carrier phase by constant increment
    # This creates smooth continuous rotation at fixed frequency
    # Unlike CPM, this increment does NOT vary with price_delta
    state.phase_accumulator_Q32 += state.amc_carrier_increment_Q32

    # Step 2: Extract 10-bit LUT index from upper bits of phase
    # Same indexing method as CPM (shares LUT)
    lut_index = Int32((reinterpret(UInt32, state.phase_accumulator_Q32) >> CPM_INDEX_SHIFT) & CPM_INDEX_MASK)

    # Step 3: Lookup carrier phasor (unit magnitude complex exponential)
    # Reuses CPM_LUT_1024 (no additional memory cost)
    carrier_phasor = CPM_LUT_1024[lut_index + 1]

    # Step 4: Amplitude modulation
    # Multiply carrier by amplitude - this is where price_delta information is encoded
    # Unlike CPM (constant |z|=1.0), AMC has variable envelope |z| = |normalized_ratio|
    complex_signal = normalized_ratio * carrier_phasor

    # Step 5: Update broadcast message with AMC-encoded signal
    update_broadcast_message!(msg, complex_signal, normalization_factor, flag)
end

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

# Main signal processing function - modifies msg and state in-place
# Processing chain: validation → jump guard → winsorize → bar stats → normalize → encoder selection → output
# Encoder selection: HEXAD-16 (discrete 16-phase), CPM (frequency modulation), or AMC (amplitude modulation)
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
    price_delta = msg.price_delta
    flag = FLAG_OK

    # Step 1: Price validation
    if msg.raw_price < min_price || msg.raw_price > max_price
        if state.last_clean !== nothing
            # Hold last valid signal
            flag |= FLAG_HOLDLAST
            normalized_ratio = Float32(0.0)
            if encoder_type == "amc"
                process_tick_amc!(msg, state, normalized_ratio, Float32(1.0), flag)
            elseif encoder_type == "cpm"
                process_tick_cpm!(msg, state, normalized_ratio, Float32(1.0), flag, cpm_modulation_index)
            else
                phase = phase_pos_global(Int64(msg.tick_idx))
                z = apply_hexad16_rotation(normalized_ratio, phase)
                update_broadcast_message!(msg, z, Float32(1.0), flag)
            end
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
        if encoder_type == "amc"
            process_tick_amc!(msg, state, normalized_ratio, Float32(1.0), FLAG_OK)
        elseif encoder_type == "cpm"
            process_tick_cpm!(msg, state, normalized_ratio, Float32(1.0), FLAG_OK, cpm_modulation_index)
        else
            phase = phase_pos_global(Int64(msg.tick_idx))
            z = apply_hexad16_rotation(normalized_ratio, phase)
            update_broadcast_message!(msg, z, Float32(1.0), FLAG_OK)
        end
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

    # Step 10: Encoder selection - HEXAD-16, CPM, AMC, or DERIVATIVE
    if encoder_type == "derivative"
        # DERIVATIVE encoder: Phase space (normalized_dV, acceleration) encoding
        # Uses normalized_ratio (same as other encoders for consistency)
        process_tick_derivative!(msg, state, normalized_ratio, normalization_factor, flag, derivative_imag_scale)
    elseif encoder_type == "amc"
        # AMC encoder: Amplitude-modulated continuous carrier (harmonic elimination)
        process_tick_amc!(msg, state, normalized_ratio, normalization_factor, flag)
    elseif encoder_type == "cpm"
        # CPM encoder: Continuous phase modulation (frequency modulation)
        process_tick_cpm!(msg, state, normalized_ratio, normalization_factor, flag, cpm_modulation_index)
    else
        # HEXAD-16 encoder: Discrete 16-phase rotation (default/backward compatible)
        phase = phase_pos_global(Int64(msg.tick_idx))
        z = apply_hexad16_rotation(normalized_ratio, phase)
        update_broadcast_message!(msg, z, normalization_factor, flag)
    end

    # Update state for next tick
    state.last_clean = msg.raw_price
    state.ticks_accepted += Int64(1)
end

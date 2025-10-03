# src/BroadcastMessage.jl - GPU-Ready Broadcast Message System (MVP)
# Replaces NamedTuple with struct-based architecture for better performance
# MVP Version: GPU-compatible types, no GPU batch processing code

module BroadcastMessageSystem

export BroadcastMessage, create_single_message, validate_message

# =============================================================================
# CORE MESSAGE STRUCTURE (GPU-COMPATIBLE TYPES)
# =============================================================================

"""
High-performance broadcast message for ComplexBiquadGA pipeline.

GPU-Compatible Design:
- All numerical fields use GPU-compatible types (Int32, Float32, ComplexF32)
- String fields remain on CPU for efficiency
- Ready for future StructArray batch operations

Fields:
- tick_index: Sequential tick number (Int64 for large datasets)
- timestamp: Tick timestamp from source data (String, CPU-only)
- raw_price: Original price in ticks from VolumeExpansion (Int32, GPU-ready)
- price_delta: Price change in ticks (Int32, GPU-ready)
- normalization_factor: AGC scale factor from TickHotLoopF32 (Float32, GPU-ready)
- complex_signal: Processed complex signal z (ComplexF32, GPU-ready)
- processing_flags: Processing status flags (UInt8, GPU-ready)
- config_snapshot: Configuration name (String, CPU-only)
- agc_envelope: AGC envelope value (Float32, GPU-ready)
- lock_quality: PLL lock quality estimate [0,1] (Float32, GPU-ready)
- frequency_estimate: Dominant frequency estimate (Float32, GPU-ready)
"""
struct BroadcastMessage
    # Core pipeline data
    tick_index::Int64
    timestamp::String

    # Price data block (GPU-compatible layout)
    raw_price::Int32
    price_delta::Int32
    normalization_factor::Float32

    # Processed signal
    complex_signal::ComplexF32
    processing_flags::UInt8

    # System metadata
    config_snapshot::String

    # Enhanced analytics
    agc_envelope::Float32
    lock_quality::Float32
    frequency_estimate::Float32

    # Validation constructor
    function BroadcastMessage(tick_index::Int64, timestamp::String,
                             raw_price::Int32, price_delta::Int32,
                             normalization_factor::Float32,
                             complex_signal::ComplexF32, processing_flags::UInt8,
                             config_snapshot::String, agc_envelope::Float32,
                             lock_quality::Float32, frequency_estimate::Float32)

        # Input validation
        @assert tick_index > 0 "tick_index must be positive"
        @assert !isempty(timestamp) "timestamp cannot be empty"
        @assert 10000 <= raw_price <= 50000 "raw_price out of reasonable range: $raw_price"
        @assert abs(price_delta) < 1000 "price_delta seems unreasonable: $price_delta"
        @assert normalization_factor > Float32(0.0) "normalization_factor must be positive: $normalization_factor"
        @assert isfinite(real(complex_signal)) && isfinite(imag(complex_signal)) "complex_signal must be finite"
        @assert !isempty(config_snapshot) "config_snapshot cannot be empty"
        @assert Float32(0.0) <= agc_envelope <= Float32(1000.0) "agc_envelope out of range: $agc_envelope"
        @assert Float32(0.0) <= lock_quality <= Float32(1.0) "lock_quality must be in [0,1]: $lock_quality"
        @assert isfinite(frequency_estimate) "frequency_estimate must be finite"

        new(tick_index, timestamp, raw_price, price_delta, normalization_factor,
            complex_signal, processing_flags, config_snapshot, agc_envelope,
            lock_quality, frequency_estimate)
    end
end

# =============================================================================
# CONSTRUCTOR HELPERS
# =============================================================================

"""
Create single broadcast message with defaults for optional analytics fields
"""
function create_single_message(tick_index::Int64, timestamp::String,
                              raw_price::Int32, price_delta::Int32,
                              normalization_factor::Float32,
                              complex_signal::ComplexF32, processing_flags::UInt8,
                              config_snapshot::String;
                              agc_envelope::Float32 = Float32(1.0),
                              lock_quality::Float32 = Float32(0.0),
                              frequency_estimate::Float32 = Float32(0.0))

    return BroadcastMessage(tick_index, timestamp, raw_price, price_delta,
                           normalization_factor, complex_signal, processing_flags,
                           config_snapshot, agc_envelope, lock_quality, frequency_estimate)
end

# =============================================================================
# VALIDATION
# =============================================================================

"""
Validate message integrity
"""
function validate_message(msg::BroadcastMessage)::Bool
    try
        return (msg.tick_index > 0 &&
                !isempty(msg.timestamp) &&
                10000 <= msg.raw_price <= 50000 &&
                abs(msg.price_delta) < 10000 &&
                msg.normalization_factor > Float32(0.0) &&
                isfinite(real(msg.complex_signal)) &&
                isfinite(imag(msg.complex_signal)) &&
                !isempty(msg.config_snapshot) &&
                Float32(0.0) <= msg.agc_envelope <= Float32(10000.0) &&
                Float32(0.0) <= msg.lock_quality <= Float32(1.0) &&
                isfinite(msg.frequency_estimate))
    catch
        return false
    end
end

end # module BroadcastMessageSystem

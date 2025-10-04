# src/BroadcastMessage.jl - GPU-Compatible Tick Data Message
# Design Specification v2.4 Implementation
# MUTABLE struct for in-place updates, all primitive types for GPU compatibility

"""
BroadcastMessage - GPU-compatible tick data message

MUTABLE for in-place updates by TickHotLoopF32
All fields are primitive types for GPU compatibility

Fields populated by VolumeExpansion:
- tick_idx: Sequential tick index (Int32)
- timestamp: Encoded timestamp (Int64, using ASCII character codes)
- raw_price: Original last trade price (Int32)
- price_delta: Price change from previous tick (Int32)

Fields updated by TickHotLoopF32 (in-place):
- normalization: Normalization factor applied (Float32)
- complex_signal: QUAD-4 rotated complex signal (ComplexF32)
- status_flag: Processing status flags (UInt8)

GPU Compatibility:
- All fields are primitive types (Int32, Int64, Float32, ComplexF32, UInt8)
- No String types (timestamp encoded as Int64)
- Struct size: 32 bytes (cache-efficient)
- Can be passed directly to CUDA kernels
"""
mutable struct BroadcastMessage
    tick_idx::Int32
    timestamp::Int64
    raw_price::Int32
    price_delta::Int32
    normalization::Float32
    complex_signal::ComplexF32
    status_flag::UInt8
end

# Status flag constants
const FLAG_OK = UInt8(0x00)           # No issues
const FLAG_MALFORMED = UInt8(0x01)    # Original record was malformed
const FLAG_HOLDLAST = UInt8(0x02)     # Price held from previous
const FLAG_CLIPPED = UInt8(0x04)      # Value was clipped/winsorized
const FLAG_AGC_LIMIT = UInt8(0x08)    # AGC hit limit

"""
    create_broadcast_message(tick_idx, timestamp, raw_price, price_delta)

Create BroadcastMessage with placeholders for TickHotLoopF32 fields.
Called by VolumeExpansion to create pre-populated messages.

# Arguments
- `tick_idx::Int32`: Sequential tick index
- `timestamp::Int64`: Encoded timestamp (ASCII → Int64)
- `raw_price::Int32`: Original last trade price
- `price_delta::Int32`: Price change from previous tick

# Returns
- `BroadcastMessage` with signal processing fields initialized to placeholders
"""
function create_broadcast_message(
    tick_idx::Int32,
    timestamp::Int64,
    raw_price::Int32,
    price_delta::Int32
)::BroadcastMessage
    return BroadcastMessage(
        tick_idx,
        timestamp,
        raw_price,
        price_delta,
        Float32(1.0),      # Placeholder normalization
        ComplexF32(0, 0),  # Placeholder complex_signal
        FLAG_OK            # Placeholder status_flag
    )
end

"""
    update_broadcast_message!(msg, complex_signal, normalization, status_flag)

Update BroadcastMessage fields in-place (called by TickHotLoopF32).
Fast in-place update with NO ALLOCATION overhead.

# Arguments
- `msg::BroadcastMessage`: Message to update (modified in-place)
- `complex_signal::ComplexF32`: Processed I/Q signal
- `normalization::Float32`: Normalization factor applied
- `status_flag::UInt8`: Processing status byte
"""
function update_broadcast_message!(
    msg::BroadcastMessage,
    complex_signal::ComplexF32,
    normalization::Float32,
    status_flag::UInt8
)
    msg.complex_signal = complex_signal
    msg.normalization = normalization
    msg.status_flag = status_flag
end

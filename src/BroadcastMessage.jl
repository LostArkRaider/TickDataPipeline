# src/BroadcastMessage.jl - GPU-Compatible Tick Data Message
# Design Specification v2.4 Implementation
# MUTABLE struct for in-place updates, all primitive types for GPU compatibility

"""
BroadcastMessage - Tick and bar data message

MUTABLE for in-place updates by TickHotLoopF32 and BarProcessor
Tick-level fields are primitive types; bar-level fields use Union{T, Nothing}

Fields populated by VolumeExpansion:
- tick_idx: Sequential tick index (Int32)
- timestamp: Encoded timestamp (Int64, using ASCII character codes)
- raw_price: Original last trade price (Int32)
- price_delta: Price change from previous tick (Int32)

Fields updated by TickHotLoopF32 (in-place):
- normalization: Normalization factor applied (Float32)
- complex_signal: QUAD-4 rotated complex signal (ComplexF32)
- status_flag: Processing status flags (UInt8)

Fields updated by BarProcessor (in-place, only on bar completion):
- bar_idx: Bar sequence number (1, 2, 3, ...)
- bar_ticks: Ticks per bar (from config)
- bar_volume: Same as bar_ticks (1 contract/tick)
- bar_open_raw: First tick raw_price in bar
- bar_high_raw: Max raw_price in bar
- bar_low_raw: Min raw_price in bar
- bar_close_raw: Last tick raw_price in bar
- bar_average_raw: avg(high, low, close)
- bar_price_delta: average_raw - prev_average_raw
- bar_complex_signal: Derivative encoded bar signal
- bar_normalization: Bar normalization factor
- bar_flags: Processing flags for bar
- bar_end_timestamp: Timestamp of final tick

Message Flow:
- 143 out of 144 ticks: bar fields = nothing (pass-through)
- 1 out of 144 ticks: bar fields populated (bar completion)
"""
mutable struct BroadcastMessage
    # Tick-level fields (always present)
    tick_idx::Int32
    timestamp::Int64
    raw_price::Int32
    price_delta::Int32
    normalization::Float32
    complex_signal::ComplexF32
    status_flag::UInt8

    # Bar-level fields (only populated at bar completion)
    bar_idx::Union{Int64, Nothing}
    bar_ticks::Union{Int32, Nothing}
    bar_volume::Union{Int32, Nothing}
    bar_open_raw::Union{Int32, Nothing}
    bar_high_raw::Union{Int32, Nothing}
    bar_low_raw::Union{Int32, Nothing}
    bar_close_raw::Union{Int32, Nothing}
    bar_average_raw::Union{Int32, Nothing}
    bar_price_delta::Union{Int32, Nothing}
    bar_complex_signal::Union{ComplexF32, Nothing}
    bar_normalization::Union{Float32, Nothing}
    bar_flags::Union{UInt8, Nothing}
    bar_end_timestamp::Union{UInt64, Nothing}
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
- `BroadcastMessage` with signal processing fields initialized to placeholders,
  bar fields initialized to nothing
"""
function create_broadcast_message(
    tick_idx::Int32,
    timestamp::Int64,
    raw_price::Int32,
    price_delta::Int32
)::BroadcastMessage
    return BroadcastMessage(
        # Tick-level fields
        tick_idx,
        timestamp,
        raw_price,
        price_delta,
        Float32(1.0),      # Placeholder normalization
        ComplexF32(0, 0),  # Placeholder complex_signal
        FLAG_OK,           # Placeholder status_flag
        # Bar-level fields (all nothing initially)
        nothing,           # bar_idx
        nothing,           # bar_ticks
        nothing,           # bar_volume
        nothing,           # bar_open_raw
        nothing,           # bar_high_raw
        nothing,           # bar_low_raw
        nothing,           # bar_close_raw
        nothing,           # bar_average_raw
        nothing,           # bar_price_delta
        nothing,           # bar_complex_signal
        nothing,           # bar_normalization
        nothing,           # bar_flags
        nothing            # bar_end_timestamp
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

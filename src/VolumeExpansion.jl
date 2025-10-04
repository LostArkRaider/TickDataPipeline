# src/VolumeExpansion.jl - Volume Expansion and Timestamp Encoding
# Design Specification v2.4 Implementation
# Outputs Channel{BroadcastMessage} with pre-populated fields

using Dates

# Note: Using parent module's BroadcastMessage (not exported from this module)
# This module is included in TickDataPipeline, so BroadcastMessage is available

"""
    encode_timestamp_to_int64(timestamp_str::String)::Int64

Encode ASCII timestamp to Int64 using 8-bit character codes.

Format: "yyyymmdd hhmmss uuuuuuu" (23 characters)
Encoding: Pack first 8 characters into Int64 (each char = 8 bits)

# Examples
```julia
encoded = encode_timestamp_to_int64("20250319 070000 0520000")
# Returns Int64 with packed character codes
```
"""
function encode_timestamp_to_int64(timestamp_str::String)::Int64
    if isempty(timestamp_str)
        return Int64(0)
    end

    # Pack up to 8 characters into Int64
    result = Int64(0)
    for i in 1:min(8, length(timestamp_str))
        char_code = Int64(codepoint(timestamp_str[i]))
        result = (result << 8) | (char_code & 0xFF)
    end

    return result
end

"""
    decode_timestamp_from_int64(encoded::Int64)::String

Decode Int64 back to timestamp string (for debugging/validation).

Extracts first 8 characters from packed Int64.
"""
function decode_timestamp_from_int64(encoded::Int64)::String
    chars = Char[]
    temp = encoded

    for _ in 1:8
        char_code = temp & 0xFF
        if char_code != 0
            pushfirst!(chars, Char(char_code))
        end
        temp >>= 8
    end

    return String(chars)
end

"""
    parse_tick_line(line::String)::Union{Tuple{String,Int32,Int32,Int32,Int32}, Nothing}

Parse tick line and extract fields.

YM Format: "20250319 070009 8320000;41961;41961;41963;1"
Fields: timestamp;bid;ask;last;volume

# Returns
- Tuple: (timestamp_str, bid, ask, last, volume) on success
- Nothing: if malformed
"""
function parse_tick_line(line::String)::Union{Tuple{String,Int32,Int32,Int32,Int32}, Nothing}
    parts = split(line, ';')

    if length(parts) != 5
        return nothing
    end

    try
        timestamp_str = strip(parts[1])
        bid = parse(Int32, strip(parts[2]))
        ask = parse(Int32, strip(parts[3]))
        last = parse(Int32, strip(parts[4]))
        volume = parse(Int32, strip(parts[5]))

        return (timestamp_str, bid, ask, last, volume)
    catch
        return nothing
    end
end

"""
    stream_expanded_ticks(file_path::String, delay_ms::Float64 = 0.0)::Channel{BroadcastMessage}

Stream expanded ticks from file with pre-populated BroadcastMessages.

Core functionality:
1. Read tick file line by line
2. Parse each line to extract fields
3. Expand volume (replicate ticks if volume > 1)
4. Calculate price_delta from consecutive ticks
5. Encode timestamp to Int64
6. Create BroadcastMessage for each tick
7. Apply flow control delay
8. Stream via Channel{BroadcastMessage}

# Arguments
- `file_path::String`: Path to tick data file
- `delay_ms::Float64`: Delay in milliseconds between ticks (default: 0.0)

# Returns
- `Channel{BroadcastMessage}`: Stream of pre-populated messages

# Example
```julia
channel = stream_expanded_ticks("data/raw/YM 06-25.Last.txt", 1.0)
for msg in channel
    println("Tick \$(msg.tick_idx): price=\$(msg.raw_price), Δ=\$(msg.price_delta)")
end
```
"""
function stream_expanded_ticks(
    file_path::String,
    delay_ms::Float64 = 0.0
)::Channel{BroadcastMessage}

    return Channel{BroadcastMessage}() do channel
        if !isfile(file_path)
            @warn "Tick file not found: $file_path"
            return
        end

        tick_idx = Int32(0)
        previous_last = Int32(0)
        first_tick = true

        open(file_path, "r") do file
            for line in eachline(file)
                # Skip empty lines
                if isempty(strip(line))
                    continue
                end

                # Parse tick line
                parsed = parse_tick_line(line)
                if parsed === nothing
                    continue  # Skip malformed
                end

                (timestamp_str, bid, ask, last, volume) = parsed

                # Volume expansion: create multiple messages for volume > 1
                for replica_idx in 1:volume
                    tick_idx += Int32(1)

                    # Encode timestamp
                    timestamp_encoded = encode_timestamp_to_int64(timestamp_str)

                    # Calculate price delta
                    # First replica: normal price delta from previous tick
                    # Subsequent replicas: zero delta (same price as first replica)
                    if first_tick
                        price_delta = Int32(0)
                        first_tick = false
                    elseif replica_idx == 1
                        # First replica of this volume group: delta from previous tick
                        price_delta = last - previous_last
                    else
                        # Subsequent replicas: zero delta (same price)
                        price_delta = Int32(0)
                    end

                    # Create pre-populated BroadcastMessage
                    msg = create_broadcast_message(
                        tick_idx,
                        timestamp_encoded,
                        last,  # raw_price
                        price_delta
                    )

                    # Apply flow control delay
                    if delay_ms > Float64(0.0)
                        sleep(delay_ms / 1000.0)
                    end

                    # Send to channel
                    put!(channel, msg)
                end

                # Update previous_last for next iteration
                previous_last = last
            end
        end
    end
end

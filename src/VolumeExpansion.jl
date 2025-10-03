# src/VolumeExpansion.jl - Simple String Processing for Tick Volume Expansion
# Session 1 REDESIGNED: Focus on string manipulation, not complex parsing
# Replaces over-engineered parsing infrastructure with simple volume expansion

module VolumeExpansion

using Dates

export expand_volume_record, process_tick_line_simple, replicate_tick_string,
       extract_volume_from_ym_line, extract_raw_price_from_ym_line,
       create_expanded_tick_strings, stream_expanded_ticks

# =============================================================================
# SIMPLE STRING PROCESSING - NO COMPLEX PARSING
# =============================================================================

"""
Extract volume from YM format line without full parsing
YM Format: "20250319 070009 8320000;41961;41961;41963;1"
Returns volume as Int32 (GPU-compatible)
"""
function extract_volume_from_ym_line(line::String)::Int32
    # Simple string split to get volume (last field)
    parts = split(line, ';')
    if length(parts) != 5
        return Int32(1)  # Default volume if malformed
    end

    try
        volume = parse(Int32, strip(parts[5]))  # GPU-compatible: Int32
        return max(volume, Int32(1))  # Ensure positive volume
    catch
        return Int32(1)  # Default if parse fails
    end
end

"""
Extract raw price (last price) from YM format line
YM Format: "20250319 070009 8320000;41961;41961;41963;1"
Returns the last price (4th field) as Int32 (GPU-compatible)
"""
function extract_raw_price_from_ym_line(line::String)::Int32
    # Simple string split to get last price (4th field)
    parts = split(line, ';')
    if length(parts) != 5
        return Int32(41000)  # Default YM price if malformed
    end

    try
        raw_price = parse(Int32, strip(parts[4]))  # 4th field is "last" price
        return raw_price
    catch
        return Int32(41000)  # Default if parse fails
    end
end

"""
Replicate YM format tick string for volume expansion
CORE LOGIC: Original record keeps price_change, replicas have price_change = 0

Input: "20250319 070009 8320000;41961;41961;41963;1"
If volume=3, returns:
- Original: "20250319 070009 8320000;41961;41961;41963;1" (volume=1, keeps price change)
- Replica 1: "20250319 070009 8320000;41961;41961;41963;1" (volume=1, price_change=0)  
- Replica 2: "20250319 070009 8320000;41961;41961;41963;1" (volume=1, price_change=0)
"""
function replicate_tick_string(original_line::String, total_volume::Int32)::Vector{String}
    if total_volume <= Int32(1)
        return [original_line]  # No expansion needed
    end
    
    # Parse original line to extract components
    parts = split(original_line, ';')
    if length(parts) != 5
        return [original_line]  # Return original if malformed
    end
    
    # Extract price information to calculate zero-change replicas
    try
        timestamp = strip(parts[1])
        bid = strip(parts[2])
        ask = strip(parts[3])
        last = strip(parts[4])
        # Ignore original volume - all replicas will have volume=1
        
        # Create replica strings
        replica_strings = Vector{String}(undef, total_volume)
        
        # First record: original with volume=1 (keeps price change)
        replica_strings[1] = "$(timestamp);$(bid);$(ask);$(last);1"
        
        # Remaining records: price_change = 0, volume = 1
        # For YM format, we need to adjust the last price to create zero price change
        # But since TickHotLoopF32 calculates price_change from consecutive records,
        # we keep the same last price to naturally create price_change = 0
        for i in Int32(2):total_volume
            replica_strings[i] = "$(timestamp);$(bid);$(ask);$(last);1"
        end
        
        return replica_strings
        
    catch e
        # If parsing fails, return original
        return [original_line]
    end
end

"""
Process single line with volume expansion
Returns vector of YM-format strings ready for TickHotLoopF32
"""
function expand_volume_record(line::String)::Vector{String}
    # Quick volume check
    volume = extract_volume_from_ym_line(line)
    
    if volume <= Int32(1)
        return [line]  # No expansion needed
    end
    
    return replicate_tick_string(line, volume)
end

"""
Simple tick line processing without complex type conversion
Just handles volume expansion and basic validation
"""
function process_tick_line_simple(line::String)::Vector{String}
    # Skip empty lines
    if isempty(strip(line))
        return String[]
    end
    
    # Basic format validation (should have 4 semicolons for 5 fields)
    if count(';', line) != 4
        return String[]  # Skip malformed lines
    end
    
    # Expand volume if needed
    return expand_volume_record(line)
end

"""
Create expanded tick strings from file reading (streaming interface)
Reads ASCII file line by line and returns expanded strings ready for TickHotLoopF32
"""
function create_expanded_tick_strings(file_path::String)::Channel{String}
    return Channel{String}() do channel
        if !isfile(file_path)
            @warn "Tick file not found: $file_path"
            return
        end
        
        line_count = Int32(0)  # GPU-compatible
        expanded_count = Int32(0)  # GPU-compatible
        
        open(file_path, "r") do file
            for line in eachline(file)
                line_count += Int32(1)
                
                # Process line and expand volume
                expanded_lines = process_tick_line_simple(line)
                
                # Send all expanded lines to channel
                for expanded_line in expanded_lines
                    put!(channel, expanded_line)
                    expanded_count += Int32(1)
                end
            end
        end
        
        println("Volume expansion: $line_count original lines → $expanded_count expanded lines")
    end
end

"""
Compatibility alias for stream_expanded_ticks
Matches the function name expected by EndToEndPipeline
Implements tick gating with artificial delays from flow_config
"""
function stream_expanded_ticks(file_path::String, flow_config)
    println("🔍 VolumeExpansion.stream_expanded_ticks called with file: $file_path")
    println("🔍 VolumeExpansion module - NOT FlowControlConfig module")
    
    # Add error handling and debugging
    if !isfile(file_path)
        error("File not found in stream_expanded_ticks: $file_path")
    end
    
    println("🔍 DEBUG: File exists, implementing tick gating with flow control...")
    
    # Extract delay configuration from flow_config
    delay_ms = if flow_config !== nothing && hasfield(typeof(flow_config), :fixed_delay_ms)
        Float64(flow_config.fixed_delay_ms)
    else
        0.0  # No delay by default for maximum performance
    end
    
    println("🔍 DEBUG: Tick gating delay: $(delay_ms)ms")

    return Channel{Tuple{String, Int32}}() do channel
        if !isfile(file_path)
            @warn "Tick file not found: $file_path"
            return
        end

        line_count = Int32(0)
        expanded_count = Int32(0)

        open(file_path, "r") do file
            for line in eachline(file)
                line_count += Int32(1)

                # DEBUG: Show first few lines being read
                if line_count <= 5
                    println("🔍 VolumeExpansion DEBUG: Line $line_count: '$(line[1:min(50,end)])...'")
                end

                # Process line and expand volume
                expanded_lines = process_tick_line_simple(line)

                # Send all expanded lines to channel with tick gating
                # Extract raw_price from EACH expanded line for data integrity
                for expanded_line in expanded_lines
                    # Apply tick gating delay BEFORE sending each tick
                    if delay_ms > 0.0
                        sleep(delay_ms / 1000.0)  # Convert ms to seconds
                    end

                    # Extract raw price from the expanded line itself
                    raw_price = extract_raw_price_from_ym_line(expanded_line)
                    put!(channel, (expanded_line, raw_price))  # Emit tuple with raw price
                    expanded_count += Int32(1)
                end
            end
        end
        
        println("Volume expansion with tick gating: $line_count original lines → $expanded_count expanded lines ($(delay_ms)ms delay per tick)")
    end
end

end # module VolumeExpansion
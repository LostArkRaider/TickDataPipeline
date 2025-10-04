# TickDataPipeline.jl - Claude Code Implementation Plan

**Package**: TickDataPipeline.jl  
**Version**: v0.1.0 (Development)  
**Reference Document**: Julia Tick Processing Pipeline Package - Design Specification

---

## Implementation Strategy

This plan divides the implementation into **8 focused Claude Code sessions**, each with clear objectives, deliverables, and test requirements. Sessions are ordered to build foundation-first, enabling incremental testing and validation.

### Session Dependencies

```
Session 1 (Foundation) → Session 2 (Data Prep) → Session 3 (Hot Loop)
                              ↓                         ↓
                         Session 4 (Broadcast) ← ─────────
                              ↓
                         Session 5 (Config) → Session 6 (Orchestration)
                              ↓                    ↓
                         Session 7 (API)  ←────────
                              ↓
                         Session 8 (Testing & Docs)
```

---

## Session 1: Project Foundation & Core Types

**Duration**: 45-60 minutes  
**Dependencies**: None  
**Priority**: Critical (Foundation)

### Objectives
1. Create Julia package structure
2. Define core GPU-compatible types
3. Implement BroadcastMessage struct
4. Set up basic testing infrastructure

### Deliverables

#### File: `Project.toml`
```toml
name = "TickDataPipeline"
uuid = "..." # Generate new UUID
authors = ["Your Name"]
version = "0.1.0"

[deps]
Dates = "ade2ca70-3891-5945-98fb-dc099432e06a"

[compat]
julia = "1.9"

[extras]
Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[targets]
test = ["Test"]
```

#### File: `src/TickDataPipeline.jl`
```julia
module TickDataPipeline

using Dates

# Core types
include("BroadcastMessage.jl")

# Will be added in later sessions
# include("VolumeExpansion.jl")
# include("FlowControlConfig.jl")
# include("TickHotLoopF32.jl")
# include("TripleSplitSystem.jl")
# include("PipelineConfig.jl")
# include("PipelineOrchestrator.jl")
# include("PipelineAPI.jl")

# Exports
export BroadcastMessage

end # module
```

#### File: `src/BroadcastMessage.jl`
```julia
"""
BroadcastMessage - GPU-compatible tick data message

MUTABLE for in-place updates by TickHotLoopF32
All fields are primitive types for GPU compatibility

Fields populated by VolumeExpansion:
- tick_idx, timestamp, raw_price, price_delta

Fields updated by TickHotLoopF32:
- normalization, complex_signal, status_flag
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
const FLAG_OK = UInt8(0x00)
const FLAG_MALFORMED = UInt8(0x01)
const FLAG_HOLDLAST = UInt8(0x02)
const FLAG_CLIPPED = UInt8(0x04)
const FLAG_AGC_LIMIT = UInt8(0x08)

"""
Create BroadcastMessage with placeholders for TickHotLoopF32 fields
Called by VolumeExpansion
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
Update BroadcastMessage fields in-place (called by TickHotLoopF32)
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
```

#### File: `test/runtests.jl`
```julia
using Test
using TickDataPipeline

@testset "TickDataPipeline.jl" begin
    include("test_broadcast_message.jl")
end
```

#### File: `test/test_broadcast_message.jl`
```julia
using Test
using TickDataPipeline

@testset begin #BroadcastMessage
    @testset begin #Creation
        msg = create_broadcast_message(
            Int32(1),
            Int64(12345),
            Int32(41971),
            Int32(10)
        )
        
        @test msg.tick_idx == Int32(1)
        @test msg.timestamp == Int64(12345)
        @test msg.raw_price == Int32(41971)
        @test msg.price_delta == Int32(10)
        @test msg.normalization == Float32(1.0)
        @test msg.complex_signal == ComplexF32(0, 0)
        @test msg.status_flag == FLAG_OK
    end
    
    @testset begin #In-place Update
        msg = create_broadcast_message(Int32(1), Int64(1), Int32(100), Int32(0))
        
        update_broadcast_message!(
            msg,
            ComplexF32(0.707, 0.707),
            Float32(2.5),
            FLAG_CLIPPED
        )
        
        @test msg.complex_signal == ComplexF32(0.707, 0.707)
        @test msg.normalization == Float32(2.5)
        @test msg.status_flag == FLAG_CLIPPED
    end
    
    @testset begin #GPU Compatibility
        # Verify all fields are primitive types
        msg = create_broadcast_message(Int32(1), Int64(1), Int32(100), Int32(0))
        
        @test isbitstype(typeof(msg.tick_idx))
        @test isbitstype(typeof(msg.timestamp))
        @test isbitstype(typeof(msg.raw_price))
        @test isbitstype(typeof(msg.price_delta))
        @test isbitstype(typeof(msg.normalization))
        @test isbitstype(typeof(msg.complex_signal))
        @test isbitstype(typeof(msg.status_flag))
        
        # Verify struct size
        @test sizeof(msg) == 32  # 4+8+4+4+4+8+1 = 33, aligned to 32
    end
end
```

### Success Criteria
- [ ] Package structure created
- [ ] BroadcastMessage fully implemented
- [ ] All tests pass
- [ ] `using TickDataPipeline` works
- [ ] GPU compatibility verified (all primitive types)

---

## Session 2: VolumeExpansion & Timestamp Encoding

**Duration**: 60-90 minutes  
**Dependencies**: Session 1  
**Priority**: Critical (Data Preparation)

### Objectives
1. Implement timestamp encoding (ASCII → Int64)
2. Implement volume expansion logic
3. Create Channel{BroadcastMessage} streaming interface
4. Parse tick data and extract raw_price
5. Calculate price_delta

### Deliverables

#### File: `src/VolumeExpansion.jl`
```julia
module VolumeExpansion

export stream_expanded_ticks, encode_timestamp_to_int64, decode_timestamp_from_int64

using ..TickDataPipeline: BroadcastMessage, create_broadcast_message, FLAG_MALFORMED

"""
Encode ASCII timestamp to Int64 using 8-bit character codes
Format: "yyyymmdd hhmmss uuuuuuu" (23 characters)
Encoding: Pack characters into Int64 (can hold 8 chars, use multiple passes)
"""
function encode_timestamp_to_int64(timestamp_str::String)::Int64
    # Implementation: Use character codes, 8 bits per char
    # For 23-char timestamp, use hash or compression scheme
    # Simplest: Use first 8 chars for uniqueness
    # More complex: Use all chars with bit packing
    
    if length(timestamp_str) < 8
        return Int64(0)
    end
    
    # Pack first 8 characters into Int64
    result = Int64(0)
    for i in 1:min(8, length(timestamp_str))
        char_code = Int64(codepoint(timestamp_str[i]))
        result = (result << 8) | (char_code & 0xFF)
    end
    
    return result
end

"""
Decode Int64 back to timestamp string (for debugging/validation)
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
Extract volume from YM tick line
Format: "yyyymmdd hhmmss uuuuuuu;bid;ask;last;volume"
"""
function extract_volume_from_line(line::String)::Int32
    parts = split(line, ';')
    if length(parts) != 5
        return Int32(1)
    end
    
    try
        volume = parse(Int32, strip(parts[5]))
        return max(volume, Int32(1))
    catch
        return Int32(1)
    end
end

"""
Parse tick line and extract fields
Returns: (timestamp_str, bid, ask, last, volume) or nothing if malformed
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
Stream expanded ticks from file with pre-populated BroadcastMessages
Returns: Channel{BroadcastMessage}
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
                for _ in 1:volume
                    tick_idx += 1
                    
                    # Encode timestamp
                    timestamp_encoded = encode_timestamp_to_int64(timestamp_str)
                    
                    # Calculate price delta
                    price_delta = first_tick ? Int32(0) : last - previous_last
                    first_tick = false
                    
                    # Create pre-populated BroadcastMessage
                    msg = create_broadcast_message(
                        tick_idx,
                        timestamp_encoded,
                        last,  # raw_price
                        price_delta
                    )
                    
                    # Apply flow control delay
                    if delay_ms > 0.0
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

end # module
```

#### File: `test/test_volume_expansion.jl`
```julia
using Test
using TickDataPipeline
using TickDataPipeline.VolumeExpansion

@testset begin #VolumeExpansion
    @testset begin #Timestamp Encoding
        timestamp = "20250319 070000 0520000"
        encoded = encode_timestamp_to_int64(timestamp)
        
        @test encoded != Int64(0)
        @test typeof(encoded) == Int64
        
        # Test round-trip (first 8 chars)
        decoded = decode_timestamp_from_int64(encoded)
        @test decoded == timestamp[1:8]
    end
    
    @testset begin #Volume Extraction
        line = "20250319 070000 0520000;41971;41970;41971;3"
        volume = extract_volume_from_line(line)
        @test volume == Int32(3)
        
        # Malformed line
        bad_line = "invalid"
        volume = extract_volume_from_line(bad_line)
        @test volume == Int32(1)
    end
    
    @testset begin #Tick Parsing
        line = "20250319 070000 0520000;41971;41970;41971;1"
        result = parse_tick_line(line)
        
        @test result !== nothing
        (ts, bid, ask, last, vol) = result
        @test ts == "20250319 070000 0520000"
        @test bid == Int32(41970)
        @test ask == Int32(41971)
        @test last == Int32(41971)
        @test vol == Int32(1)
    end
    
    @testset begin #Stream Expanded Ticks
        # Create test file
        test_file = "test_ticks.txt"
        open(test_file, "w") do f
            println(f, "20250319 070000 0520000;41971;41970;41971;1")
            println(f, "20250319 070001 0520000;41972;41971;41972;2")
            println(f, "20250319 070002 0520000;41973;41972;41973;1")
        end
        
        try
            messages = BroadcastMessage[]
            channel = stream_expanded_ticks(test_file, 0.0)
            
            for msg in channel
                push!(messages, msg)
            end
            
            # Should have 4 messages (1 + 2 + 1)
            @test length(messages) == 4
            
            # Check first message
            @test messages[1].tick_idx == Int32(1)
            @test messages[1].raw_price == Int32(41971)
            @test messages[1].price_delta == Int32(0)  # First tick
            
            # Check second message (from volume expansion)
            @test messages[2].tick_idx == Int32(2)
            @test messages[2].raw_price == Int32(41972)
            @test messages[2].price_delta == Int32(1)
            
            # Check fourth message
            @test messages[4].tick_idx == Int32(4)
            @test messages[4].raw_price == Int32(41973)
            
        finally
            rm(test_file, force=true)
        end
    end
end
```

### Success Criteria
- [ ] Timestamp encoding/decoding implemented
- [ ] Volume expansion works correctly
- [ ] Channel{BroadcastMessage} streams data
- [ ] Price delta calculation correct
- [ ] All tests pass
- [ ] Handles malformed records gracefully

---

## Session 3: TickHotLoopF32 - Signal Processing

**Duration**: 90-120 minutes  
**Dependencies**: Sessions 1, 2  
**Priority**: Critical (Hot Loop Performance)

### Objectives
1. Implement normalization (EMA-based)
2. Implement winsorization (outlier clipping)
3. Implement AGC (Automatic Gain Control)
4. Implement QUAD-4 rotation
5. Update BroadcastMessage in-place
6. **ZERO conditional branches** in hot loop

### Deliverables

#### File: `src/TickHotLoopF32.jl`
```julia
module TickHotLoopF32

export TickHotLoopState, create_tickhotloop_state, process_tick_signal!

using ..TickDataPipeline: BroadcastMessage, update_broadcast_message!
using ..TickDataPipeline: FLAG_OK, FLAG_HOLDLAST, FLAG_CLIPPED, FLAG_AGC_LIMIT

"""
Stateful processing for TickHotLoopF32
Tracks EMA values and AGC state across ticks
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
Create initial TickHotLoopState
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
Apply QUAD-4 phase rotation
phase_pos: 0, 1, 2, 3 (repeating)
"""
function apply_quad4_rotation(normalized_value::Float32, phase_pos::Int32)::ComplexF32
    # QUAD-4 rotation: 0°, 90°, 180°, 270°
    # pos 0: (1, 0)   → multiply by 1
    # pos 1: (0, 1)   → multiply by i
    # pos 2: (-1, 0)  → multiply by -1
    # pos 3: (0, -1)  → multiply by -i
    
    phase = phase_pos % Int32(4)
    
    if phase == Int32(0)
        return ComplexF32(normalized_value, 0.0f0)
    elseif phase == Int32(1)
        return ComplexF32(0.0f0, normalized_value)
    elseif phase == Int32(2)
        return ComplexF32(-normalized_value, 0.0f0)
    else  # phase == 3
        return ComplexF32(0.0f0, -normalized_value)
    end
end

"""
Global phase position (cycles through 0,1,2,3)
"""
function phase_pos_global(tick_idx::Int64)::Int32
    return Int32(tick_idx % 4)
end

"""
Process single tick signal (IN-PLACE UPDATE)
PERFORMANCE CRITICAL: No conditional branches for feature enablement

Parameters:
- msg: BroadcastMessage with price_delta already populated
- state: TickHotLoopState for stateful processing
- config: Signal processing parameters

Updates msg.complex_signal, msg.normalization, msg.status_flag IN-PLACE
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
    state.tick_count += 1
    price_delta = msg.price_delta
    flag = FLAG_OK
    
    # Absolute price validation (ALWAYS ENABLED)
    if msg.raw_price < min_price || msg.raw_price > max_price
        if state.last_clean !== nothing
            flag |= FLAG_HOLDLAST
            # Use zero delta, previous signal
            normalized_ratio = Float32(0.0)
            phase = phase_pos_global(state.tick_count)
            z = apply_quad4_rotation(normalized_ratio, phase)
            
            update_broadcast_message!(msg, z, Float32(1.0), flag)
            state.ticks_accepted += 1
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
        phase = phase_pos_global(state.tick_count)
        z = apply_quad4_rotation(normalized_ratio, phase)
        
        update_broadcast_message!(msg, z, Float32(1.0), FLAG_OK)
        state.ticks_accepted += 1
        return
    end
    
    # Get delta
    delta = price_delta
    
    # Hard jump guard (ALWAYS ENABLED)
    if abs(delta) > max_jump
        delta = delta > 0 ? max_jump : -max_jump
        flag |= FLAG_CLIPPED
    end
    
    # Update EMA for normalization (ALWAYS ENABLED)
    abs_delta = abs(delta)
    
    if state.has_delta_ema
        # Update EMA (alpha = 1/16 = 0.0625)
        state.ema_delta = state.ema_delta + (delta - state.ema_delta) >> 4
        dev = abs(delta - state.ema_delta)
        state.ema_delta_dev = state.ema_delta_dev + (dev - state.ema_delta_dev) >> 4
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
    normalization_factor = Float32(agc_scale)
    
    # Winsorization (ALWAYS ENABLED)
    if abs(normalized_ratio) > winsorize_threshold
        normalized_ratio = sign(normalized_ratio) * winsorize_threshold
        flag |= FLAG_CLIPPED
    end
    
    # Apply QUAD-4 rotation (ALWAYS ENABLED)
    phase = phase_pos_global(state.tick_count)
    z = apply_quad4_rotation(normalized_ratio, phase)
    
    # Update message IN-PLACE
    update_broadcast_message!(msg, z, normalization_factor, flag)
    
    # Update state
    state.last_clean = msg.raw_price
    state.ticks_accepted += 1
end

end # module
```

#### File: `test/test_tickhotloopf32.jl`
```julia
using Test
using TickDataPipeline
using TickDataPipeline.TickHotLoopF32

@testset begin #TickHotLoopF32
    @testset begin #State Creation
        state = create_tickhotloop_state()
        @test state.last_clean === nothing
        @test state.has_delta_ema == false
        @test state.tick_count == Int64(0)
    end
    
    @testset begin #QUAD-4 Rotation
        # Phase 0: real axis
        z = apply_quad4_rotation(Float32(1.0), Int32(0))
        @test real(z) ≈ 1.0f0
        @test imag(z) ≈ 0.0f0
        
        # Phase 1: imaginary axis
        z = apply_quad4_rotation(Float32(1.0), Int32(1))
        @test real(z) ≈ 0.0f0
        @test imag(z) ≈ 1.0f0
        
        # Phase 2: negative real axis
        z = apply_quad4_rotation(Float32(1.0), Int32(2))
        @test real(z) ≈ -1.0f0
        @test imag(z) ≈ 0.0f0
        
        # Phase 3: negative imaginary axis
        z = apply_quad4_rotation(Float32(1.0), Int32(3))
        @test real(z) ≈ 0.0f0
        @test imag(z) ≈ -1.0f0
    end
    
    @testset begin #Signal Processing
        state = create_tickhotloop_state()
        
        # Create test message
        msg = create_broadcast_message(
            Int32(1),
            Int64(12345),
            Int32(41971),
            Int32(10)  # price_delta
        )
        
        # Process
        process_tick_signal!(
            msg,
            state,
            Float32(0.0625),  # agc_alpha
            Int32(4),         # agc_min_scale
            Int32(50),        # agc_max_scale
            Float32(3.0),     # winsorize_threshold
            Int32(40000),     # min_price
            Int32(43000),     # max_price
            Int32(50)         # max_jump
        )
        
        # Check that message was updated
        @test msg.complex_signal != ComplexF32(0, 0)
        @test msg.normalization > Float32(0.0)
        @test msg.status_flag >= FLAG_OK
        
        # State should be updated
        @test state.ticks_accepted > 0
        @test state.last_clean !== nothing
    end
    
    @testset begin #No Conditional Branches
        # Verify all features execute regardless of values
        state = create_tickhotloop_state()
        
        # Even with "disabled" values, should process
        msg = create_broadcast_message(Int32(1), Int64(1), Int32(41971), Int32(0))
        
        process_tick_signal!(
            msg,
            state,
            Float32(0.0),     # "Disabled" AGC
            Int32(1),         # Fixed scale
            Int32(1),
            Float32(1000.0),  # "Disabled" winsorization
            Int32(0),
            Int32(100000),
            Int32(10000)
        )
        
        # Should still process successfully
        @test state.ticks_accepted == 1
    end
end
```

### Success Criteria
- [ ] All signal processing features implemented
- [ ] Zero conditional branches for feature enablement
- [ ] In-place message updates work correctly
- [ ] QUAD-4 rotation correct for all phases
- [ ] AGC, normalization, winsorization all function
- [ ] All tests pass
- [ ] Performance verified (no branching overhead)

---

## Session 4: TripleSplitSystem - Channel Broadcasting

**Duration**: 60-90 minutes  
**Dependencies**: Session 1  
**Priority**: Critical (Message Distribution)

### Objectives
1. Implement multi-consumer channel management
2. Implement priority vs. standard consumer handling
3. Implement backpressure and overflow handling
4. Thread-safe broadcasting

### Deliverables

#### File: `src/TripleSplitSystem.jl`
```julia
module TripleSplitSystem

export ConsumerType, TripleSplitManager, create_triple_split_manager
export subscribe_consumer!, broadcast_to_all!, get_consumer_channel

using ..TickDataPipeline: BroadcastMessage

# Consumer types
@enum ConsumerType::Int32 begin
    PRIORITY = Int32(1)
    MONITORING = Int32(2)
    ALERTING = Int32(3)
    ANALYTICS = Int32(4)
end

"""
Consumer channel wrapper
"""
mutable struct ConsumerChannel
    consumer_id::Symbol
    consumer_type::ConsumerType
    channel::Channel{BroadcastMessage}
    buffer_size::Int32
    messages_sent::Int32
    messages_dropped::Int32
end

"""
Triple split manager for multi-consumer broadcasting
"""
mutable struct TripleSplitManager
    # Consumer channels
    priority_channel::Union{ConsumerChannel, Nothing}
    standard_channels::Dict{Symbol, ConsumerChannel}
    
    # Configuration
    enable_backpressure::Bool
    drop_on_overflow::Bool
    
    # Thread safety
    lock::ReentrantLock
    
    # Statistics
    total_broadcasts::Int64
    successful_broadcasts::Int64
    failed_broadcasts::Int64
end

"""
Create triple split manager
"""
function create_triple_split_manager(;
    enable_backpressure::Bool = true,
    drop_on_overflow::Bool = true
)::TripleSplitManager
    return TripleSplitManager(
        nothing,
        Dict{Symbol, ConsumerChannel}(),
        enable_backpressure,
        drop_on_overflow,
        ReentrantLock(),
        Int64(0),
        Int64(0),
        Int64(0)
    )
end

"""
Subscribe consumer to receive broadcasts
"""
function subscribe_consumer!(
    manager::TripleSplitManager,
    consumer_id::Symbol,
    consumer_type::ConsumerType,
    buffer_size::Int32 = Int32(2048)
)::Channel{BroadcastMessage}
    lock(manager.lock) do
        channel = Channel{BroadcastMessage}(buffer_size)
        
        consumer_channel = ConsumerChannel(
            consumer_id,
            consumer_type,
            channel,
            buffer_size,
            Int32(0),
            Int32(0)
        )
        
        if consumer_type == PRIORITY
            if manager.priority_channel !== nothing
                error("Priority consumer already subscribed")
            end
            manager.priority_channel = consumer_channel
        else
            if haskey(manager.standard_channels, consumer_id)
                error("Consumer $consumer_id already subscribed")
            end
            manager.standard_channels[consumer_id] = consumer_channel
        end
        
        return channel
    end
end

"""
Get consumer channel by ID
"""
function get_consumer_channel(
    manager::TripleSplitManager,
    consumer_id::Symbol
)::Union{Channel{BroadcastMessage}, Nothing}
    lock(manager.lock) do
        # Check priority channel
        if manager.priority_channel !== nothing && 
           manager.priority_channel.consumer_id == consumer_id
            return manager.priority_channel.channel
        end
        
        # Check standard channels
        if haskey(manager.standard_channels, consumer_id)
            return manager.standard_channels[consumer_id].channel
        end
        
        return nothing
    end
end

"""
Broadcast message to all consumers
Returns: (total_consumers, successful_deliveries, failed_deliveries)
"""
function broadcast_to_all!(
    manager::TripleSplitManager,
    message::BroadcastMessage
)::Tuple{Int32, Int32, Int32}
    
    total_consumers = Int32(0)
    successful = Int32(0)
    failed = Int32(0)
    
    lock(manager.lock) do
        # Priority consumer (ALWAYS successful, blocking if needed)
        if manager.priority_channel !== nothing
            total_consumers += Int32(1)
            try
                put!(manager.priority_channel.channel, message)
                manager.priority_channel.messages_sent += Int32(1)
                successful += Int32(1)
            catch e
                failed += Int32(1)
            end
        end
        
        # Standard consumers (non-blocking, drop on overflow)
        for (_, consumer_channel) in manager.standard_channels
            total_consumers += Int32(1)
            
            try
                # Non-blocking: check if space available
                if manager.drop_on_overflow
                    if isready(consumer_channel.channel) || 
                       length(consumer_channel.channel.data) < consumer_channel.buffer_size
                        put!(consumer_channel.channel, message)
                        consumer_channel.messages_sent += Int32(1)
                        successful += Int32(1)
                    else
                        # Drop message
                        consumer_channel.messages_dropped += Int32(1)
                        failed += Int32(1)
                    end
                else
                    # Blocking put
                    put!(consumer_channel.channel, message)
                    consumer_channel.messages_sent += Int32(1)
                    successful += Int32(1)
                end
            catch e
                failed += Int32(1)
            end
        end
        
        # Update stats
        manager.total_broadcasts += Int64(1)
        if failed == Int32(0)
            manager.successful_broadcasts += Int64(1)
        else
            manager.failed_broadcasts += Int64(1)
        end
    end
    
    return (total_consumers, successful, failed)
end

end # module
```

#### File: `test/test_triple_split.jl`
```julia
using Test
using TickDataPipeline
using TickDataPipeline.TripleSplitSystem

@testset begin #TripleSplitSystem
    @testset begin #Manager Creation
        manager = create_triple_split_manager()
        @test manager.priority_channel === nothing
        @test isempty(manager.standard_channels)
        @test manager.total_broadcasts == Int64(0)
    end
    
    @testset begin #Consumer Subscription
        manager = create_triple_split_manager()
        
        # Subscribe priority consumer
        priority_ch = subscribe_consumer!(manager, :production, PRIORITY, Int32(1024))
        @test priority_ch isa Channel{BroadcastMessage}
        @test manager.priority_channel !== nothing
        
        # Subscribe standard consumers
        monitor_ch = subscribe_consumer!(manager, :monitoring, MONITORING, Int32(512))
        @test haskey(manager.standard_channels, :monitoring)
        
        alert_ch = subscribe_consumer!(manager, :alerting, ALERTING, Int32(256))
        @test haskey(manager.standard_channels, :alerting)
    end
    
    @testset begin #Broadcasting
        manager = create_triple_split_manager()
        
        # Subscribe consumers
        priority_ch = subscribe_consumer!(manager, :production, PRIORITY)
        monitor_ch = subscribe_consumer!(manager, :monitoring, MONITORING)
        
        # Create test message
        msg = create_broadcast_message(Int32(1), Int64(1), Int32(100), Int32(5))
        
        # Broadcast
        (total, success, failed) = broadcast_to_all!(manager, msg)
        
        @test total == Int32(2)
        @test success == Int32(2)
        @test failed == Int32(0)
        
        # Consumers should receive message
        @test isready(priority_ch)
        @test isready(monitor_ch)
        
        priority_msg = take!(priority_ch)
        monitor_msg = take!(monitor_ch)
        
        @test priority_msg.tick_idx == Int32(1)
        @test monitor_msg.tick_idx == Int32(1)
    end
    
    @testset begin #Backpressure Handling
        manager = create_triple_split_manager(drop_on_overflow=true)
        
        # Small buffer for testing overflow
        small_ch = subscribe_consumer!(manager, :test, MONITORING, Int32(2))
        
        # Fill buffer
        for i in 1:10
            msg = create_broadcast_message(Int32(i), Int64(i), Int32(100), Int32(0))
            broadcast_to_all!(manager, msg)
        end
        
        # Some messages should have been dropped
        consumer = manager.standard_channels[:test]
        @test consumer.messages_dropped > Int32(0)
    end
end
```

### Success Criteria
- [ ] Multi-consumer channel management works
- [ ] Priority consumer never drops messages
- [ ] Standard consumers drop on overflow
- [ ] Thread-safe operations
- [ ] All tests pass
- [ ] Statistics tracking correct

---

## Session 5: PipelineConfig - Configuration System

**Duration**: 45-60 minutes  
**Dependencies**: Session 2 (FlowControlConfig)  
**Priority**: Medium

### Objectives
1. Implement simplified PipelineConfig (not ModernConfigSystem)
2. TOML loading and saving
3. Configuration validation
4. Default configurations

### Deliverables

#### File: `src/PipelineConfig.jl`
```julia
module PipelineConfig

export SignalProcessingConfig, FlowControlConfig, ChannelConfig, PerformanceConfig
export PipelineConfiguration, load_pipeline_config, save_pipeline_config
export create_default_pipeline_config, validate_pipeline_config

using TOML
using Dates

# Signal processing configuration (TickHotLoopF32)
# NO enable/disable flags - all features ALWAYS ENABLED
struct SignalProcessingConfig
    # Normalization (ALWAYS ENABLED)
    normalization_method::Symbol  # :ema, :sma, :fixed
    
    # Winsorization (ALWAYS ENABLED)
    winsorize_threshold::Float32
    
    # AGC (ALWAYS ENABLED)
    agc_alpha::Float32
    agc_min_scale::Int32
    agc_max_scale::Int32
    agc_guard_factor::Int32
    
    # Price validation (ALWAYS ENABLED)
    min_price_ticks::Int32
    max_price_ticks::Int32
    max_price_jump_ticks::Int32
end

# Flow control configuration
struct FlowControlConfig
    delay_ms::Float64
    enable_timing_validation::Bool
    timing_tolerance_ms::Int32
end

# Channel configuration
struct ChannelConfig
    priority_buffer_size::Int32
    standard_buffer_size::Int32
    enable_backpressure::Bool
    drop_on_overflow::Bool
    overflow_warning_threshold::Float32
end

# Performance configuration
struct PerformanceConfig
    target_latency_us::Int32
    max_latency_us::Int32
    target_throughput_tps::Float32
    max_memory_mb::Float32
end

# Main pipeline configuration
struct PipelineConfiguration
    pipeline_name::String
    description::String
    signal_processing::SignalProcessingConfig
    flow_control::FlowControlConfig
    channels::ChannelConfig
    performance::PerformanceConfig
    created::DateTime
    version::String
end

"""
Create default pipeline configuration
"""
function create_default_pipeline_config()::PipelineConfiguration
    return PipelineConfiguration(
        "default",
        "Default tick processing pipeline",
        SignalProcessingConfig(
            :ema,              # normalization_method
            Float32(3.0),      # winsorize_threshold
            Float32(0.0625),   # agc_alpha (1/16)
            Int32(4),          # agc_min_scale
            Int32(50),         # agc_max_scale
            Int32(7),          # agc_guard_factor
            Int32(40000),      # min_price_ticks
            Int32(43000),      # max_price_ticks
            Int32(50)          # max_price_jump_ticks
        ),
        FlowControlConfig(
            1.0,               # delay_ms
            true,              # enable_timing_validation
            Int32(10)          # timing_tolerance_ms
        ),
        ChannelConfig(
            Int32(4096),       # priority_buffer_size
            Int32(2048),       # standard_buffer_size
            true,              # enable_backpressure
            true,              # drop_on_overflow
            Float32(0.90)      # overflow_warning_threshold
        ),
        PerformanceConfig(
            Int32(500),        # target_latency_us
            Int32(1000),       # max_latency_us
            Float32(10000.0),  # target_throughput_tps
            Float32(512.0)     # max_memory_mb
        ),
        now(),
        "1.0"
    )
end

"""
Load pipeline configuration from TOML file
"""
function load_pipeline_config(config_path::String)::PipelineConfiguration
    if !isfile(config_path)
        @warn "Config file not found: $config_path, using defaults"
        return create_default_pipeline_config()
    end
    
    toml_data = TOML.parsefile(config_path)
    
    # Parse sections (with defaults if missing)
    # Implementation details...
    
    return create_default_pipeline_config()  # Placeholder
end

"""
Save pipeline configuration to TOML file
"""
function save_pipeline_config(config::PipelineConfiguration, config_path::String)
    # Convert to TOML dict and save
    # Implementation details...
end

"""
Validate pipeline configuration
"""
function validate_pipeline_config(config::PipelineConfiguration)::Bool
    errors = String[]
    
    # Validate latency targets
    if config.performance.max_latency_us <= config.performance.target_latency_us
        push!(errors, "max_latency must be > target_latency")
    end
    
    # Validate throughput
    if config.performance.target_throughput_tps <= Float32(0.0)
        push!(errors, "target_throughput must be positive")
    end
    
    # Validate AGC parameters
    if config.signal_processing.agc_min_scale >= config.signal_processing.agc_max_scale
        push!(errors, "agc_min_scale must be < agc_max_scale")
    end
    
    # ... more validation
    
    if !isempty(errors)
        for err in errors
            @error err
        end
        return false
    end
    
    return true
end

end # module
```

### Success Criteria
- [ ] Configuration structs defined
- [ ] Default configuration works
- [ ] TOML loading/saving implemented
- [ ] Validation catches errors
- [ ] Tests pass

---

## Session 6: PipelineOrchestrator - Main Loop

**Duration**: 60-75 minutes  
**Dependencies**: Sessions 2, 3, 4, 5  
**Priority**: Critical (Integration)

### Objectives
1. Implement main pipeline loop
2. Integrate all components
3. Implement `process_single_tick_through_pipeline!`
4. Implement metrics collection
5. Handle pipeline lifecycle

### Deliverables

#### File: `src/PipelineOrchestrator.jl`
```julia
module PipelineOrchestrator

export PipelineManager, create_pipeline_manager, run_pipeline!
export process_single_tick_through_pipeline!

using ..TickDataPipeline: BroadcastMessage
using ..VolumeExpansion: stream_expanded_ticks
using ..TickHotLoopF32: TickHotLoopState, create_tickhotloop_state, process_tick_signal!
using ..TripleSplitSystem: TripleSplitManager, broadcast_to_all!
using ..PipelineConfig: PipelineConfiguration

"""
Pipeline manager - orchestrates all components
"""
mutable struct PipelineManager
    config::PipelineConfiguration
    tickhotloop_state::TickHotLoopState
    split_manager::TripleSplitManager
    is_running::Bool
    completion_callback::Union{Function, Nothing}
end

"""
Create pipeline manager
"""
function create_pipeline_manager(
    config::PipelineConfiguration,
    split_manager::TripleSplitManager
)::PipelineManager
    return PipelineManager(
        config,
        create_tickhotloop_state(),
        split_manager,
        false,
        nothing
    )
end

"""
Process single tick through pipeline (INTERNAL)
Returns: NamedTuple with metrics
"""
function process_single_tick_through_pipeline!(
    manager::PipelineManager,
    msg::BroadcastMessage
)::NamedTuple
    pipeline_start = time_ns()
    
    # Stage 2: Signal processing (TickHotLoopF32)
    signal_start = time_ns()
    
    sp = manager.config.signal_processing
    process_tick_signal!(
        msg,
        manager.tickhotloop_state,
        sp.agc_alpha,
        sp.agc_min_scale,
        sp.agc_max_scale,
        sp.winsorize_threshold,
        sp.min_price_ticks,
        sp.max_price_ticks,
        sp.max_price_jump_ticks
    )
    
    signal_time_us = Int32((time_ns() - signal_start) ÷ 1000)
    
    # Stage 3: Broadcasting
    broadcast_start = time_ns()
    (total, success, failed) = broadcast_to_all!(manager.split_manager, msg)
    broadcast_time_us = Int32((time_ns() - broadcast_start) ÷ 1000)
    
    total_time_us = Int32((time_ns() - pipeline_start) ÷ 1000)
    
    return (
        success = (failed == Int32(0)),
        total_latency_us = total_time_us,
        signal_processing_time_us = signal_time_us,
        broadcast_time_us = broadcast_time_us,
        consumers_reached = success,
        complex_signal = msg.complex_signal,
        price_delta = msg.price_delta,
        status_flag = msg.status_flag
    )
end

"""
Run pipeline main loop
"""
function run_pipeline!(
    manager::PipelineManager,
    tick_file_path::String,
    num_ticks::Union{Int, Nothing} = nothing
)
    manager.is_running = true
    
    # Get message stream from VolumeExpansion
    delay_ms = manager.config.flow_control.delay_ms
    message_channel = stream_expanded_ticks(tick_file_path, delay_ms)
    
    tick_count = 0
    
    # Process each message
    for msg in message_channel
        if !manager.is_running
            break
        end
        
        # Process through pipeline
        result = process_single_tick_through_pipeline!(manager, msg)
        
        tick_count += 1
        
        # Check tick limit
        if num_ticks !== nothing && tick_count >= num_ticks
            break
        end
    end
    
    # Completion callback
    if manager.completion_callback !== nothing
        manager.completion_callback(tick_count)
    end
    
    manager.is_running = false
end

end # module
```

### Success Criteria
- [ ] Main pipeline loop functional
- [ ] All components integrated
- [ ] Metrics collection works
- [ ] Tests pass
- [ ] End-to-end processing verified

---

## Session 7: Public API & Examples

**Duration**: 45-60 minutes  
**Dependencies**: Session 6  
**Priority**: High (User Interface)

### Objectives
1. Implement user-facing API
2. Implement persistent consumers
3. Create usage examples
4. Document API

### Deliverables

#### File: `src/PipelineAPI.jl`
```julia
module PipelineAPI

export start_tick_pipeline, TickPipelineHandle
export subscribe_consumer, get_consumer_channel
export set_completion_callback

using ..TickDataPipeline: BroadcastMessage
using ..PipelineConfig: PipelineConfiguration, create_default_pipeline_config
using ..TripleSplitSystem: TripleSplitManager, create_triple_split_manager
using ..TripleSplitSystem: subscribe_consumer!, ConsumerType, PRIORITY, MONITORING
using ..PipelineOrchestrator: PipelineManager, create_pipeline_manager, run_pipeline!

"""
Pipeline control handle
"""
mutable struct TickPipelineHandle
    manager::PipelineManager
    pipeline_task::Union{Task, Nothing}
    persistent_consumers::Set{Symbol}
end

"""
Start tick processing pipeline
"""
function start_tick_pipeline(;
    tick_file_path::String,
    num_ticks::Union{Int, Nothing} = nothing,
    tick_delay_ms::Float64 = 0.0,
    buffer_sizes::Dict{Symbol, Int} = Dict(:priority => 2048, :standard => 1024),
    persistent_consumers::Vector{Symbol} = Symbol[],
    config::Union{PipelineConfiguration, Nothing} = nothing
)::TickPipelineHandle
    
    # Use provided config or create default
    cfg = config === nothing ? create_default_pipeline_config() : config
    
    # Override delay if specified
    if tick_delay_ms > 0.0
        # Create modified config with new delay
        # ...
    end
    
    # Create triple split manager
    split_manager = create_triple_split_manager()
    
    # Subscribe persistent consumers
    for consumer_id in persistent_consumers
        consumer_type = consumer_id == :priority ? PRIORITY : MONITORING
        buffer_size = get(buffer_sizes, consumer_id, 1024)
        subscribe_consumer!(split_manager, consumer_id, consumer_type, Int32(buffer_size))
    end
    
    # Create pipeline manager
    manager = create_pipeline_manager(cfg, split_manager)
    
    # Start pipeline task
    task = @async run_pipeline!(manager, tick_file_path, num_ticks)
    
    handle = TickPipelineHandle(
        manager,
        task,
        Set(persistent_consumers)
    )
    
    return handle
end

"""
Subscribe consumer with callback
"""
function subscribe_consumer(
    handle::TickPipelineHandle,
    consumer_id::Symbol,
    callback::Function
)
    channel = get_consumer_channel(handle, consumer_id)
    
    if channel === nothing
        error("Consumer $consumer_id not found")
    end
    
    @async begin
        for msg in channel
            callback(msg)
        end
    end
end

"""
Get consumer channel
"""
function get_consumer_channel(
    handle::TickPipelineHandle,
    consumer_id::Symbol
)::Union{Channel{BroadcastMessage}, Nothing}
    return TripleSplitSystem.get_consumer_channel(
        handle.manager.split_manager,
        consumer_id
    )
end

"""
Set completion callback
"""
function set_completion_callback(
    handle::TickPipelineHandle,
    callback::Function
)
    handle.manager.completion_callback = callback
end

end # module
```

#### File: `examples/basic_usage.jl`
```julia
using TickDataPipeline

# Start pipeline with persistent monitoring
handle = start_tick_pipeline(
    tick_file_path = "data/raw/YM 06-25.Last.txt",
    num_ticks = 1000,
    tick_delay_ms = 1.0,
    persistent_consumers = [:monitoring]
)

# Get monitoring channel
monitoring_ch = get_consumer_channel(handle, :monitoring)

# Process monitoring data
@async for msg in monitoring_ch
    println("Tick $(msg.tick_idx): price=$(msg.raw_price), Δ=$(msg.price_delta)")
end

# Set completion callback
set_completion_callback(handle) do tick_count
    println("Completed processing $tick_count ticks")
end

# Wait for completion
wait(handle.pipeline_task)
```

### Success Criteria
- [ ] Public API implemented
- [ ] Examples work
- [ ] Documentation clear
- [ ] User-friendly interface

---

## Session 8: Testing, Documentation & Polish

**Duration**: 90-120 minutes  
**Dependencies**: All previous sessions  
**Priority**: High (Quality Assurance)

### Objectives
1. Comprehensive integration tests
2. Performance benchmarks
3. Complete documentation
4. README with examples
5. Final polish

### Deliverables

#### File: `test/test_integration.jl`
```julia
using Test
using TickDataPipeline

@testset begin #Integration Tests
    @testset begin #End-to-End Pipeline
        # Create test file
        test_file = "test_integration_ticks.txt"
        open(test_file, "w") do f
            for i in 1:100
                println(f, "20250319 070000 $(i*10000);41970;41971;41972;1")
            end
        end
        
        try
            # Start pipeline
            handle = start_tick_pipeline(
                tick_file_path = test_file,
                num_ticks = 100,
                tick_delay_ms = 0.0,
                persistent_consumers = [:test_consumer]
            )
            
            # Consume messages
            messages_received = BroadcastMessage[]
            ch = get_consumer_channel(handle, :test_consumer)
            
            @async for msg in ch
                push!(messages_received, msg)
            end
            
            # Wait for completion
            wait(handle.pipeline_task)
            
            # Verify
            @test length(messages_received) == 100
            @test all(msg -> msg.complex_signal != ComplexF32(0,0), messages_received)
            
        finally
            rm(test_file, force=true)
        end
    end
end
```

#### File: `README.md`
```markdown
# TickDataPipeline.jl

High-performance tick data processing pipeline for Julia with GPU-compatible output.

## Features

- Volume expansion and preprocessing
- Real-time signal processing (normalization, AGC, QUAD-4 rotation)
- Multi-consumer broadcasting with backpressure handling
- GPU-compatible data structures
- Zero-allocation hot loop
- Configurable via TOML files

## Installation

```julia
using Pkg
Pkg.add("TickDataPipeline")
```

## Quick Start

```julia
using TickDataPipeline

# Start pipeline
handle = start_tick_pipeline(
    tick_file_path = "data/ticks.txt",
    tick_delay_ms = 1.0
)

# Process data
subscribe_consumer(handle, :my_consumer) do msg
    println("Tick: $(msg.tick_idx), Price: $(msg.raw_price)")
end

wait(handle.pipeline_task)
```

## Documentation

See full documentation at [docs/](docs/).

## License

MIT
```

### Success Criteria
- [ ] All integration tests pass
- [ ] Documentation complete
- [ ] README informative
- [ ] Examples work
- [ ] Package ready for v0.1.0 release

---

## Summary & Checklist

### Total Implementation Time: 8-10 hours

### Session Summary
1. **Foundation** (60 min): Project setup, BroadcastMessage
2. **Data Prep** (90 min): VolumeExpansion, timestamp encoding
3. **Hot Loop** (120 min): TickHotLoopF32 signal processing
4. **Broadcasting** (90 min): TripleSplitSystem
5. **Configuration** (60 min): PipelineConfig
6. **Orchestration** (75 min): PipelineOrchestrator
7. **API** (60 min): Public API, examples
8. **Testing** (120 min): Integration tests, docs

### Final Package Structure
```
TickDataPipeline.jl/
├── Project.toml
├── README.md
├── src/
│   ├── TickDataPipeline.jl
│   ├── BroadcastMessage.jl
│   ├── VolumeExpansion.jl
│   ├── TickHotLoopF32.jl
│   ├── TripleSplitSystem.jl
│   ├── PipelineConfig.jl
│   ├── PipelineOrchestrator.jl
│   └── PipelineAPI.jl
├── test/
│   ├── runtests.jl
│   ├── test_broadcast_message.jl
│   ├── test_volume_expansion.jl
│   ├── test_tickhotloopf32.jl
│   ├── test_triple_split.jl
│   └── test_integration.jl
├── examples/
│   ├── basic_usage.jl
│   ├── persistent_monitoring.jl
│   └── gpu_consumer.jl
└── config/
    └── pipeline/
        ├── default.toml
        └── production.toml
```

### Pre-Implementation Checklist
- [ ] Design specification reviewed
- [ ] Development environment ready
- [ ] Test data files available
- [ ] Julia 1.9+ installed
- [ ] Git repository initialized

### Post-Implementation Checklist
- [ ] All tests pass
- [ ] Documentation complete
- [ ] Examples tested
- [ ] Performance verified
- [ ] Ready for v0.1.0 tag

---

**Note**: Each session can be executed independently in Claude Code. Save progress after each session and verify tests pass before proceeding to the next session.
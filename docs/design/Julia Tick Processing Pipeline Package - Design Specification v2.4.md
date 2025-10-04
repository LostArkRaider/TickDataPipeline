# Julia Tick Processing Pipeline Package - Design Specification

## Project Overview

This document specifies the design for extracting the tick data processing pipeline from a larger Julia signal processing application into a standalone, reusable package. The original application processes YM futures tick data through a filter bank with genetic algorithm (GA) optimization capabilities. This extraction will create a focused package that handles tick ingestion, preprocessing, and distribution to multiple consumers via Julia Channels.

## Package Purpose

Create a standalone Julia package named `TickDataPipeline.jl` (or similar) that:
- Reads and preprocesses YM futures tick data from flat files
- Performs volume expansion and signal processing transformations
- Distributes processed tick data to multiple downstream consumers via dedicated Channels
- Provides a clean API for integration into other Julia applications
- Can be installed as a standard Julia package

## Architecture Overview

### Data Flow Pipeline

```
Tick File → VolumeExpansion → FlowControl → TickHotLoopF32 → TripleSplitSystem → Multiple Consumers
                                                                                    ↓
                                                                    ProductionFilterConsumer (Priority)
                                                                    MonitoringConsumer
                                                                    ABTestManager
                                                                    SimulatedLiveEvaluator
```

## Input Specification

### Tick Data File Format

**File Location**: `data/raw/YM 06-25.Last.txt`

**File Characteristics**:
- ASCII text file
- No header row
- Semicolon (`;`) delimited CSV format
- `.txt` file extension

**Data Format**:
```
yyyymmdd hhmmss u-seconds;bid;asked;last;volume
```

**Sample Data**:
```
20250319 070000 0520000;41971;41970;41971;1
20250319 070001 4640000;41970;41969;41970;1
20250319 070001 5200000;41970;41969;41970;1
20250319 070001 6080000;41970;41969;41970;1
```

**Field Descriptions**:
- **Timestamp**: `yyyymmdd hhmmss u-seconds` (date, time, microseconds)
- **Bid**: Bid price (integer ticks)
- **Asked**: Ask price (integer ticks)
- **Last**: Last trade price (integer ticks) - **PRIMARY FIELD**
- **Volume**: Trade volume (integer)

## Internal Pipeline Orchestration

### Core Processing Function (Internal Use)

The pipeline uses a central orchestration function that processes each tick through all stages. This function is **internal to the package** and primarily used by the main processing loop, though it can be useful for testing and debugging.

**IMPORTANT**: With the optimized architecture, this function is now much simpler since most work is done in VolumeExpansion.

```julia
"""
Process single tick through complete pipeline stages (INTERNAL FUNCTION)
Returns detailed metrics and processing results

SIMPLIFIED: Most work done in VolumeExpansion; this just coordinates signal processing.

Primary use cases:
1. Called repeatedly by run_pipeline_loop!() for each message
2. Unit testing specific tick scenarios
3. Performance profiling and bottleneck identification  
4. Debugging problematic tick records

Parameters:
- manager: PipelineManager with initialized state
- broadcast_msg: Pre-populated BroadcastMessage from VolumeExpansion
- tick_idx: Sequential tick index (Int32) - can be read from broadcast_msg

Returns NamedTuple with:
- success: Bool - Overall processing success
- total_latency_us: Int32 - End-to-end processing time
- signal_processing_time_us: Int32 - TickHotLoopF32 processing time (CRITICAL METRIC)
- triple_split_time_us: Int32 - Broadcasting time
- complex_signal: ComplexF32 - Processed I/Q signal
- delta_ticks: Int32 - Price change from previous tick
- processing_flag: UInt8 - Status flags
- consumers_reached: Int32 - Number of consumers that received message
"""
function process_single_tick_through_pipeline!(
    manager::PipelineManager, 
    broadcast_msg::BroadcastMessage  # Changed: now receives pre-populated message
)::NamedTuple
    
    pipeline_start_time = time_ns()
    
    # NO PREPROCESSING STAGE - already done in VolumeExpansion!
    # Message arrives fully parsed with timestamp encoded, raw_price extracted, price_delta computed
    
    # Stage 2: Signal processing (TickHotLoopF32) - THE ONLY HOT LOOP
    signal_processing_start_time = time_ns()
    
    # Get already-computed price_delta (NO calculation needed)
    price_delta = broadcast_msg.price_delta
    
    # Process signal (ONLY math, no parsing/allocation)
    complex_signal, normalization, status_flag = process_tick_signal!(
        manager.tickhotloop_state,
        price_delta,
        broadcast_msg.tick_idx
    )
    
    # Update message IN-PLACE (no allocation)
    broadcast_msg.complex_signal = complex_signal
    broadcast_msg.normalization = normalization
    broadcast_msg.status_flag = status_flag
    
    signal_processing_time_us = Int32((time_ns() - signal_processing_start_time) ÷ 1000)
    
    # Stage 3: Triple split broadcasting
    triple_split_start_time = time_ns()
    
    # Broadcast fully-populated message to all consumers
    (total_consumers, successful_deliveries, failed_deliveries) = 
        broadcast_to_all!(manager.split_manager, broadcast_msg)
    
    triple_split_time_us = Int32((time_ns() - triple_split_start_time) ÷ 1000)
    
    # Calculate total latency (should be MUCH lower now)
    total_latency_us = Int32((time_ns() - pipeline_start_time) ÷ 1000)
    
    return (
        success = (failed_deliveries == 0),
        total_latency_us = total_latency_us,
        signal_processing_time_us = signal_processing_time_us,  # CRITICAL: should be ~50-80μs
        triple_split_time_us = triple_split_time_us,
        consumers_reached = successful_deliveries,
        complex_signal = complex_signal,
        delta_ticks = price_delta,
        processing_flag = status_flag
    )
end
```

### Pipeline Main Loop (Internal)

The main processing loop is now cleaner since messages arrive pre-populated:

```julia
function run_pipeline_loop!(manager::PipelineManager)
    # Get pre-populated message stream from VolumeExpansion
    # NOTE: VolumeExpansion now returns Channel{BroadcastMessage}, not Channel{String}
    message_channel = VolumeExpansion.stream_expanded_ticks(
        manager.config.tick_file_path,
        manager.config.flow_config
    )
    
    # Process each pre-populated message as it arrives
    for broadcast_msg in message_channel
        # CORE: Update signal fields and broadcast
        # MUCH FASTER: No parsing, encoding, or allocation overhead
        result = process_single_tick_through_pipeline!(
            manager, 
            broadcast_msg  # Pre-populated message
        )
        
        # Update aggregated metrics
        update_pipeline_metrics!(manager.metrics, result)
        
        # Check for stop condition
        if should_stop_pipeline(manager)
            break
        end
    end
    
    # Call completion callback if set
    if manager.completion_callback !== nothing
        stats = create_pipeline_stats(manager.metrics)
        manager.completion_callback(stats)
    end
end
```

**Design Rationale**:
- **Extreme performance**: TickHotLoopF32 overhead reduced to bare minimum
- **Clear separation**: VolumeExpansion = data prep, TickHotLoopF32 = signal processing
- **Testability**: Can test signal processing isolated from parsing
- **Metrics**: Can measure pure signal processing time vs. total latency
- **Not part of public API**: Users interact with `start_tick_pipeline()`, not this internal function

**Expected Performance**:
- **Old architecture**: 150-200μs per tick in TickHotLoopF32
- **New architecture**: 50-80μs per tick in TickHotLoopF32
- **Speedup**: 2-3x faster hot loop

### Stage 1: Volume Expansion & Message Preparation (`VolumeExpansion.jl`)

**Purpose**: Expand multi-volume ticks, perform ALL data preparation, and create pre-populated BroadcastMessages for downstream processing.

**Critical Design Philosophy**: This stage handles ALL non-signal-processing work to keep TickHotLoopF32 as fast as possible.

**Logic**:
- When `volume > 1`: Clone the tick record `(volume - 1)` times
- Set `volume = 1` for the original record and all clones
- All cloned records have identical timestamp and price data

**Data Preparation (Performed Here, NOT in TickHotLoopF32)**:

1. **Timestamp Encoding**
   - Convert full ASCII timestamp to Int64 encoding
   - **Encoding Scheme**: Use ASCII character codes, reserving 8 bits per character
   - **Storage**: Encode as Int64 value that can be decoded back to original ASCII string
   - **WHY HERE**: Encoding is slow; do it once upstream

2. **Raw Price Extraction**
   - Extract "last" price field from tick data (4th field)
   - Convert to Int32 for GPU compatibility
   - **WHY HERE**: Simple parsing done once per tick

3. **Price Delta Calculation**
   - Calculate `price_delta = current_last - previous_last`
   - Track previous_last in VolumeExpansion state
   - **WHY HERE**: Simple subtraction, no need to burden TickHotLoopF32

4. **BroadcastMessage Pre-Creation**
   - Create BroadcastMessage with ALL fields except those computed by TickHotLoopF32
   - **Pre-populated fields**: tick_idx, timestamp, raw_price, price_delta
   - **Placeholder fields**: normalization (default Float32(1.0)), complex_signal (default ComplexF32(0,0)), status_flag (default UInt8(0))
   - **WHY HERE**: Memory allocation and struct creation done upstream

**Streaming Interface**:
```julia
function stream_expanded_ticks(file_path::String, flow_config)::Channel{BroadcastMessage}
    # CHANGED: Now returns Channel{BroadcastMessage} instead of Channel{String}
    
    return Channel{BroadcastMessage}() do channel
        previous_last = Int32(0)
        tick_idx = Int32(0)
        
        open(file_path, "r") do file
            for line in eachline(file)
                expanded_lines = process_tick_line_simple(line)
                
                for expanded_line in expanded_lines
                    tick_idx += 1
                    
                    # Parse tick data
                    parts = split(expanded_line, ';')
                    timestamp_str = parts[1]
                    bid = parse(Int32, parts[2])
                    ask = parse(Int32, parts[3])
                    last = parse(Int32, parts[4])
                    volume = parse(Int32, parts[5])
                    
                    # 1. Encode timestamp to Int64 (SLOW - do here)
                    timestamp_encoded = encode_timestamp_to_int64(timestamp_str)
                    
                    # 2. Calculate price delta (SIMPLE - do here)
                    price_delta = tick_idx == 1 ? Int32(0) : last - previous_last
                    previous_last = last
                    
                    # 3. Create pre-populated BroadcastMessage (ALLOCATION - do here)
                    broadcast_msg = BroadcastMessage(
                        tick_idx = tick_idx,
                        timestamp = timestamp_encoded,
                        raw_price = last,
                        price_delta = price_delta,
                        normalization = Float32(1.0),      # Placeholder - updated by TickHotLoopF32
                        complex_signal = ComplexF32(0, 0), # Placeholder - updated by TickHotLoopF32
                        status_flag = UInt8(0)             # Placeholder - updated by TickHotLoopF32
                    )
                    
                    # Apply flow control delay (between stages 1 and 2)
                    if delay_ms > 0.0
                        sleep(delay_ms / 1000.0)
                    end
                    
                    put!(channel, broadcast_msg)  # Send to Stage 3 (TickHotLoopF32)
                end
            end
        end
    end
end
```

**Output**: Returns `Channel{BroadcastMessage}` with pre-populated messages ready for signal processing.

**Performance Impact**: 
- Removes ~5-10μs of overhead from TickHotLoopF32 per tick
- Moves string parsing, encoding, and allocation to non-critical path
- TickHotLoopF32 can focus purely on signal processing math

### Stage 2: Flow Control (`FlowControlConfig.jl`)

**Purpose**: Control the rate of tick delivery to consumers.

**Implementation Location**: Flow control delay is applied **inside VolumeExpansion's streaming loop** when putting records into the Channel{String}.

**Configuration**:
- Delay specified in milliseconds (can be from config file or API)
- Applies delay between consecutive tick transmissions
- Implemented as `sleep()` call before each `put!(channel, expanded_line)`

**API Control**:
- Delay value must be configurable via the package API
- Default value should be loaded from config file if available

**Code Integration**:
```julia
# Inside VolumeExpansion.stream_expanded_ticks()
for expanded_line in expanded_lines
    # Flow control applied HERE
    if delay_ms > 0.0
        sleep(delay_ms / 1000.0)  # Convert ms to seconds
    end
    put!(channel, expanded_line)
end
```

**Design Note**: Flow control is integrated into VolumeExpansion rather than being a separate stage, since it controls the rate at which ticks are placed into the channel for downstream consumption.

### Stage 3: Complex Signal Processing (`TickHotLoopF32.jl`)

**Purpose**: ULTRA-FAST signal processing - ONLY compute complex signal transformation. All other work done upstream.

**Critical Performance Requirement**: This is the HOT PATH. Every microsecond counts. NO parsing, NO allocations, NO string operations.

**Input**: Reads pre-populated `BroadcastMessage` from the `Channel{BroadcastMessage}` produced by VolumeExpansion.

**What TickHotLoopF32 Does (ONLY)**:
1. **Read price_delta** from the pre-populated message (already computed in VolumeExpansion)
2. **Perform normalization** with winsorization on price_delta (**ALWAYS ENABLED - no conditional check**)
   - Apply AGC (Automatic Gain Control)
   - Winsorize outliers
   - Calculate normalization factor (Float32)
   - Produce normalized price change value
3. **Apply QUAD-4 rotation** to convert normalized value to ComplexF32 (**ALWAYS ENABLED - no conditional check**)
   - Real component = I signal
   - Imaginary component = Q signal
4. **Generate status flag** (UInt8)
5. **UPDATE the BroadcastMessage** in-place (no allocation!)
   - Update `complex_signal` field
   - Update `normalization` field
   - Update `status_flag` field
6. **Pass message forward** to TripleSplitSystem

**PERFORMANCE CRITICAL - NO CONDITIONAL BRANCHES**:
- All signal processing steps are **hard-wired ENABLED**
- No `if (enable_normalization)` checks
- No `if (agc_enabled)` checks  
- No `if (quad4_enabled)` checks
- **Zero branching overhead** in hot loop
- Predictable instruction pipeline
- Maximum CPU efficiency

**What TickHotLoopF32 Does NOT Do (Moved to VolumeExpansion)**:
- ❌ Parse tick strings
- ❌ Extract timestamp
- ❌ Encode timestamp to Int64
- ❌ Extract raw price
- ❌ Calculate price delta
- ❌ Create BroadcastMessage struct
- ❌ Allocate memory

**Channel Reading Pattern**:
```julia
# Read pre-populated messages from VolumeExpansion channel
message_channel = VolumeExpansion.stream_expanded_ticks(file_path, flow_config)

for broadcast_msg in message_channel
    # SPEED CRITICAL SECTION STARTS HERE
    
    # Get already-computed price delta (NO CALCULATION)
    price_delta = broadcast_msg.price_delta
    
    # Apply QUAD-4 rotation and normalization (ONLY MATH)
    z, normalization_factor, status_flag = process_tick_signal(
        price_delta, 
        broadcast_msg.tick_idx,
        manager.tickhotloop_state  # Stateful EMA tracking
    )
    
    # UPDATE message in-place (NO ALLOCATION)
    broadcast_msg.complex_signal = z
    broadcast_msg.normalization = normalization_factor
    broadcast_msg.status_flag = status_flag
    
    # SPEED CRITICAL SECTION ENDS HERE
    
    # Send to TripleSplitSystem for broadcast
    broadcast_to_consumers(broadcast_msg)
end
```

**Performance Optimization Notes**:
- **Mutable struct**: BroadcastMessage should be mutable to allow in-place updates
- **No allocations**: Only update existing fields
- **Cache-friendly**: Access sequential fields in the pre-existing struct
- **Minimal branching**: Keep conditional logic to absolute minimum

**Required Enhancement**:
- **Normalization Factor Export**: Update the `normalization` field in the existing BroadcastMessage
- This allows consumers to denormalize signals if needed for analysis

**Output**:
- Updated `BroadcastMessage` with:
  - `complex_signal::ComplexF32` - Complex signal (I + jQ)
  - `normalization::Float32` - Normalization factor applied
  - `status_flag::UInt8` - Processing status byte

**Connection to Stage 4**: Passes the completed BroadcastMessage to TripleSplitSystem for distribution to consumer channels.

**Estimated Latency Reduction**: 
- **Before**: ~150-200μs per tick (with parsing, encoding, allocation)
- **After**: ~50-80μs per tick (pure signal processing math)
- **Speedup**: 2-3x faster hot loop

### Stage 4: Triple Split Broadcast System (`TripleSplitSystem.jl`)

**Purpose**: Distribute processed tick data to multiple consumers with priority handling and backpressure management.

**Channel Architecture**:

#### Producer-Side vs Consumer-Side Components

**Producer-Side** (included in TickDataPipeline package):
- `TripleSplitSystem.jl` - Core channel management and broadcast logic
- `BroadcastMessage.jl` - Message structure definition

**Consumer-Side** (NOT included in base package):
- `TripleSplitManager.jl` - Consumer subscription and lifecycle management
- `ProductionFilterConsumer.jl` - Production filter bank consumer
- `MonitoringConsumer.jl` - Monitoring and alerting consumer
- `TripleSplitMetrics_addition.jl` - Metrics collection utilities

**Rationale**: The package provides the tick stream and broadcast infrastructure. Consumers are application-specific and should be implemented by the consuming application.

#### Multi-Consumer Design with Priority Handling

**Consumer Types** (4 consumers):
1. **ProductionFilterConsumer** - **PRIORITY PATH**
   - Dedicated channel with guaranteed delivery
   - Cannot be delayed by backpressure from other consumers
   - Must always process ticks without blocking
   
2. **MonitoringConsumer** - Standard priority
3. **ABTestManager** - Standard priority
4. **SimulatedLiveEvaluator** - Standard priority

**Channel Configuration**:
- **Separate Channels**: Each consumer has its own dedicated Julia Channel
- **Buffer Sizes**: All channels must have configurable buffer sizes
- **Backpressure Handling**: 
  - ProductionFilterConsumer: Never drops messages, has priority delivery
  - Other consumers: Drop messages on buffer overflow (lossy delivery acceptable)

**Broadcast Mechanism**:
```julia
function broadcast_to_all!(manager, message::BroadcastMessage)
    # Priority consumer (non-blocking guaranteed delivery)
    put!(priority_channel, message)
    
    # Standard consumers (non-blocking with overflow handling)
    for consumer_channel in standard_channels
        if !isready(consumer_channel) || length(consumer_channel) < buffer_size
            put!(consumer_channel, message)
        else
            # Drop message - buffer full, backpressure applied
            record_dropped_message(consumer_channel)
        end
    end
end
```

## BroadcastMessage Structure

**GPU Compatibility Requirement**: All fields must use GPU-compatible primitive types (no String types).

**Mutability Requirement**: Must be mutable to allow TickHotLoopF32 to update fields in-place without allocation.

Based on the existing code signature, with GPU compatibility and in-place update optimization:

```julia
mutable struct BroadcastMessage  # MUTABLE for in-place updates
    tick_idx::Int32              # Sequential tick index
    timestamp::Int64             # Encoded timestamp (ASCII → Int64)
    raw_price::Int32             # Original "last" price from tick data
    price_delta::Int32           # Tick-to-tick price change (Δ)
    normalization::Float32       # Normalization factor (updated by TickHotLoopF32)
    complex_signal::ComplexF32   # I/Q complex signal (updated by TickHotLoopF32)
    status_flag::UInt8           # Processing status byte (updated by TickHotLoopF32)
end
```

**Field Lifecycle**:

**Populated by VolumeExpansion**:
- `tick_idx`: Sequential index for this tick
- `timestamp`: Encoded timestamp using 8-bit ASCII character codes
- `raw_price`: Original last trade price before transformations
- `price_delta`: Already computed tick-to-tick change

**Populated by TickHotLoopF32** (in-place update):
- `normalization`: Normalization factor applied during signal processing
- `complex_signal`: QUAD-4 rotated complex signal (real=I, imag=Q)
- `status_flag`: Processing status flags (UInt8 bitmask)

**Factory Function for VolumeExpansion**:
```julia
function create_broadcast_message(
    tick_idx::Int32,
    timestamp::Int64,           # Already encoded in VolumeExpansion
    raw_price::Int32,           # Extracted from tick data "last" field
    price_delta::Int32          # Already computed in VolumeExpansion
)::BroadcastMessage
    return BroadcastMessage(
        tick_idx,
        timestamp,
        raw_price,
        price_delta,
        Float32(1.0),      # Placeholder - updated by TickHotLoopF32
        ComplexF32(0, 0),  # Placeholder - updated by TickHotLoopF32
        UInt8(0)           # Placeholder - updated by TickHotLoopF32
    )
end
```

**In-Place Update by TickHotLoopF32**:
```julia
function update_broadcast_message!(
    msg::BroadcastMessage,
    complex_signal::ComplexF32,
    normalization::Float32,
    status_flag::UInt8
)
    # Fast in-place update - NO ALLOCATION
    msg.complex_signal = complex_signal
    msg.normalization = normalization
    msg.status_flag = status_flag
end
```

**GPU Compatibility Notes**:
- All fields are primitive types suitable for GPU kernels
- No String types (removed config_name for GPU compatibility)
- Mutable struct allows efficient in-place updates
- Total structure size: 32 bytes (highly cache-efficient)
- Can be passed directly to CUDA kernels without conversion

**Performance Benefits**:
- VolumeExpansion creates struct once (allocation cost paid upstream)
- TickHotLoopF32 only updates 3 fields in-place (zero allocation overhead)
- Cache-friendly: struct fits in single cache line

## Configuration System

### Design Decision: Simplified Configuration vs. ModernConfigSystem

**The tick pipeline package will NOT use the existing `ModernConfigSystem.jl`** from the main application. Here's why:

**ModernConfigSystem.jl is Too Specialized**:
- Designed for GA-evolved filter banks with PLL processing
- Contains parameters specific to:
  - Genetic Algorithm initialization (population, fitness, evolution)
  - Phase-Locked Loop (PLL) tuning (phase detector gain, loop bandwidth, lock threshold)
  - Fibonacci filter bank periods ([1, 2, 3, 5, 8, 13, 21, 34, 55])
  - Individual filter overrides (per-period parameter tuning)
  - Filter-specific parameters (Q factor, ring decay, clamping thresholds)
- 800+ lines of filter-bank domain logic
- Tight coupling to GA/PLL/filter concepts

**Tick Pipeline Needs Simpler Configuration**:
- Focus on tick processing fundamentals:
  - Flow control (delays, throughput)
  - Signal processing (normalization, winsorization, AGC)
  - Channel management (buffers, backpressure)
  - Performance targets (latency, throughput)
- No GA, no PLL, no filter-bank periods
- Clean separation from downstream consumer concerns

**Solution**: Create **`PipelineConfig.jl`** - a lightweight, focused configuration system for tick processing.

### PipelineConfig Structure

The pipeline uses a **simplified, hierarchical configuration** tailored for tick processing:

```julia
# Core configuration structure
struct PipelineConfig
    # Identity
    pipeline_name::String
    description::String
    
    # Signal Processing (TickHotLoopF32 parameters only)
    signal_processing::SignalProcessingConfig
    
    # Flow Control (tick rate management)
    flow_control::FlowControlConfig
    
    # Channel Management
    channels::ChannelConfig
    
    # Performance Targets
    performance::PerformanceConfig
    
    # Monitoring (optional)
    monitoring::MonitoringConfig
    
    # Metadata
    created::DateTime
    version::String
end

# Signal processing parameters (TickHotLoopF32)
struct SignalProcessingConfig
    # PERFORMANCE CRITICAL: No enable/disable flags in hot loop!
    # All features are ALWAYS ENABLED to eliminate branching overhead
    # Normalization, winsorization, AGC, and QUAD-4 are hard-wired ON
    
    # Normalization parameters (ALWAYS ENABLED)
    normalization_method::Symbol  # :ema, :sma, :fixed (but always normalized)
    
    # Winsorization parameters (ALWAYS ENABLED)
    winsorize_threshold::Float32  # Standard deviations for clipping
    
    # AGC parameters (ALWAYS ENABLED)
    agc_alpha::Float32           # EMA coefficient (e.g., 0.0625 = 1/16)
    agc_min_scale::Int32         # Minimum scale factor
    agc_max_scale::Int32         # Maximum scale factor
    agc_guard_factor::Int32      # Stability guard
    
    # Price validation (ALWAYS ENABLED)
    min_price_ticks::Int32       # Minimum valid price
    max_price_ticks::Int32       # Maximum valid price
    max_price_jump_ticks::Int32  # Max tick-to-tick jump
    
    # NOTE: QUAD-4 rotation is ALWAYS ENABLED (hard-wired)
    # No quad4_enabled flag to avoid branching in hot loop
end
```

**Design Rationale**:
- **Zero conditional branches** in TickHotLoopF32 hot loop
- All signal processing features are **always active**
- Configuration only controls **parameters**, not **enablement**
- Eliminates branch misprediction penalties
- Predictable, consistent latency

**Performance Impact**:
- Removes ~5-10 CPU cycles per tick (branch prediction + checks)
- Eliminates conditional jumps in hot loop
- Better instruction pipelining
- Consistent code path for CPU branch predictor

**If User Wants "Disabled" Behavior**:
```julia
# To effectively "disable" winsorization, use very high threshold
config = SignalProcessingConfig(
    winsorize_threshold = Float32(1000.0)  # Effectively disabled
)

# To effectively "disable" AGC, use fixed scale
config = SignalProcessingConfig(
    agc_min_scale = Int32(1),
    agc_max_scale = Int32(1),  # Fixed scale = no AGC effect
    agc_alpha = Float32(0.0)   # No adaptation
)
```

But in practice, these features should **always be enabled** for proper signal processing.

# Flow control configuration (from FlowControlConfig.jl, simplified)
struct FlowControlConfig
    delay_mode::DelayMode        # NO_DELAY, FIXED_DELAY, ADAPTIVE_DELAY
    fixed_delay_ms::Float64      # Milliseconds between ticks
    enable_timing_validation::Bool
    timing_tolerance_ms::Int32
end

# Channel configuration
struct ChannelConfig
    # Buffer sizes per consumer type
    priority_buffer_size::Int32
    standard_buffer_size::Int32
    
    # Backpressure
    enable_backpressure::Bool
    drop_on_overflow::Bool       # Drop messages vs. block
    overflow_warning_threshold::Float32  # Warn at X% full
end

# Performance targets
struct PerformanceConfig
    target_latency_us::Int32
    max_latency_us::Int32
    target_throughput_tps::Float32
    max_memory_mb::Float32
end
```

### TOML Configuration File Specification

**Simplified for Tick Processing** (compared to ModernConfigSystem's 800+ line filter-bank configs)

**File Location**: `config/pipeline/[name].toml`

**Example**: `config/pipeline/production.toml`

```toml
# =============================================================================
# PIPELINE METADATA
# =============================================================================
[metadata]
name = "production"
description = "Production tick processing pipeline"
version = "1.0"
created = "2025-10-03T12:00:00"

# =============================================================================
# SIGNAL PROCESSING (TickHotLoopF32 - HARD-WIRED, NO CONDITIONALS)
# =============================================================================
[signal_processing]
# PERFORMANCE CRITICAL: All features are ALWAYS ENABLED
# No enable/disable flags - eliminates branching in hot loop
# Normalization, winsorization, AGC, and QUAD-4 are hard-wired ON

# Normalization (ALWAYS ACTIVE)
normalization_method = "ema"  # "ema", "sma", or "fixed"

# Winsorization (ALWAYS ACTIVE) - outlier clipping
winsorize_threshold = 3.0  # Standard deviations

# AGC (ALWAYS ACTIVE) - Automatic Gain Control
agc_alpha = 0.0625          # EMA coefficient (1/16)
agc_min_scale = 4
agc_max_scale = 50
agc_guard_factor = 7

# Price validation (ALWAYS ACTIVE)
min_price_ticks = 40000     # YM futures minimum
max_price_ticks = 43000     # YM futures maximum
max_price_jump_ticks = 50   # Maximum tick-to-tick jump

# NOTE: QUAD-4 rotation is ALWAYS ENABLED (hard-wired in code)
# No configuration flag - always performs 4-phase rotation

# =============================================================================
# FLOW CONTROL
# =============================================================================
[flow_control]
delay_mode = "FIXED_DELAY"  # "NO_DELAY", "FIXED_DELAY", "ADAPTIVE_DELAY"
fixed_delay_ms = 1.0        # Milliseconds between ticks
enable_timing_validation = true
timing_tolerance_ms = 10

# =============================================================================
# CHANNEL CONFIGURATION
# =============================================================================
[channels]
# Buffer sizes
priority_buffer_size = 4096
standard_buffer_size = 2048

# Backpressure
enable_backpressure = true
drop_on_overflow = true     # Drop messages on overflow (standard consumers only)
overflow_warning_threshold = 0.90  # Warn at 90% full

# =============================================================================
# PERFORMANCE TARGETS
# =============================================================================
[performance]
target_latency_us = 500       # Target per-tick latency
max_latency_us = 1000         # Maximum acceptable latency
target_throughput_tps = 10000.0
max_memory_mb = 512.0

# =============================================================================
# MONITORING (Optional)
# =============================================================================
[monitoring]
enable_metrics = true
metrics_interval_ms = 100
enable_logging = true
log_level = "INFO"
```

### Key Differences from ModernConfigSystem

| Aspect | ModernConfigSystem | PipelineConfig |
|--------|-------------------|----------------|
| **Purpose** | GA-evolved filter banks | Tick processing pipeline |
| **Complexity** | 800+ lines, 10+ structs | ~200 lines, 5 structs |
| **Domain Concepts** | GA, PLL, Fibonacci periods, Q factors | Ticks, normalization, AGC, channels |
| **Configuration Size** | Large TOML (100+ parameters) | Small TOML (~30 parameters) |
| **Dependencies** | Coupled to filter bank internals | Independent, reusable |
| **Use Case** | Specific to main application | General tick processing |

### Loading Configuration

**Simplified API**:
```julia
# Load from TOML
config = load_pipeline_config("production")

# Create programmatically
config = PipelineConfig(
    pipeline_name = "test",
    signal_processing = SignalProcessingConfig(
        agc_enabled = true,
        agc_alpha = 0.0625
    ),
    flow_control = FlowControlConfig(
        delay_mode = FIXED_DELAY,
        fixed_delay_ms = 1.0
    )
)

# Use defaults
config = create_default_pipeline_config()
```

### Integration with Main Application

Applications using the tick pipeline package **can still use ModernConfigSystem.jl** for their filter bank configurations:

```julia
# In main application that uses both systems

# Load filter bank config (ModernConfigSystem)
filter_config = ModernConfigSystem.load_filter_config("pll_enhanced")

# Load tick pipeline config (PipelineConfig)
pipeline_config = TickDataPipeline.load_pipeline_config("production")

# Start tick pipeline
handle = start_tick_pipeline(
    tick_file_path = filter_config.io.input_file,  # Can reference filter config
    config = pipeline_config  # Use pipeline config
)

# Subscribe filter bank as consumer
subscribe_consumer(handle, :priority) do msg
    # Process using filter_config parameters
    process_with_filter_bank(msg, filter_config)
end
```

**Clear Separation of Concerns**:
- **PipelineConfig** → Tick acquisition and preprocessing
- **ModernConfigSystem** → Filter bank evolution and signal analysis (consumer-side)

### Preset Configurations

Simple, focused presets for tick processing:

1. **`default.toml`** - Balanced settings
2. **`production.toml`** - High-performance
3. **`testing.toml`** - Fast testing with validation
4. **`low_latency.toml`** - Minimal latency priority
5. **`debug.toml`** - Verbose logging

**No need for**: GA presets, PLL variants, filter period combinations (those belong in ModernConfigSystem for the consuming application).

### TOML Configuration File Specification

**File Location**: `config/pipeline/[name].toml`

**Complete Example**: `config/pipeline/production.toml`

```toml
# =============================================================================
# PIPELINE METADATA
# =============================================================================
[metadata]
name = "production"
description = "Production tick processing pipeline configuration"
version = "1.0"
created = "2025-10-03T12:00:00"

# =============================================================================
# PROCESSING CONFIGURATION
# =============================================================================
[processing]
# TickHotLoopF32 Signal Processing Parameters
enable_normalization = true
enable_winsorization = true
winsorize_threshold = 3.0  # Standard deviations for outlier clipping

# AGC (Automatic Gain Control) Parameters
agc_enabled = true
agc_alpha = 0.0625          # EMA coefficient for AGC (1/16)
agc_min_scale = 4           # Minimum AGC scale factor
agc_max_scale = 50          # Maximum AGC scale factor (matches max_jump)
agc_guard_factor = 7        # AGC guard factor for stability

# Price Range Validation
min_price_ticks = 40000     # Minimum valid price (YM range)
max_price_ticks = 43000     # Maximum valid price (YM range)
max_price_jump_ticks = 50   # Maximum allowed tick-to-tick jump

# QUAD-4 Rotation
quad4_enabled = true        # Enable QUAD-4 phase rotation

# =============================================================================
# FLOW CONTROL CONFIGURATION
# =============================================================================
[flow_control]
# Delay Mode: "NO_DELAY", "FIXED_DELAY", "ADAPTIVE_DELAY"
delay_mode = "FIXED_DELAY"

# Fixed Delay Settings
fixed_delay_ms = 1.0        # Milliseconds between ticks (0.0 = maximum speed)

# Adaptive Delay Settings (if delay_mode = "ADAPTIVE_DELAY")
target_throughput_tps = 1000.0    # Target ticks per second
adaptive_adjustment_rate = 0.1     # Rate of delay adjustment

# Timing Validation
enable_timing_validation = true
timing_tolerance_ms = 10    # Allowed timing variance

# =============================================================================
# PERFORMANCE TARGETS
# =============================================================================
[performance]
# Latency Targets (microseconds)
target_latency_us = 500           # Target end-to-end latency per tick
max_latency_us = 1000             # Maximum acceptable latency
warning_latency_us = 800          # Warning threshold

# Throughput Targets
target_throughput_tps = 10000.0   # Target ticks per second
min_throughput_tps = 5000.0       # Minimum acceptable throughput

# Memory Limits
max_memory_mb = 512.0             # Maximum memory usage
memory_warning_mb = 400.0         # Memory warning threshold

# Emergency Thresholds
emergency_latency_multiplier = 2.0      # Emergency if latency > target * multiplier
emergency_memory_threshold_mb = 480.0   # Emergency memory threshold

# =============================================================================
# CONSUMER CONFIGURATION
# =============================================================================
[consumers]
# Maximum number of concurrent consumers
max_consumers = 10

# Enable/Disable Specific Consumers
enable_priority_consumer = true
enable_monitoring_consumer = true
enable_alerting_consumer = true
enable_analytics_consumer = false

# Buffer Sizes (per consumer type)
priority_buffer_size = 4096         # Priority consumer (production filter)
standard_buffer_size = 2048         # Standard consumers
monitoring_buffer_size = 1024       # Monitoring consumer
alerting_buffer_size = 512          # Alerting consumer

# Backpressure Configuration
backpressure_enabled = true
backpressure_warning_threshold = 90    # Warn when buffer 90% full
backpressure_critical_threshold = 95   # Critical when buffer 95% full
backpressure_drop_policy = "drop_oldest"  # "drop_oldest" or "drop_newest"

# Consumer Health Monitoring
enable_consumer_health_monitoring = true
health_check_interval_ms = 1000    # Check consumer health every second
max_consumer_lag_ms = 5000         # Max acceptable consumer lag

# =============================================================================
# MONITORING CONFIGURATION
# =============================================================================
[monitoring]
# Metrics Collection
enable_metrics_collection = true
metrics_collection_interval_ms = 100   # Collect metrics every 100ms
metrics_retention_minutes = 60         # Keep metrics for 1 hour

# Performance Monitoring
enable_latency_tracking = true
enable_throughput_tracking = true
enable_memory_tracking = true

# Latency Percentiles to Track
latency_percentiles = [50, 90, 95, 99, 99.9]

# Alerting
enable_alerting = true
alert_on_latency_violation = true
alert_on_throughput_violation = true
alert_on_memory_violation = true
alert_on_consumer_failure = true

# Alert Thresholds
alert_cooldown_seconds = 60        # Minimum time between duplicate alerts

# Logging
enable_performance_logging = true
log_level = "INFO"                 # "DEBUG", "INFO", "WARN", "ERROR"
log_file = "logs/pipeline.log"
log_rotation_size_mb = 100

# =============================================================================
# TIMESTAMP ENCODING CONFIGURATION
# =============================================================================
[timestamp_encoding]
# Encoding scheme for timestamp Int64 conversion
encoding_scheme = "ASCII_8BIT"     # Use 8-bit ASCII character codes
validation_enabled = true          # Validate encoding/decoding
store_original = false             # Don't store original string (save memory)

# =============================================================================
# CHANNEL CONFIGURATION
# =============================================================================
[channels]
# Channel behavior
channel_type = "buffered"          # "buffered" or "unbuffered"
enable_channel_stats = true        # Track channel statistics

# Overflow Behavior
overflow_policy = "block_priority_drop_standard"  # Priority never drops, standard drops
overflow_warning_enabled = true
overflow_log_frequency = 100       # Log every 100 overflow events

# =============================================================================
# TESTING AND DEBUGGING
# =============================================================================
[testing]
# Test Mode Settings
enable_test_mode = false
test_tick_limit = 10000            # Limit ticks in test mode
test_validation_strict = true      # Strict validation in test mode

# Debug Settings
enable_debug_output = false
debug_output_interval = 1000       # Output debug info every N ticks
debug_trace_signals = false        # Trace signal processing
debug_trace_channels = false       # Trace channel operations

# Profiling
enable_profiling = false
profile_output_file = "profile_results.json"

# =============================================================================
# FILE I/O CONFIGURATION
# =============================================================================
[io]
# Input Validation
validate_tick_format = true
skip_malformed_records = true      # Skip vs. error on malformed ticks
malformed_record_limit = 100       # Max malformed records before stopping

# Output Settings
save_processing_stats = true
stats_output_file = "data/processing_stats.jld2"
save_metrics_history = true
metrics_output_file = "data/metrics_history.jld2"

# Compression
enable_compression = true
compression_level = 6              # 1-9, higher = more compression

# =============================================================================
# RECOVERY AND CHECKPOINTING
# =============================================================================
[recovery]
# Checkpoint Settings
enable_checkpointing = false
checkpoint_interval_ticks = 10000   # Checkpoint every N ticks
checkpoint_directory = "data/checkpoints"
max_checkpoints_retained = 5

# Recovery Settings
enable_auto_recovery = false
recovery_on_failure = false

# =============================================================================
# GPU CONFIGURATION (Future Enhancement)
# =============================================================================
[gpu]
# GPU Processing
enable_gpu = false
gpu_device_id = 0
gpu_batch_size = 1024

# GPU Memory
gpu_memory_fraction = 0.8          # Use 80% of available GPU memory
```

### Loading Configuration

**From TOML File**:
```julia
using TickDataPipeline

# Load named configuration
config = load_pipeline_config("production")  # Looks for config/pipeline/production.toml

# Load from specific path
config = load_pipeline_config("config/custom/my_pipeline.toml")

# Load with validation disabled (faster, for testing)
config = load_pipeline_config("production", validate=false)
```

**Programmatic Creation**:
```julia
# Create minimal configuration
config = PipelineConfig(
    pipeline_name = "test_pipeline",
    processing = ProcessingConfig(
        enable_normalization = true,
        agc_enabled = true
    ),
    flow_control = FlowControlConfig(
        delay_mode = FIXED_DELAY,
        fixed_delay_ms = 1.0
    )
)

# Create with defaults
config = create_default_pipeline_config()

# Create production-optimized configuration
config = create_production_config(
    name = "production",
    target_latency_us = 500,
    target_throughput_tps = 10000.0
)
```

### Validation

Configuration validation ensures settings are consistent and within valid ranges:

```julia
# Validate configuration
is_valid = validate_pipeline_config(config)

# Validation checks:
# - Latency targets (max > target > 0)
# - Throughput targets (> 0)
# - Memory limits (> 0)
# - Buffer sizes (> 0)
# - Consumer count (> 0, <= max_consumers)
# - File paths exist
# - Encoding parameters valid
# - Flow control settings consistent
```

### Configuration Inheritance

Create specialized configurations by modifying base configurations:

```julia
# Start with production config
base_config = load_pipeline_config("production")

# Create test variant
test_config = PipelineConfig(
    base_config,
    pipeline_name = "production_test",
    flow_control = FlowControlConfig(
        base_config.flow_control,
        fixed_delay_ms = 10.0  # Slower for testing
    ),
    testing = TestingConfig(
        enable_test_mode = true,
        test_tick_limit = 1000
    )
)
```

### Available Preset Configurations

The package should include these preset configurations:

1. **`default.toml`** - Balanced settings for general use
2. **`production.toml`** - High-performance production settings
3. **`development.toml`** - Development with verbose logging
4. **`testing.toml`** - Fast testing with reduced tick counts
5. **`high_latency.toml`** - Optimized for high-throughput, relaxed latency
6. **`low_latency.toml`** - Optimized for minimal latency
7. **`debug.toml`** - Maximum debugging output

### Environment Variable Overrides

Allow runtime overrides via environment variables:

```bash
# Override specific settings
export TICK_PIPELINE_DELAY_MS=2.0
export TICK_PIPELINE_MAX_LATENCY_US=2000
export TICK_PIPELINE_LOG_LEVEL=DEBUG

julia> using TickDataPipeline
julia> handle = start_tick_pipeline(
    tick_file_path = "data/ticks.txt",
    config = load_pipeline_config("production")  # Settings overridden by env vars
)
```

### Primary API Function

```julia
function start_tick_pipeline(;
    tick_file_path::String,
    num_ticks::Union{Int, Nothing} = nothing,  # nothing = process all
    tick_delay_ms::Float64 = 0.0,
    buffer_sizes::Dict{Symbol, Int} = Dict(
        :priority => 2048,
        :standard => 1024
    ),
    persistent_consumers::Vector{Symbol} = Symbol[],  # Auto-subscribe these consumers
    config::Union{PipelineConfig, Nothing} = nothing
)::TickPipelineHandle
```

**Parameters**:
- `tick_file_path`: Full path to the tick data file
- `num_ticks`: Number of ticks to process (nothing = all ticks in file)
- `tick_delay_ms`: Delay in milliseconds between tick transmissions
- `buffer_sizes`: Channel buffer sizes for priority and standard consumers
- `persistent_consumers`: Vector of consumer types to automatically create channels for (e.g., `[:monitoring, :alerting]`)
- `config`: Optional pipeline configuration object (loaded from TOML file or created programmatically)

**Returns**: `TickPipelineHandle` - Handle for controlling the pipeline

**Configuration Loading**:
```julia
# Option 1: Load from TOML file
config = load_pipeline_config("config/pipeline/default.toml")
handle = start_tick_pipeline(
    tick_file_path = "data/raw/YM 06-25.Last.txt",
    config = config
)

# Option 2: Use defaults (config = nothing)
handle = start_tick_pipeline(
    tick_file_path = "data/raw/YM 06-25.Last.txt",
    tick_delay_ms = 1.0  # Override specific settings
)

# Option 3: Create programmatically
config = PipelineConfig(
    pipeline_name = "production",
    max_latency_us = 1000,
    target_throughput_tps = 10000.0
)
handle = start_tick_pipeline(
    tick_file_path = "data/raw/YM 06-25.Last.txt",
    config = config
)
```

**Persistent Consumers Feature**:
The `persistent_consumers` parameter allows specification of consumers that should have channels pre-created and available for the lifetime of the pipeline, eliminating the need for explicit subscription:

```julia
# Example: Monitoring always available
handle = start_tick_pipeline(
    tick_file_path = "data/raw/YM 06-25.Last.txt",
    persistent_consumers = [:monitoring, :alerting],  # These channels always exist
    num_ticks = 10000
)

# Persistent channels are immediately available
monitoring_channel = get_consumer_channel(handle, :monitoring)
alerting_channel = get_consumer_channel(handle, :alerting)

# Start consuming without explicit subscription
@async while isopen(monitoring_channel)
    msg = take!(monitoring_channel)
    update_dashboard(msg)
end
```

### Pipeline Control Handle

```julia
struct TickPipelineHandle
    pipeline_task::Task                    # Asynchronous processing task
    priority_channel::Channel{BroadcastMessage}
    standard_channels::Dict{Symbol, Channel{BroadcastMessage}}  # Keyed by consumer type
    persistent_channels::Set{Symbol}       # Consumers with persistent subscriptions
    completion_callback::Union{Function, Nothing}
    
    # Control methods
    stop::Function                         # Stop pipeline gracefully
    pause::Function                        # Pause tick delivery
    resume::Function                       # Resume tick delivery
    status::Function                       # Get pipeline status
end
```

### Direct Channel Access (For Persistent Consumers)

For consumers specified in `persistent_consumers`, channels are pre-created and accessible without subscription:

```julia
"""
Get channel for a consumer type. 
For persistent consumers, returns the pre-created channel.
For non-persistent consumers, returns nothing unless subscribed.
"""
function get_consumer_channel(
    handle::TickPipelineHandle, 
    consumer_type::Symbol
)::Union{Channel{BroadcastMessage}, Nothing}
```

**Usage Pattern for Persistent Consumers**:
```julia
# Pipeline with persistent monitoring
handle = start_tick_pipeline(
    tick_file_path = "data/ticks.txt",
    persistent_consumers = [:monitoring, :alerting]
)

# Direct channel access (no subscription needed)
monitoring_ch = get_consumer_channel(handle, :monitoring)
alerting_ch = get_consumer_channel(handle, :alerting)

# Consume messages directly from channels
@async for msg in monitoring_ch
    process_monitoring(msg)
end

@async for msg in alerting_ch
    check_alerts(msg)
end
```

### Consumer Subscription API

```julia
function subscribe_consumer(
    handle::TickPipelineHandle,
    consumer_type::Symbol,  # :priority, :monitoring, :abtest, :simulated
    callback::Function      # Callback(message::BroadcastMessage) -> nothing
)::ConsumerHandle
```

**Consumer Callback Signature**:
```julia
function consumer_callback(message::BroadcastMessage)
    # Process tick data
    # This function should be non-blocking
end
```

### Completion Callback

```julia
function set_completion_callback(
    handle::TickPipelineHandle,
    callback::Function  # Callback(stats::PipelineStats) -> nothing
)
```

**Completion Callback Signature**:
```julia
function completion_callback(stats::PipelineStats)
    println("Pipeline completed:")
    println("  Total ticks processed: $(stats.total_ticks)")
    println("  Processing time: $(stats.elapsed_time_ms) ms")
    println("  Dropped messages: $(stats.dropped_messages)")
end
```

### Static Channel Access

For the single-channel use case, provide a static accessor:

```julia
function get_priority_channel()::Union{Channel{BroadcastMessage}, Nothing}
    # Returns the currently active priority channel
    # Returns nothing if no pipeline is running
end

function get_standard_channel(consumer_type::Symbol)::Union{Channel{BroadcastMessage}, Nothing}
    # Returns standard channel for specified consumer type
    # consumer_type ∈ [:monitoring, :abtest, :simulated]
end
```

**Rationale**: Since only one pipeline instance runs at a time, static accessors simplify consumer implementation.

## Pipeline Statistics

```julia
struct PipelineStats
    total_ticks::Int64
    ticks_processed::Int64
    ticks_dropped::Dict{Symbol, Int64}  # Per-consumer dropped count
    elapsed_time_ms::Float64
    average_tick_rate::Float64          # Ticks per second
    buffer_overflows::Dict{Symbol, Int64}
end

function get_pipeline_stats(handle::TickPipelineHandle)::PipelineStats
```

## Asynchronous Operation

The tick pipeline must operate asynchronously:

1. **Async Task**: `start_tick_pipeline()` launches a background Task
2. **Non-blocking**: Returns immediately with a handle
3. **Event-Driven**: Consumers receive on-tick events via callbacks
4. **Lifecycle**: Pipeline runs until:
   - All ticks processed (if `num_ticks` specified)
   - `stop()` called on handle
   - Critical error occurs

**Example Usage**:
```julia
# Start pipeline
handle = start_tick_pipeline(
    tick_file_path = "data/raw/YM 06-25.Last.txt",
    num_ticks = 10000,
    tick_delay_ms = 1.0
)

# Subscribe consumers
subscribe_consumer(handle, :priority) do message
    # Process priority tick
    process_production_filter(message)
end

subscribe_consumer(handle, :monitoring) do message
    # Process monitoring tick
    update_monitoring_dashboard(message)
end

# Set completion callback
set_completion_callback(handle) do stats
    println("Processing complete: $(stats.total_ticks) ticks")
end

# Pipeline runs asynchronously...
# Can do other work here

# Wait for completion (optional)
wait(handle.pipeline_task)
```

## Package Structure

### Proposed Directory Layout

```
TickDataPipeline.jl/
├── Project.toml
├── src/
│   ├── TickDataPipeline.jl          # Main module file
│   ├── VolumeExpansion.jl           # Stage 1: Volume expansion with Channel{String}
│   ├── FlowControlConfig.jl         # Stage 2: Flow control configuration
│   ├── TickHotLoopF32.jl            # Stage 3: Signal processing
│   ├── TripleSplitSystem.jl         # Stage 4: Channel broadcast system
│   ├── BroadcastMessage.jl          # GPU-compatible message structure
│   ├── PipelineOrchestrator.jl      # Core: process_single_tick_through_pipeline!
│   ├── PipelineConfig.jl            # Configuration management
│   └── PipelineStats.jl             # Statistics and monitoring
├── test/
│   ├── runtests.jl
│   ├── test_volume_expansion.jl
│   ├── test_flow_control.jl
│   ├── test_signal_processing.jl
│   ├── test_broadcast_system.jl
│   └── test_pipeline_orchestration.jl  # Test complete pipeline flow
├── examples/
│   ├── basic_usage.jl
│   ├── custom_consumers.jl
│   ├── persistent_monitoring.jl
│   └── pipeline_metrics.jl
└── README.md
```

### Files from Original Application

**Included in Package** (Producer-side):
- `VolumeExpansion.jl` - Volume expansion logic with channel streaming
- `FlowControlConfig.jl` - Flow control configuration (**simplified version**)
- `TickHotLoopF32.jl` - Complex signal processing
- `TripleSplitSystem.jl` - Core channel broadcast mechanism
- `BroadcastMessage.jl` - Message structure definition
- **`PipelineOrchestrator.jl`** - NEW: Core orchestration logic (extracted from EndToEndPipeline.jl)
  - Contains `process_single_tick_through_pipeline!()` function
  - Main pipeline loop with channel integration
  - Per-tick metrics collection
  - Stage timing and performance tracking
- **`PipelineConfig.jl`** - NEW: **Simplified** pipeline-specific configuration system
  - NOT the full ModernConfigSystem.jl (too GA/filter-bank specific)
  - Focused on tick processing pipeline needs only
  - No PLL, GA, or filter bank parameters

**NOT Included** (Consumer-side):
- `TripleSplitManager.jl` - Consumer lifecycle management (application-specific)
- `ProductionFilterConsumer.jl` - Production filter implementation (application-specific)
- `MonitoringConsumer.jl` - Monitoring logic (application-specific)
- `TripleSplitMetrics_addition.jl` - Metrics collection (application-specific)
- `ABTestManager.jl` - A/B testing framework (application-specific)
- `SimulatedLiveEvaluator.jl` - Simulation consumer (application-specific)

**NOT Included** (Too specialized for GA/filter applications):
- `ModernConfigSystem.jl` - **Excluded** (GA/PLL/filter-bank specific)
  - Contains GA initialization defaults
  - PLL configuration
  - Fibonacci filter periods
  - Filter-specific parameters (Q factor, ring decay, etc.)
  - Individual filter overrides
  - **Replace with simplified PipelineConfig.jl** for tick processing only

**Rationale**: 
- The package provides the tick processing pipeline infrastructure only
- ModernConfigSystem.jl is tightly coupled to GA-evolved filter banks, PLL processing, and Fibonacci periods
- The tick pipeline needs a **simpler, focused configuration system** for:
  - Flow control (tick delays)
  - Signal processing parameters (normalization, winsorization, AGC)
  - Channel buffers
  - Performance targets
- Consumers are domain-specific and should be implemented by applications using this package
- Applications using the tick pipeline can use their own configuration systems (including ModernConfigSystem.jl if needed)

## Installation and Usage

### As a Julia Package

```julia
# Install from registry (future)
using Pkg
Pkg.add("TickDataPipeline")

# Or install from local development
Pkg.develop(path="/path/to/TickDataPipeline.jl")

# Use in application
using TickDataPipeline

handle = start_tick_pipeline(
    tick_file_path = "data/ticks.txt",
    tick_delay_ms = 1.0
)
```

### Integration Example

```julia
module MyTradingApp

using TickDataPipeline

function main()
    # Configure pipeline with persistent monitoring/alerting
    handle = start_tick_pipeline(
        tick_file_path = "data/raw/YM 06-25.Last.txt",
        num_ticks = 100000,
        tick_delay_ms = 0.5,
        buffer_sizes = Dict(
            :priority => 4096,
            :standard => 2048
        ),
        persistent_consumers = [:monitoring, :alerting]  # Always available
    )
    
    # Subscribe production filter (priority consumer) - still needs subscription
    subscribe_consumer(handle, :priority) do msg
        # High-priority processing
        process_for_production(msg.complex_signal, msg.price_delta)
    end
    
    # Persistent monitoring - direct channel access, no subscription
    monitoring_channel = get_consumer_channel(handle, :monitoring)
    @async for msg in monitoring_channel
        # Monitoring runs independently
        if msg.status_flag & 0x01 != 0
            log_anomaly(msg)
        end
        update_dashboard(msg)
    end
    
    # Persistent alerting - direct channel access
    alerting_channel = get_consumer_channel(handle, :alerting)
    @async for msg in alerting_channel
        check_price_alerts(msg.raw_price, msg.price_delta)
    end
    
    # Wait for completion
    wait(handle.pipeline_task)
end

end # module
```

## Key Design Decisions

### 1. Separate Channels for Priority Handling
- **Decision**: Each consumer type has its own dedicated Channel
- **Rationale**: ProductionFilterConsumer cannot be delayed by other consumers' backpressure
- **Implementation**: Priority channel guaranteed delivery; standard channels drop on overflow

### 2. Timestamp Encoding
- **Decision**: Convert ASCII timestamp to Int64 using 8-bit ASCII character encoding
- **Rationale**: Compact representation, reversible decoding, fits in Int64
- **Trade-off**: Slight encoding/decoding overhead vs. memory efficiency

### 3. GPU Compatibility
- **Decision**: All BroadcastMessage fields must be GPU-compatible primitive types
- **Rationale**: 
  - Enable GPU processing of tick data in downstream consumers
  - Removed String type (config_name) to maintain GPU compatibility
  - All fields are primitive types (Int32, Int64, Float32, ComplexF32, UInt8)
- **Impact**: BroadcastMessage can be directly passed to CUDA kernels

### 4. Raw Price Preservation
- **Decision**: Include original "last" price as Int32 in BroadcastMessage
- **Rationale**:
  - Preserves unmodified price data before any transformations
  - Enables downstream consumers to perform their own price analysis
  - Required for price alert systems and monitoring
- **Source**: Extracted from tick file during VolumeExpansion stage

### 5. Persistent Consumer Subscriptions
- **Decision**: Support pre-created channels via `persistent_consumers` parameter
- **Rationale**:
  - Monitoring and alerting systems need continuous access without re-subscription
  - Some consumers should persist across pipeline restarts
  - Simplifies infrastructure for always-on monitoring applications
- **Implementation**: Channels for persistent consumers created at pipeline startup

### 6. Consumer-Side Exclusion
- **Decision**: Consumer implementations NOT included in base package
- **Rationale**: 
  - Consumers are application-specific
  - Package focuses on data pipeline infrastructure
  - Allows flexibility in consumer implementation
  - Reduces package dependencies

### 7. Asynchronous Pipeline
- **Decision**: Pipeline runs as async Task with callback-based consumer notifications
- **Rationale**:
  - Non-blocking operation
  - Natural fit for event-driven processing
  - Allows concurrent consumer processing
  - Julia's Channel primitives handle synchronization

### 8. Dual Access Patterns
- **Decision**: Support both callback-based subscription and direct channel access
- **Rationale**:
  - Callbacks for transient consumers (ABTest, production filters)
  - Direct channel access for persistent infrastructure (monitoring, alerting)
  - Flexibility in consumer implementation patterns

## Performance Considerations

### Throughput Targets
- **Target**: Process 10,000+ ticks/second
- **Bottlenecks**: 
  - File I/O (mitigated by buffering)
  - Volume expansion (minimal overhead)
  - Channel operations (Julia's Channels are optimized)

### Memory Management
- **Buffer Sizing**: Configurable channel buffers prevent memory bloat
- **Message Structure**: Compact BroadcastMessage design (< 64 bytes)
- **Overflow Handling**: Drop messages on standard channels vs. blocking

### Latency Optimization
- **Priority Path**: Dedicated channel with no contention
- **Non-blocking Broadcast**: tryput!() for standard consumers
- **Minimal Locking**: Channel primitives handle synchronization

## Testing Strategy

### Unit Tests
- Volume expansion logic
- Timestamp encoding/decoding
- Flow control timing
- Signal processing (QUAD-4 rotation, normalization)
- Channel broadcast mechanics

### Integration Tests
- End-to-end pipeline with mock consumers
- Multi-consumer scenarios
- Backpressure and message dropping
- Priority vs. standard consumer behavior
- Completion callbacks

### Performance Tests
- Throughput benchmarks (ticks/second)
- Latency measurements (tick-to-consumer)
- Memory usage under load
- Buffer overflow behavior

## Documentation Requirements

### README.md
- Quick start guide
- Installation instructions
- Basic usage examples
- API reference summary

### API Documentation
- Docstrings for all public functions
- Parameter descriptions
- Return value specifications
- Usage examples

### Examples
- Basic single-consumer pipeline
- Multi-consumer setup
- Custom consumer implementation
- Error handling and recovery
- Performance tuning guide

## Migration Path

### Phase 1: Package Extraction
1. Extract source files to new package structure
2. Implement API layer
3. Add unit tests
4. Create basic documentation

### Phase 2: Enhancement
1. Add timestamp encoding to VolumeExpansion
2. Export normalization factor from TickHotLoopF32
3. Implement priority channel architecture
4. Add completion callbacks

### Phase 3: Integration
1. Update original application to use package
2. Implement consumer-side components in application
3. Performance testing and optimization
4. Final documentation

### Phase 4: Release
1. Package registration (if publishing to Julia registry)
2. Version tagging
3. CI/CD setup
4. Community feedback incorporation

## Open Questions - RESOLVED

### 1. **Error Handling** ✅ RESOLVED
**Decision**: Skip malformed tick records and continue processing

**Implementation**:
- Malformed records are silently skipped in VolumeExpansion
- Status flag (UInt8) in BroadcastMessage encodes any processing issues
- No pipeline interruption for malformed data
- Consumer can check status_flag to detect issues

```julia
# In VolumeExpansion.jl
function process_tick_line_simple(line::String)::Vector{String}
    if isempty(strip(line))
        return String[]  # Skip empty lines
    end
    
    if count(';', line) != 4
        return String[]  # Skip malformed - wrong number of fields
    end
    
    # Continue processing...
end
```

**Status Flag Encoding** (already in place):
```julia
# BroadcastMessage.status_flag bit meanings
const FLAG_OK = UInt8(0x00)           # No issues
const FLAG_MALFORMED = UInt8(0x01)    # Original record was malformed
const FLAG_HOLDLAST = UInt8(0x02)     # Price held from previous
const FLAG_CLIPPED = UInt8(0x04)      # Value was clipped/winsorized
const FLAG_AGC_LIMIT = UInt8(0x08)    # AGC hit limit
```

### 2. **Configuration Persistence** ✅ RESOLVED
**Decision**: Use TOML format for configuration files

**Implementation**:
- Configuration stored in `config/pipeline/*.toml`
- Load: `load_pipeline_config("production")` reads TOML
- Save: `save_pipeline_config(config, "config/pipeline/custom.toml")`
- No config_id in BroadcastMessage (keeps struct minimal and GPU-compatible)

**Rationale**: 
- TOML is human-readable and standard in Julia ecosystem
- No need for config tracking in BroadcastMessage (configuration is pipeline-level, not per-tick)
- Consumers that need config context can access PipelineConfig separately

### 3. **Logging** ✅ RESOLVED
**Decision**: Use Julia's Logging module, disabled by default for 100% quiet operation

**Implementation**:
```julia
using Logging

# Default: completely silent operation
const PIPELINE_LOGGER = NullLogger()

# Enable logging when needed
function enable_pipeline_logging(level::LogLevel = Logging.Info)
    global PIPELINE_LOGGER
    PIPELINE_LOGGER = ConsoleLogger(stderr, level)
end

# In pipeline code
@debug "Processing tick $tick_idx" _logger=PIPELINE_LOGGER
@info "Pipeline started" _logger=PIPELINE_LOGGER
@warn "Buffer near capacity" _logger=PIPELINE_LOGGER
@error "Critical failure" _logger=PIPELINE_LOGGER
```

**Usage**:
```julia
# Silent by default (production)
handle = start_tick_pipeline(tick_file_path = "data/ticks.txt")

# Enable logging for debugging
TickDataPipeline.enable_pipeline_logging(Logging.Debug)
handle = start_tick_pipeline(tick_file_path = "data/ticks.txt")
```

**Log Levels**:
- `Debug`: Detailed per-tick information
- `Info`: Pipeline lifecycle events (start, stop, completion)
- `Warn`: Performance degradation, buffer warnings
- `Error`: Critical failures

### 4. **Package Naming** ✅ RESOLVED
**Decision**: `TickDataPipeline.jl`

**Rationale**:
- Clear, descriptive name
- Indicates purpose: tick data processing pipeline
- Generic enough for reuse beyond YM futures
- Follows Julia package naming conventions

**Repository**: `TickDataPipeline.jl`
**Module**: `TickDataPipeline`
**Usage**: `using TickDataPipeline`

### 5. **Versioning** ✅ RESOLVED
**Decision**: Start with v0.1.0 (development)

**Version Progression**:
- **v0.1.0**: Initial development release
  - Core functionality: VolumeExpansion, TickHotLoopF32, TripleSplitSystem
  - Basic testing and examples
  - API subject to change
  
- **v0.2.0**: Feature additions
  - Persistent consumers
  - Enhanced monitoring
  - Performance optimizations
  
- **v0.9.0**: Pre-release candidate
  - API stabilization
  - Comprehensive testing
  - Documentation complete
  
- **v1.0.0**: Production release
  - Stable API
  - Performance guarantees
  - Full documentation
  - Comprehensive test suite

**Semantic Versioning**:
- **Major (X.0.0)**: Breaking API changes
- **Minor (0.X.0)**: New features, backward compatible
- **Patch (0.0.X)**: Bug fixes, no API changes

### 6. **Persistent Consumer Lifecycle** ✅ RESOLVED
**Decision**: Auto-restart persistent consumers with exponential backoff

**Implementation**:
```julia
struct ConsumerRestartPolicy
    enable_auto_restart::Bool
    max_restart_attempts::Int32
    initial_backoff_ms::Int32
    max_backoff_ms::Int32
    backoff_multiplier::Float32
end

# Default restart policy for persistent consumers
const DEFAULT_RESTART_POLICY = ConsumerRestartPolicy(
    enable_auto_restart = true,
    max_restart_attempts = Int32(5),
    initial_backoff_ms = Int32(100),   # Start with 100ms
    max_backoff_ms = Int32(60000),     # Cap at 60 seconds
    backoff_multiplier = Float32(2.0)  # Exponential backoff
)

function monitor_persistent_consumer!(
    channel::Channel{BroadcastMessage},
    consumer_id::Symbol,
    callback::Function,
    restart_policy::ConsumerRestartPolicy
)
    attempt = Int32(0)
    backoff_ms = restart_policy.initial_backoff_ms
    
    while attempt < restart_policy.max_restart_attempts
        try
            # Run consumer loop
            for msg in channel
                callback(msg)
            end
            break  # Normal termination
            
        catch e
            attempt += 1
            @warn "Persistent consumer $consumer_id failed (attempt $attempt): $e"
            
            if attempt >= restart_policy.max_restart_attempts
                @error "Persistent consumer $consumer_id exceeded max restart attempts"
                break
            end
            
            # Exponential backoff
            sleep(backoff_ms / 1000.0)
            backoff_ms = min(
                Int32(backoff_ms * restart_policy.backoff_multiplier),
                restart_policy.max_backoff_ms
            )
            
            @info "Restarting persistent consumer $consumer_id after $(backoff_ms)ms backoff"
        end
    end
end
```

**Usage**:
```julia
# Persistent consumer with auto-restart
handle = start_tick_pipeline(
    tick_file_path = "data/ticks.txt",
    persistent_consumers = [:monitoring]
)

# Monitoring consumer will auto-restart on failure
# With backoff: 100ms, 200ms, 400ms, 800ms, 1600ms (max 5 attempts)
```

**Restart Behavior**:
- **Attempt 1**: Immediate restart after 100ms
- **Attempt 2**: Restart after 200ms
- **Attempt 3**: Restart after 400ms
- **Attempt 4**: Restart after 800ms
- **Attempt 5**: Restart after 1600ms
- **After 5 failures**: Consumer permanently stopped, error logged

**Override Restart Policy**:
```julia
custom_policy = ConsumerRestartPolicy(
    enable_auto_restart = true,
    max_restart_attempts = Int32(10),
    initial_backoff_ms = Int32(1000),
    max_backoff_ms = Int32(300000),  # 5 minutes max
    backoff_multiplier = Float32(1.5)
)

configure_restart_policy!(handle, :monitoring, custom_policy)
```

### 7. **GPU Data Transfer** ✅ RESOLVED
**Decision**: Leave to consumer implementation

**Rationale**:
- BroadcastMessage is already GPU-compatible (primitive types only)
- Different consumers may use different GPU frameworks (CUDA.jl, AMDGPU.jl, Metal.jl)
- Transfer strategy varies by use case (individual transfers vs. batching)
- Keeps package dependencies minimal

**Consumer-Side GPU Transfer** (example):
```julia
using CUDA

# Consumer handles GPU transfer
subscribe_consumer(handle, :priority) do msg
    # Transfer to GPU
    gpu_signal = CuArray([msg.complex_signal])
    gpu_price = CuArray([msg.raw_price])
    gpu_delta = CuArray([msg.price_delta])
    
    # Process on GPU
    result = process_on_gpu(gpu_signal, gpu_price, gpu_delta)
    
    # Result back to CPU if needed
    cpu_result = Array(result)
end

# Or batch transfer for efficiency
batch = BroadcastMessage[]
subscribe_consumer(handle, :priority) do msg
    push!(batch, msg)
    
    if length(batch) >= 1024
        # Batch transfer to GPU
        gpu_batch = transfer_batch_to_gpu(batch)
        process_batch_on_gpu(gpu_batch)
        empty!(batch)
    end
end
```

**Helper Functions** (optional, in examples/):
```julia
# Example helper (not in core package)
function create_gpu_message_arrays(messages::Vector{BroadcastMessage})
    n = length(messages)
    
    # Pre-allocate GPU arrays
    gpu_timestamps = CuArray{Int64}(undef, n)
    gpu_prices = CuArray{Int32}(undef, n)
    gpu_deltas = CuArray{Int32}(undef, n)
    gpu_signals = CuArray{ComplexF32}(undef, n)
    
    # Copy data
    for (i, msg) in enumerate(messages)
        gpu_timestamps[i] = msg.timestamp
        gpu_prices[i] = msg.raw_price
        gpu_deltas[i] = msg.price_delta
        gpu_signals[i] = msg.complex_signal
    end
    
    return (
        timestamps = gpu_timestamps,
        prices = gpu_prices,
        deltas = gpu_deltas,
        signals = gpu_signals
    )
end
```

**Documentation Note**: Include GPU transfer examples in `examples/gpu_consumer.jl` but don't include GPU dependencies in core package.

---

**All Open Questions Have Been Resolved** ✅

The specification is now complete with clear decisions on all implementation details.

---

**Document Version**: 1.0  
**Date**: 2025-10-02  
**Author**: System Architect  
**Status**: Ready for Implementation Review
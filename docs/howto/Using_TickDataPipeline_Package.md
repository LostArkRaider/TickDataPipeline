# Using TickDataPipeline Package in Your Project

**TickDataPipeline v0.1.0**

---

## Table of Contents

1. [Installation](#installation)
2. [Quick Start](#quick-start)
3. [Package Architecture](#package-architecture)
4. [Basic Usage Patterns](#basic-usage-patterns)
5. [Configuration](#configuration)
6. [Advanced Usage](#advanced-usage)
7. [Multi-threaded Applications](#multi-threaded-applications)
8. [API Reference](#api-reference)

---

## Installation

### Option 1: Local Development Package

Add TickDataPipeline as a local dependency to your project:

```julia
# From your project directory
using Pkg
Pkg.develop(path="/path/to/TickDataPipeline")
```

Or add to your `Project.toml`:

```toml
[deps]
TickDataPipeline = "..."

[sources]
TickDataPipeline = {path = "/path/to/TickDataPipeline"}
```

### Option 2: Direct Include (For Testing)

```julia
# Add to LOAD_PATH
push!(LOAD_PATH, "/path/to/TickDataPipeline/src")
using TickDataPipeline
```

### Verify Installation

```julia
using TickDataPipeline

# Check exported functions
println(names(TickDataPipeline))
```

---

## Quick Start

### Minimal Example: Process Tick File

```julia
using TickDataPipeline

# Create default configuration
config = create_default_config()

# Create broadcasting system
split_mgr = create_triple_split_manager()

# Subscribe a consumer
consumer = subscribe_consumer!(split_mgr, "my_consumer", MONITORING, Int32(4096))

# Create pipeline manager
pipeline_mgr = create_pipeline_manager(config, split_mgr)

# Process ticks
@async run_pipeline!(pipeline_mgr, max_ticks=Int64(10000))

# Consume messages
for msg in consumer.channel
    println("Tick $(msg.tick_idx): price=$(msg.raw_price), I/Q=$(msg.complex_signal)")
end
```

---

## Package Architecture

### Core Components

```
TickDataPipeline
├── BroadcastMessage       # Data structure for processed ticks
├── VolumeExpansion        # Stage 1: Tick streaming & volume expansion
├── TickHotLoopF32         # Stage 2: Signal processing (AGC, QUAD-4)
├── TripleSplitSystem      # Stage 3: Multi-consumer broadcasting
├── PipelineConfig         # Configuration management
└── PipelineOrchestrator   # Pipeline coordination
```

### Data Flow

```
Raw Tick File
    ↓
VolumeExpansion (stream_expanded_ticks)
    ↓
BroadcastMessage (pre-populated: tick_idx, timestamp, raw_price, price_delta)
    ↓
TickHotLoopF32 (process_tick_signal!)
    ↓
BroadcastMessage (updated: complex_signal, normalization, status_flag)
    ↓
TripleSplitSystem (broadcast_to_all!)
    ↓
Consumer Channels (PRIORITY, MONITORING, ANALYTICS)
```

---

## Basic Usage Patterns

### Pattern 1: Simple Tick Consumer

Process ticks and extract data:

```julia
using TickDataPipeline

function process_ticks(tick_file::String; max_ticks::Int64=0)
    # Setup
    config = PipelineConfig(tick_file_path=tick_file)
    split_mgr = create_triple_split_manager()
    consumer = subscribe_consumer!(split_mgr, "processor", MONITORING, Int32(4096))
    pipeline_mgr = create_pipeline_manager(config, split_mgr)

    # Storage
    results = BroadcastMessage[]

    # Start pipeline
    pipeline_task = @async run_pipeline!(pipeline_mgr, max_ticks=max_ticks)

    # Consume messages
    consumer_task = @async begin
        for msg in consumer.channel
            push!(results, msg)
        end
    end

    # Wait for completion
    wait(pipeline_task)
    sleep(0.1)  # Allow consumer to drain
    close(consumer.channel)
    wait(consumer_task)

    return results
end

# Usage
messages = process_ticks("data/raw/ticks.txt", max_ticks=Int64(100000))
println("Processed $(length(messages)) ticks")
```

### Pattern 2: Asynchronous Real-time Processing

Process ticks asynchronously without blocking:

```julia
using TickDataPipeline

function start_realtime_processing(tick_file::String)
    config = PipelineConfig(tick_file_path=tick_file)
    split_mgr = create_triple_split_manager()
    consumer = subscribe_consumer!(split_mgr, "realtime", MONITORING, Int32(4096))
    pipeline_mgr = create_pipeline_manager(config, split_mgr)

    # Start pipeline (non-blocking)
    pipeline_task = @async run_pipeline!(pipeline_mgr)

    # Process asynchronously (non-blocking)
    processing_task = @async begin
        for msg in consumer.channel
            # Your processing logic
            if msg.tick_idx % 1000 == 0
                println("Tick $(msg.tick_idx): I=$(real(msg.complex_signal)), Q=$(imag(msg.complex_signal))")
            end

            # Can do other work here (update UI, log, calculate indicators, etc.)
            update_indicators(msg)
            check_trading_signals(msg)
        end
        println("Processing complete")
    end

    # Return tasks for control (can wait, check status, etc.)
    return (pipeline_task, processing_task)
end

# Usage - function returns immediately, processing happens in background
(pipeline, processor) = start_realtime_processing("data/raw/ticks.txt")

# Can do other work while processing
println("Pipeline running in background...")

# Wait for completion when needed
wait(pipeline)
wait(processor)
```

### Pattern 3: Multiple Consumers

Use different consumer types for different purposes:

```julia
using TickDataPipeline

function multi_consumer_pipeline(tick_file::String)
    config = PipelineConfig(tick_file_path=tick_file)
    split_mgr = create_triple_split_manager()

    # Priority consumer: Trading logic (blocking, guaranteed delivery)
    trading_consumer = subscribe_consumer!(split_mgr, "trading", PRIORITY, Int32(2048))

    # Monitoring consumer: Logging (non-blocking, can drop if full)
    logging_consumer = subscribe_consumer!(split_mgr, "logging", MONITORING, Int32(8192))

    # Analytics consumer: Research (non-blocking, larger buffer)
    analytics_consumer = subscribe_consumer!(split_mgr, "analytics", ANALYTICS, Int32(16384))

    pipeline_mgr = create_pipeline_manager(config, split_mgr)

    # Start pipeline
    @async run_pipeline!(pipeline_mgr)

    # Trading task (critical path)
    @async begin
        for msg in trading_consumer.channel
            # Execute trading logic
            execute_trade(msg)
        end
    end

    # Logging task
    @async begin
        for msg in logging_consumer.channel
            # Log to file/database
            log_tick(msg)
        end
    end

    # Analytics task
    @async begin
        for msg in analytics_consumer.channel
            # Update statistics/models
            update_analytics(msg)
        end
    end
end
```

---

## Configuration

### Default Configuration

```julia
config = create_default_config()
```

**Default values (from src/PipelineConfig.jl):**
- `tick_file_path`: "data/raw/YM 06-25.Last.txt"
- `agc_alpha`: 0.125 (1/8 time constant)
- `agc_min_scale`: 4
- `agc_max_scale`: 50
- `winsorize_threshold`: 3.0σ
- `min_price`: 36600
- `max_price`: 43300
- `max_jump`: 50
- `delay_ms`: 0.0 (no flow control delay)

### Custom Configuration

```julia
# Method 1: Keyword arguments
config = PipelineConfig(
    tick_file_path = "data/raw/my_ticks.txt",
    signal_processing = SignalProcessingConfig(
        agc_alpha = Float32(0.25),      # Faster AGC
        min_price = Int32(30000),
        max_price = Int32(50000)
    ),
    flow_control = FlowControlConfig(
        delay_ms = 1.0                   # 1ms delay per tick
    )
)

# Method 2: Load from TOML file
config = load_config_from_toml("config/my_pipeline.toml")

# Method 3: Modify default
config = create_default_config()
config = PipelineConfig(
    tick_file_path = "data/raw/new_file.txt",
    signal_processing = config.signal_processing,  # Keep other settings
    flow_control = config.flow_control,
    channels = config.channels,
    performance = config.performance,
    pipeline_name = "custom_pipeline",
    description = "Custom configuration",
    version = "1.0",
    created = now()
)
```

### TOML Configuration File

Create `config/pipeline.toml`:

```toml
pipeline_name = "production"
description = "Production tick processing pipeline"
version = "1.0"
tick_file_path = "data/raw/ES 12-25.Last.txt"

[signal_processing]
agc_alpha = 0.125
agc_min_scale = 4
agc_max_scale = 50
winsorize_threshold = 3.0
min_price = 30000
max_price = 50000
max_jump = 100

[flow_control]
delay_ms = 0.0

[channels]
priority_buffer_size = 4096
standard_buffer_size = 2048

[performance]
target_latency_us = 500
max_latency_us = 1000
target_throughput_tps = 10000.0
```

Load it:

```julia
config = load_config_from_toml("config/pipeline.toml")
```

### Validate Configuration

```julia
(is_valid, errors) = validate_config(config)

if !is_valid
    println("Configuration errors:")
    for error in errors
        println("  - $error")
    end
else
    println("Configuration valid!")
end
```

---

## Advanced Usage

### Access Internal State

The pipeline maintains state internally, but you can access processed data:

```julia
# BroadcastMessage fields
msg.tick_idx           # Int32: Sequential tick number (1-based)
msg.timestamp          # Int64: Encoded timestamp
msg.raw_price          # Int32: Current tick price
msg.price_delta        # Int32: Price change from previous tick
msg.complex_signal     # ComplexF32: I/Q output (±0.5 range)
msg.normalization      # Float32: AGC scale factor
msg.status_flag        # UInt8: Processing flags

# Status flags
FLAG_OK        = 0x00  # Normal processing
FLAG_MALFORMED = 0x01  # Malformed input (unused)
FLAG_HOLDLAST  = 0x02  # Price validation failed, held previous
FLAG_CLIPPED   = 0x04  # Winsorization clipping occurred
FLAG_AGC_LIMIT = 0x08  # AGC hit max_scale limit

# Check flags
if (msg.status_flag & FLAG_CLIPPED) != 0
    println("Tick $(msg.tick_idx) was clipped")
end

if (msg.status_flag & FLAG_HOLDLAST) != 0
    println("Tick $(msg.tick_idx) failed validation")
end
```

### Decode Timestamp

```julia
using Dates

timestamp_str = decode_timestamp_from_int64(msg.timestamp)
println("Tick time: $timestamp_str")
```

### Recover Original Price Delta

The normalization factor allows recovery of the original price delta:

```julia
# Extract I (real component)
i_signal = real(msg.complex_signal)

# Recover price delta
recovered_delta = i_signal * msg.normalization

# Verify
@assert recovered_delta ≈ Float32(msg.price_delta)
```

### Custom Signal Processing

If you need custom processing beyond the pipeline:

```julia
using TickDataPipeline

# Get state for custom processing
state = create_tickhotloop_state()

# Process individual messages
for msg in consumer.channel
    # Access pre-processed fields
    raw_price = msg.raw_price
    price_delta = msg.price_delta

    # Access signal processing results
    i_signal = real(msg.complex_signal)
    q_signal = imag(msg.complex_signal)
    agc_scale = msg.normalization / 6.0  # Original AGC scale

    # Your custom processing here
    custom_indicator = calculate_indicator(i_signal, q_signal)

    # Use the data
    process_signal(custom_indicator)
end
```

### Pipeline Control

```julia
# Start pipeline with tick limit
pipeline_mgr = create_pipeline_manager(config, split_mgr)
task = @async run_pipeline!(pipeline_mgr, max_ticks=Int64(100000))

# Check if running
println("Pipeline running: ", !istaskdone(task))

# Wait for completion
wait(task)

# Manual pipeline processing (advanced)
# If you need more control, you can implement your own loop:
tick_channel = stream_expanded_ticks(config.tick_file_path, config.flow_control.delay_ms)
state = create_tickhotloop_state()

for msg in tick_channel
    process_tick_signal!(
        msg,
        state,
        config.signal_processing.agc_alpha,
        config.signal_processing.agc_min_scale,
        config.signal_processing.agc_max_scale,
        config.signal_processing.winsorize_threshold,
        config.signal_processing.min_price,
        config.signal_processing.max_price,
        config.signal_processing.max_jump
    )

    # msg now contains processed signal
    broadcast_to_all!(split_mgr, msg)
end
```

---

## Multi-threaded Applications

### Thread Safety

**TickDataPipeline is single-threaded by design and thread-safe when used in multi-threaded applications:**

- Pipeline runs on **one task** (Julia coroutine), not multi-threaded
- Multiple consumers can run on different threads safely
- Channels are thread-safe for cross-thread communication

### Using in Multi-threaded Apps

```julia
using TickDataPipeline

# Your app may use multiple threads
println("Application threads: $(Threads.nthreads())")

# Pipeline will use one thread regardless
config = create_default_config()
split_mgr = create_triple_split_manager()
pipeline_mgr = create_pipeline_manager(config, split_mgr)

# Pipeline runs on its own task (one thread)
@async run_pipeline!(pipeline_mgr)

# Consumers can run on different threads
consumer1 = subscribe_consumer!(split_mgr, "thread1", MONITORING, Int32(4096))
consumer2 = subscribe_consumer!(split_mgr, "thread2", MONITORING, Int32(4096))

# Consumer 1 on thread 1
Threads.@spawn begin
    println("Consumer 1 on thread: $(Threads.threadid())")
    for msg in consumer1.channel
        process_on_thread1(msg)
    end
end

# Consumer 2 on thread 2
Threads.@spawn begin
    println("Consumer 2 on thread: $(Threads.threadid())")
    for msg in consumer2.channel
        process_on_thread2(msg)
    end
end
```

### Thread Safety Guarantee

The pipeline's **mutable state** (`TickHotLoopState`) is:
- Owned by the pipeline task only
- Never accessed concurrently
- Safe because pipeline is single-threaded

**Channels** are:
- Thread-safe by Julia design
- Can safely pass messages between threads

**No additional synchronization needed** - the architecture ensures thread safety.

---

## API Reference

### Exported Types

#### BroadcastMessage
```julia
struct BroadcastMessage
    tick_idx::Int32              # Sequential tick number
    timestamp::Int64             # Encoded timestamp
    raw_price::Int32             # Current price
    price_delta::Int32           # Price change
    complex_signal::ComplexF32   # I/Q output (±0.5 range)
    normalization::Float32       # AGC scale × 6.0
    status_flag::UInt8           # Processing flags
end
```

#### Configuration Types
```julia
SignalProcessingConfig(;
    agc_alpha = Float32(0.125),
    agc_min_scale = Int32(4),
    agc_max_scale = Int32(50),
    winsorize_threshold = Float32(3.0),
    min_price = Int32(36600),
    max_price = Int32(43300),
    max_jump = Int32(50)
)

FlowControlConfig(;
    delay_ms = 0.0
)

ChannelConfig(;
    priority_buffer_size = Int32(4096),
    standard_buffer_size = Int32(2048)
)

PerformanceConfig(;
    target_latency_us = Int32(500),
    max_latency_us = Int32(1000),
    target_throughput_tps = Float32(10000.0)
)

PipelineConfig(;
    tick_file_path = "data/raw/YM 06-25.Last.txt",
    signal_processing = SignalProcessingConfig(),
    flow_control = FlowControlConfig(),
    channels = ChannelConfig(),
    performance = PerformanceConfig(),
    pipeline_name = "default",
    description = "Default tick processing pipeline",
    version = "1.0",
    created = now()
)
```

### Exported Functions

#### Configuration
```julia
create_default_config()::PipelineConfig
load_config_from_toml(toml_path::String)::PipelineConfig
save_config_to_toml(config::PipelineConfig, toml_path::String)
validate_config(config::PipelineConfig)::Tuple{Bool, Vector{String}}
```

#### Pipeline Management
```julia
create_pipeline_manager(config::PipelineConfig, split_mgr::TripleSplitManager)::PipelineManager
run_pipeline!(pipeline_mgr::PipelineManager; max_ticks::Int64=0)
stop_pipeline!(pipeline_mgr::PipelineManager)
```

#### Consumer Management
```julia
ConsumerType: PRIORITY, MONITORING, ANALYTICS

subscribe_consumer!(
    mgr::TripleSplitManager,
    consumer_id::String,
    type::ConsumerType,
    buffer_size::Int32
)::ConsumerChannel

unsubscribe_consumer!(mgr::TripleSplitManager, consumer_id::String)
```

#### Utilities
```julia
# Timestamp encoding/decoding
encode_timestamp_to_int64(timestamp_str::String)::Int64
decode_timestamp_from_int64(encoded::Int64)::String

# Parse tick line (for custom processing)
parse_tick_line(line::String)::Union{Nothing, Tuple{String, Int32, Int32, Int32, Int32}}
```

### Constants

```julia
# Status Flags
FLAG_OK        = UInt8(0x00)
FLAG_MALFORMED = UInt8(0x01)
FLAG_HOLDLAST  = UInt8(0x02)
FLAG_CLIPPED   = UInt8(0x04)
FLAG_AGC_LIMIT = UInt8(0x08)

# Consumer Types
PRIORITY   = ConsumerType(1)   # Blocking, guaranteed delivery
MONITORING = ConsumerType(2)   # Non-blocking, can drop
ANALYTICS  = ConsumerType(3)   # Non-blocking, larger buffer
```

---

## Example Projects

### Example 1: Save to Database

```julia
using TickDataPipeline
using SQLite

function save_to_database(tick_file::String, db_path::String)
    # Setup database
    db = SQLite.DB(db_path)
    SQLite.execute(db, """
        CREATE TABLE IF NOT EXISTS ticks (
            tick_idx INTEGER PRIMARY KEY,
            timestamp TEXT,
            raw_price INTEGER,
            price_delta INTEGER,
            i_signal REAL,
            q_signal REAL,
            normalization REAL,
            status_flag INTEGER
        )
    """)

    # Setup pipeline
    config = PipelineConfig(tick_file_path=tick_file)
    split_mgr = create_triple_split_manager()
    consumer = subscribe_consumer!(split_mgr, "db_writer", MONITORING, Int32(8192))
    pipeline_mgr = create_pipeline_manager(config, split_mgr)

    # Start pipeline
    @async run_pipeline!(pipeline_mgr)

    # Write to database
    stmt = SQLite.Stmt(db, """
        INSERT INTO ticks VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    """)

    for msg in consumer.channel
        SQLite.bind!(stmt, (
            msg.tick_idx,
            decode_timestamp_from_int64(msg.timestamp),
            msg.raw_price,
            msg.price_delta,
            real(msg.complex_signal),
            imag(msg.complex_signal),
            msg.normalization,
            msg.status_flag
        ))
        SQLite.execute(stmt)
    end

    SQLite.close(db)
end
```

### Example 2: Real-time Strategy

```julia
using TickDataPipeline

mutable struct TradingStrategy
    position::Int32
    entry_price::Int32
    iq_history::Vector{ComplexF32}
end

function run_strategy(tick_file::String)
    strategy = TradingStrategy(Int32(0), Int32(0), ComplexF32[])

    config = PipelineConfig(tick_file_path=tick_file)
    split_mgr = create_triple_split_manager()
    consumer = subscribe_consumer!(split_mgr, "strategy", PRIORITY, Int32(2048))
    pipeline_mgr = create_pipeline_manager(config, split_mgr)

    @async run_pipeline!(pipeline_mgr)

    for msg in consumer.channel
        # Track I/Q history
        push!(strategy.iq_history, msg.complex_signal)
        if length(strategy.iq_history) > 100
            popfirst!(strategy.iq_history)
        end

        # Calculate indicator from I/Q signals
        if length(strategy.iq_history) >= 20
            avg_magnitude = mean(abs.(strategy.iq_history[end-19:end]))

            # Trading logic
            if strategy.position == 0 && avg_magnitude > 0.3
                # Enter long
                strategy.position = Int32(1)
                strategy.entry_price = msg.raw_price
                println("LONG at $(msg.raw_price)")
            elseif strategy.position == 1 && avg_magnitude < 0.1
                # Exit long
                pnl = msg.raw_price - strategy.entry_price
                println("EXIT at $(msg.raw_price), PnL: $pnl")
                strategy.position = Int32(0)
            end
        end
    end
end
```

---

## Troubleshooting

### Issue: Package Not Found

```julia
ERROR: ArgumentError: Package TickDataPipeline not found in current path
```

**Solution:** Add to project dependencies or LOAD_PATH:
```julia
push!(LOAD_PATH, "/path/to/TickDataPipeline/src")
```

### Issue: Configuration Validation Fails

```julia
(is_valid, errors) = validate_config(config)
# is_valid = false
```

**Solution:** Check error messages and fix parameters:
```julia
for error in errors
    println(error)
end
# Fix the reported issues in your config
```

### Issue: Consumer Channel Closes Unexpectedly

**Symptom:** Loop exits early

**Solution:** Pipeline finished or was stopped. Check:
```julia
# Ensure pipeline has enough ticks
run_pipeline!(pipeline_mgr)  # No max_ticks = process all

# Or check task status
pipeline_task = @async run_pipeline!(pipeline_mgr)
println("Pipeline done: ", istaskdone(pipeline_task))
```

### Issue: Memory Usage Growing

**Symptom:** RAM consumption increases during processing

**Solution:** Consumer not keeping up, increase buffer or use non-blocking:
```julia
# Use MONITORING (non-blocking) instead of PRIORITY
consumer = subscribe_consumer!(split_mgr, "consumer", MONITORING, Int32(4096))

# Or process messages faster in consumer loop
```

---

## Best Practices

1. **Always validate configuration** before running pipeline
2. **Use MONITORING consumers** for non-critical tasks (can drop messages)
3. **Use PRIORITY consumers** only for critical paths (blocks pipeline if full)
4. **Close consumer channels** when done to free resources
5. **Check status_flag** to handle validation failures and clipping
6. **Use async tasks** to avoid blocking main thread
7. **Find actual price range** before setting min_price/max_price (use find_price_range.jl)
8. **Tune AGC alpha** based on your data's volatility characteristics
9. **Monitor normalization factor** to ensure AGC is working correctly

---

## Additional Resources

- **Source Code:** `src/TickDataPipeline.jl`
- **Examples:** `scripts/stream_ticks_to_jld2.jl`
- **Configuration:** `docs/howto/Data_Capture_and_Plotting_Guide.md`
- **Testing:** `test/` directory (100% passing)

---

**Last Updated:** 2025-10-05
**Package Version:** v0.1.0
**Julia Compatibility:** 1.6+

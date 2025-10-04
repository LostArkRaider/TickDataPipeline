# TickDataPipeline.jl API Reference

Complete API documentation for TickDataPipeline.jl v0.1.0

## Table of Contents

- [Core Types](#core-types)
- [Configuration](#configuration)
- [Pipeline Execution](#pipeline-execution)
- [Consumer Management](#consumer-management)
- [Metrics and Monitoring](#metrics-and-monitoring)
- [Utility Functions](#utility-functions)

---

## Core Types

### BroadcastMessage

```julia
mutable struct BroadcastMessage
    tick_idx::Int32
    timestamp::Int64
    raw_price::Int32
    price_delta::Int32
    normalization::Float32
    complex_signal::ComplexF32
    status_flag::UInt8
end
```

GPU-compatible message type representing a processed tick.

**Fields**:
- `tick_idx`: Sequential tick index (starts at 1)
- `timestamp`: Encoded timestamp (Int64)
- `raw_price`: Original last trade price
- `price_delta`: Price change from previous tick
- `normalization`: Normalization factor applied by AGC
- `complex_signal`: I/Q signal after QUAD-4 rotation
- `status_flag`: Processing status flags

**Status Flags**:
- `FLAG_OK = 0x00`: Normal processing
- `FLAG_MALFORMED = 0x01`: Original record was malformed
- `FLAG_HOLDLAST = 0x02`: Price held from previous tick
- `FLAG_CLIPPED = 0x04`: Value was clipped/winsorized
- `FLAG_AGC_LIMIT = 0x08`: AGC hit min/max limit

**Functions**:

```julia
create_broadcast_message(
    tick_idx::Int32,
    timestamp::Int64,
    raw_price::Int32,
    price_delta::Int32
)::BroadcastMessage
```

Create message with initial values. Signal processing fields set to defaults.

```julia
update_broadcast_message!(
    msg::BroadcastMessage,
    complex_signal::ComplexF32,
    normalization::Float32,
    status_flag::UInt8
)
```

Update message with signal processing results (in-place).

---

## Configuration

### PipelineConfig

```julia
struct PipelineConfig
    tick_file_path::String
    signal_processing::SignalProcessingConfig
    flow_control::FlowControlConfig
    channels::ChannelConfig
    performance::PerformanceConfig
    pipeline_name::String
    description::String
    version::String
    created::DateTime
end
```

Complete pipeline configuration.

**Constructor**:

```julia
PipelineConfig(;
    tick_file_path::String = "data/raw/YM 06-25.Last.txt",
    signal_processing::SignalProcessingConfig = SignalProcessingConfig(),
    flow_control::FlowControlConfig = FlowControlConfig(),
    channels::ChannelConfig = ChannelConfig(),
    performance::PerformanceConfig = PerformanceConfig(),
    pipeline_name::String = "default",
    description::String = "Default tick processing pipeline",
    version::String = "1.0",
    created::DateTime = now()
)::PipelineConfig
```

### SignalProcessingConfig

```julia
struct SignalProcessingConfig
    agc_alpha::Float32
    agc_min_scale::Int32
    agc_max_scale::Int32
    winsorize_threshold::Float32
    min_price::Int32
    max_price::Int32
    max_jump::Int32
end
```

Signal processing parameters. All features ALWAYS ENABLED.

**Defaults**:
- `agc_alpha = 0.0625` (1/16)
- `agc_min_scale = 4`
- `agc_max_scale = 50`
- `winsorize_threshold = 3.0` (σ units)
- `min_price = 40000`
- `max_price = 43000`
- `max_jump = 50`

### FlowControlConfig

```julia
struct FlowControlConfig
    delay_ms::Float64
end
```

Flow control parameters.

**Default**: `delay_ms = 0.0` (maximum speed)

### ChannelConfig

```julia
struct ChannelConfig
    priority_buffer_size::Int32
    standard_buffer_size::Int32
end
```

Channel buffer sizes for consumers.

**Defaults**:
- `priority_buffer_size = 4096`
- `standard_buffer_size = 2048`

### PerformanceConfig

```julia
struct PerformanceConfig
    target_latency_us::Int32
    max_latency_us::Int32
    target_throughput_tps::Float32
end
```

Performance targets and limits.

**Defaults**:
- `target_latency_us = 500` (μs)
- `max_latency_us = 1000` (μs)
- `target_throughput_tps = 10000.0` (ticks/sec)

### Configuration Functions

```julia
create_default_config()::PipelineConfig
```

Create default configuration for YM futures.

```julia
load_config_from_toml(toml_path::String)::PipelineConfig
```

Load configuration from TOML file.

```julia
save_config_to_toml(config::PipelineConfig, toml_path::String)
```

Save configuration to TOML file.

```julia
validate_config(config::PipelineConfig)::Tuple{Bool, Vector{String}}
```

Validate configuration. Returns `(is_valid, error_messages)`.

**Validation Rules**:
- AGC: `min_scale < max_scale`, both positive, `alpha ∈ (0,1)`
- Price: `min_price < max_price`
- Jump: `max_jump > 0`
- Winsorize: `threshold > 0`
- Flow: `delay_ms >= 0`
- Channels: `buffer_sizes >= 1`
- Performance: `max_latency > target_latency`, `throughput > 0`

---

## Pipeline Execution

### PipelineManager

```julia
mutable struct PipelineManager
    config::PipelineConfig
    tickhotloop_state::TickHotLoopState
    split_manager::TripleSplitManager
    metrics::PipelineMetrics
    is_running::Bool
    completion_callback::Union{Function, Nothing}
end
```

Pipeline state and lifecycle management.

**Create**:

```julia
create_pipeline_manager(
    config::PipelineConfig,
    split_manager::TripleSplitManager
)::PipelineManager
```

Create pipeline manager with configuration and broadcasting manager.

### Pipeline Execution Functions

```julia
run_pipeline(
    config::PipelineConfig,
    manager::TripleSplitManager;
    max_ticks::Int64 = typemax(Int64)
)::NamedTuple
```

Simple pipeline execution. Returns basic statistics.

**Returns**:
- `ticks_processed::Int64`
- `broadcasts_sent::Int32`
- `errors::Int32`
- `state::TickHotLoopState`

```julia
run_pipeline!(
    pipeline_manager::PipelineManager;
    max_ticks::Int64 = typemax(Int64)
)::NamedTuple
```

Enhanced pipeline execution with detailed metrics.

**Returns**:
- `ticks_processed::Int64`
- `broadcasts_sent::Int32`
- `errors::Int32`
- `avg_latency_us::Float32`
- `max_latency_us::Int32`
- `min_latency_us::Int32`
- `avg_signal_time_us::Float32`
- `avg_broadcast_time_us::Float32`
- `state::TickHotLoopState`

```julia
stop_pipeline!(pipeline_manager::PipelineManager)
```

Request graceful pipeline shutdown. Sets `is_running = false`.

```julia
process_single_tick_through_pipeline!(
    pipeline_manager::PipelineManager,
    msg::BroadcastMessage
)::NamedTuple
```

Process single tick with metrics. For advanced usage.

**Returns**:
- `success::Bool`
- `total_latency_us::Int32`
- `signal_processing_time_us::Int32`
- `broadcast_time_us::Int32`
- `consumers_reached::Int32`
- `status_flag::UInt8`

---

## Consumer Management

### ConsumerType

```julia
@enum ConsumerType begin
    PRIORITY = 0
    MONITORING = 1
    ANALYTICS = 2
end
```

Consumer priority types.

- **PRIORITY**: Blocking delivery (always succeeds, may slow pipeline)
- **MONITORING**: Non-blocking (drops messages on full channel)
- **ANALYTICS**: Non-blocking (drops messages on full channel)

### TripleSplitManager

```julia
mutable struct TripleSplitManager
    consumers::Vector{ConsumerChannel}
    lock::ReentrantLock
    total_broadcasts::Int32
    total_dropped::Int32
end
```

Multi-consumer broadcasting manager.

**Create**:

```julia
create_triple_split_manager()::TripleSplitManager
```

Create empty broadcasting manager.

### Consumer Functions

```julia
subscribe_consumer!(
    manager::TripleSplitManager,
    consumer_id::String,
    consumer_type::ConsumerType,
    buffer_size::Int32
)::ConsumerChannel
```

Subscribe a new consumer.

**Parameters**:
- `manager`: Broadcasting manager
- `consumer_id`: Unique consumer identifier
- `consumer_type`: PRIORITY, MONITORING, or ANALYTICS
- `buffer_size`: Channel buffer size

**Returns**: ConsumerChannel with message channel

```julia
unsubscribe_consumer!(
    manager::TripleSplitManager,
    consumer_id::String
)::Bool
```

Remove consumer. Returns `true` if found and removed.

```julia
broadcast_to_all!(
    manager::TripleSplitManager,
    message::BroadcastMessage
)::Tuple{Int32, Int32, Int32}
```

Broadcast message to all consumers.

**Returns**: `(total_consumers, successful_deliveries, dropped_messages)`

### Consumer Statistics

```julia
get_consumer_stats(consumer::ConsumerChannel)::NamedTuple
```

Get consumer statistics.

**Returns**:
- `consumer_id::String`
- `consumer_type::ConsumerType`
- `buffer_size::Int32`
- `messages_sent::Int32`
- `messages_dropped::Int32`
- `current_buffer_usage::Int`

```julia
get_manager_stats(manager::TripleSplitManager)::NamedTuple
```

Get manager statistics.

**Returns**:
- `total_consumers::Int32`
- `total_broadcasts::Int32`
- `total_dropped::Int32`
- `consumers::Vector{NamedTuple}` (stats for each consumer)

---

## Metrics and Monitoring

### PipelineMetrics

```julia
mutable struct PipelineMetrics
    ticks_processed::Int64
    broadcasts_sent::Int32
    errors::Int32
    total_latency_us::Int64
    signal_processing_time_us::Int64
    broadcast_time_us::Int64
    max_latency_us::Int32
    min_latency_us::Int32
end
```

Accumulated pipeline statistics.

**Accessed via**: `pipeline_manager.metrics`

---

## Utility Functions

### Volume Expansion

```julia
stream_expanded_ticks(
    file_path::String,
    delay_ms::Float64 = 0.0
)::Channel{BroadcastMessage}
```

Stream tick data with volume expansion.

**Parameters**:
- `file_path`: Path to tick data file
- `delay_ms`: Delay between ticks (milliseconds)

**Returns**: Channel yielding BroadcastMessage for each expanded tick

```julia
parse_tick_line(line::String)::Union{Tuple{String,Int32,Int32,Int32,Int32}, Nothing}
```

Parse tick file line.

**Returns**: `(timestamp_str, bid, ask, last, volume)` or `nothing` if malformed

### Timestamp Encoding

```julia
encode_timestamp_to_int64(timestamp_str::String)::Int64
```

Encode ASCII timestamp to Int64 (first 8 characters).

```julia
decode_timestamp_from_int64(encoded::Int64)::String
```

Decode Int64 back to timestamp string (for debugging).

### Signal Processing

```julia
process_tick_signal!(
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
```

Process tick through signal processing pipeline (in-place update).

**Processing Steps** (all ALWAYS ENABLED):
1. Hard jump guard (clip to max_jump)
2. EMA normalization (alpha = 1/16)
3. AGC (automatic gain control)
4. Winsorization (outlier clipping)
5. QUAD-4 rotation (complex signal)

```julia
create_tickhotloop_state()::TickHotLoopState
```

Create signal processing state (for pipeline initialization).

---

## Usage Examples

### Basic Pipeline

```julia
using TickDataPipeline

config = create_default_config()
split_mgr = create_triple_split_manager()
consumer = subscribe_consumer!(split_mgr, "consumer1", PRIORITY, Int32(1000))

stats = run_pipeline(config, split_mgr, max_ticks = Int64(1000))

while consumer.channel.n_avail_items > 0
    msg = take!(consumer.channel)
    # Process message
end
```

### Enhanced Metrics

```julia
pipeline_mgr = create_pipeline_manager(config, split_mgr)
stats = run_pipeline!(pipeline_mgr, max_ticks = Int64(1000))

println("Avg latency: $(stats.avg_latency_us)μs")
println("Max latency: $(stats.max_latency_us)μs")
```

### Async Execution

```julia
pipeline_mgr = create_pipeline_manager(config, split_mgr)

pipeline_mgr.completion_callback = function(tick_count)
    println("Completed: $tick_count ticks")
end

task = @async run_pipeline!(pipeline_mgr, max_ticks = Int64(10000))
# Do other work...
wait(task)
```

### TOML Configuration

```julia
config = load_config_from_toml("my_config.toml")
is_valid, errors = validate_config(config)

if is_valid
    # Use config
else
    for error in errors
        println("Error: $error")
    end
end
```

---

## Performance Characteristics

**Benchmark Results** (typical):
- **Throughput**: 12,000+ ticks/sec
- **Latency P50**: < 1μs
- **Latency P95**: < 3μs
- **Latency P99**: < 10μs
- **Multi-consumer overhead**: Linear scaling

**Memory**:
- BroadcastMessage: 32 bytes (aligned)
- Zero allocation in hot loop
- Buffers: Configurable per consumer

**Thread Safety**:
- Broadcasting: ReentrantLock protected
- Safe for multi-threaded consumers
- Single-threaded pipeline execution

---

## See Also

- **Examples**: [`examples/`](../examples/) directory
- **Tests**: [`test/`](../test/) directory for usage examples
- **Design Spec**: [`docs/design/`](design/) for implementation details
- **Session Logs**: [`docs/logs/`](logs/) for development notes

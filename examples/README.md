# TickDataPipeline Examples

This directory contains example code demonstrating various usage patterns of the TickDataPipeline.jl package.

## Examples Overview

### 1. basic_usage.jl
**Demonstrates**: Core functionality and simple usage patterns

**Topics covered**:
- Simple pipeline with default configuration
- Custom configuration creation
- Multiple consumer types (PRIORITY, MONITORING, ANALYTICS)
- Enhanced metrics with PipelineManager
- Performance analysis

**Run**:
```bash
julia --project=.. basic_usage.jl
```

**Note**: This example will show warnings if the default tick data file is not present. This is expected behavior.

### 2. advanced_usage.jl
**Demonstrates**: Async processing, callbacks, and lifecycle control

**Topics covered**:
- Async pipeline execution with background tasks
- Completion callbacks
- Real-time message processing with consumer tasks
- Graceful pipeline shutdown
- Per-tick metrics collection and analysis
- Multiple concurrent pipelines

**Run**:
```bash
julia --project=.. advanced_usage.jl
```

**Note**: This example creates temporary test files that are automatically cleaned up.

### 3. config_example.jl
**Demonstrates**: Configuration management with TOML

**Topics covered**:
- Loading configuration from TOML files
- Creating and saving custom configurations
- Configuration validation
- Instrument-specific configurations (YM, ES, NQ)
- Environment-based configuration

**Run**:
```bash
julia --project=.. config_example.jl
```

**Note**: This example works with the `config/default.toml` file in the project root.

## Quick Start

The simplest way to use TickDataPipeline:

```julia
using TickDataPipeline

# Create configuration
config = create_default_config()

# Create broadcasting manager
split_mgr = create_triple_split_manager()

# Subscribe a consumer
consumer = subscribe_consumer!(split_mgr, "my_consumer", PRIORITY, Int32(1000))

# Run pipeline
stats = run_pipeline(config, split_mgr, max_ticks = Int64(100))

# Process messages
while consumer.channel.n_avail_items > 0
    msg = take!(consumer.channel)
    println("Tick $(msg.tick_idx): price=$(msg.raw_price)")
end
```

## Example Data Files

The examples expect tick data files in the `data/raw/` directory with the format:

```
data/raw/YM 06-25.Last.txt
data/raw/ES 06-25.Last.txt
data/raw/NQ 06-25.Last.txt
```

**Tick file format** (semicolon-separated):
```
yyyymmdd hhmmss uuuuuuu;bid;ask;last;volume
```

**Example line**:
```
20250319 070000 0520000;41971;41970;41971;1
```

If these files don't exist, the examples will create temporary test files or show warnings (which is expected).

## Common Patterns

### Pattern 1: Simple Synchronous Processing

```julia
config = create_default_config()
split_mgr = create_triple_split_manager()
consumer = subscribe_consumer!(split_mgr, "consumer1", PRIORITY, Int32(100))

stats = run_pipeline(config, split_mgr, max_ticks = Int64(1000))

for msg in consumer.channel
    # Process message
    println("Signal: $(msg.complex_signal)")
end
```

### Pattern 2: Async Processing with Metrics

```julia
config = create_default_config()
split_mgr = create_triple_split_manager()
subscribe_consumer!(split_mgr, "consumer1", PRIORITY, Int32(1000))

pipeline_mgr = create_pipeline_manager(config, split_mgr)

# Run async
task = @async run_pipeline!(pipeline_mgr, max_ticks = Int64(1000))

# Do other work...

# Wait and get stats
wait(task)
println("Avg latency: $(pipeline_mgr.metrics.avg_latency_us)μs")
```

### Pattern 3: Custom Configuration

```julia
config = PipelineConfig(
    tick_file_path = "my_data.txt",
    signal_processing = SignalProcessingConfig(
        agc_alpha = Float32(0.125),
        max_jump = Int32(25)
    ),
    flow_control = FlowControlConfig(delay_ms = 5.0)
)

# Validate before use
is_valid, errors = validate_config(config)
if is_valid
    # Use config...
end
```

### Pattern 4: TOML Configuration

```julia
# Save configuration
config = create_default_config()
save_config_to_toml(config, "my_config.toml")

# Load configuration
config = load_config_from_toml("my_config.toml")

# Validate
is_valid, errors = validate_config(config)
```

### Pattern 5: Multiple Consumers

```julia
split_mgr = create_triple_split_manager()

# Priority consumer (blocks on full channel)
priority = subscribe_consumer!(split_mgr, "priority", PRIORITY, Int32(500))

# Monitoring consumer (drops on full channel)
monitor = subscribe_consumer!(split_mgr, "monitor", MONITORING, Int32(500))

# Analytics consumer (drops on full channel)
analytics = subscribe_consumer!(split_mgr, "analytics", ANALYTICS, Int32(500))

# Run pipeline
stats = run_pipeline(config, split_mgr)

# Each consumer gets all messages (subject to backpressure rules)
```

## Performance Tips

1. **Buffer Sizing**: Size buffers according to expected backpressure
   - PRIORITY consumers block when full
   - MONITORING/ANALYTICS drop messages when full

2. **Flow Control**: Use delay_ms to control tick rate
   - 0.0 = maximum speed
   - > 0.0 = milliseconds between ticks

3. **Metrics Collection**: Use PipelineManager for detailed metrics
   - Adds minimal overhead (~few μs per tick)
   - Provides avg/min/max latency breakdown

4. **Multiple Pipelines**: Each pipeline is independent
   - Can run multiple instruments concurrently
   - Each has its own state and consumers

## Troubleshooting

### "Tick file not found" Warning
**Solution**: Create test data or update `tick_file_path` in configuration

### Consumer Channel Empty
**Possible causes**:
- Non-priority consumer dropped messages due to backpressure
- Pipeline max_ticks limit reached before messages consumed
- Check consumer statistics: `consumer.messages_sent` vs `consumer.messages_dropped`

### High Latency
**Check**:
- System load
- Buffer sizes (too small can cause blocking)
- Flow control delay (set to 0.0 for maximum speed)

### Validation Errors
**Common issues**:
- min_price >= max_price (should be <)
- agc_min_scale >= agc_max_scale (should be <)
- Negative delays or buffer sizes

## Additional Resources

- **Package Documentation**: See main README.md in project root
- **Design Specification**: `docs/design/Julia Tick Processing Pipeline Package - Design Specification v2.4.md`
- **Session Logs**: `docs/logs/` directory for implementation details
- **Tests**: `test/` directory for additional usage examples

## Support

For issues or questions:
- Review session logs in `docs/logs/`
- Check test files in `test/` for working examples
- Verify configuration with `validate_config()`

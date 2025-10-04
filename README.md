# TickDataPipeline.jl

High-performance tick data processing pipeline for Julia with GPU-compatible output.

[![Julia 1.9+](https://img.shields.io/badge/julia-1.9+-blue.svg)](https://julialang.org)
[![Tests](https://img.shields.io/badge/tests-298%2F298%20passing-brightgreen.svg)](test/)

## Overview

TickDataPipeline.jl is a specialized package for processing financial tick data with ultra-low latency and GPU-compatible data structures. It implements a complete pipeline from raw tick data to signal-processed output suitable for downstream analytics and GPU acceleration.

### Key Features

- **Volume Expansion**: Replicate ticks based on volume with correct price delta handling
- **Signal Processing**: Zero-allocation hot loop with AGC, EMA normalization, and QUAD-4 rotation
- **Multi-Consumer Broadcasting**: Priority-based message delivery with backpressure handling
- **GPU-Compatible**: All data structures use primitive types (Int32, Float32, ComplexF32)
- **TOML Configuration**: Flexible configuration management with validation
- **Performance Metrics**: Per-tick latency tracking with microsecond precision
- **Async Operation**: Background pipeline execution with lifecycle control

### Performance

- **Average Latency**: 0.03μs - 10μs per tick (depending on system and configuration)
- **Target Throughput**: 10,000+ ticks per second
- **Zero Allocation**: Hot loop uses in-place updates only
- **Thread-Safe**: ReentrantLock protection for multi-consumer broadcasting

## Installation

**Note**: This package is for internal use and is not published to the Julia General registry.

### For Use in ComplexBiquadGA (or other internal projects)

**Recommended: Development Mode**
```julia
# From ComplexBiquadGA directory
using Pkg
Pkg.activate(".")
Pkg.develop(path="../TickDataPipeline")
```

**Alternative: Direct Path**
```julia
using Pkg
Pkg.activate(".")
Pkg.add(path="C:\\Users\\Keith\\source\\repos\\Julia\\TickDataPipeline")
```

**Verify Installation**
```julia
using TickDataPipeline
println("✓ TickDataPipeline loaded successfully!")
```

See [INTERNAL_USAGE.md](INTERNAL_USAGE.md) for detailed integration guide.

## Quick Start

### Simple Pipeline

```julia
using TickDataPipeline

# Create configuration
config = create_default_config()

# Create broadcasting manager
split_mgr = create_triple_split_manager()

# Subscribe a consumer
consumer = subscribe_consumer!(split_mgr, "my_consumer", PRIORITY, Int32(1000))

# Run pipeline
stats = run_pipeline(config, split_mgr, max_ticks = Int64(1000))

println("Processed: $(stats.ticks_processed) ticks")
println("Errors: $(stats.errors)")

# Retrieve messages
while consumer.channel.n_avail_items > 0
    msg = take!(consumer.channel)
    println("Tick $(msg.tick_idx): price=$(msg.raw_price), signal=$(msg.complex_signal)")
end
```

### With Enhanced Metrics

```julia
using TickDataPipeline

config = create_default_config()
split_mgr = create_triple_split_manager()
subscribe_consumer!(split_mgr, "consumer1", PRIORITY, Int32(1000))

# Create pipeline manager for enhanced metrics
pipeline_mgr = create_pipeline_manager(config, split_mgr)

# Run with detailed statistics
stats = run_pipeline!(pipeline_mgr, max_ticks = Int64(1000))

println("Average latency: $(round(stats.avg_latency_us, digits=2))μs")
println("Max latency: $(stats.max_latency_us)μs")
println("Signal processing: $(round(stats.avg_signal_time_us, digits=2))μs")
println("Broadcasting: $(round(stats.avg_broadcast_time_us, digits=2))μs")
```

### Async Processing

```julia
using TickDataPipeline

config = create_default_config()
split_mgr = create_triple_split_manager()
subscribe_consumer!(split_mgr, "consumer1", PRIORITY, Int32(1000))

pipeline_mgr = create_pipeline_manager(config, split_mgr)

# Set completion callback
pipeline_mgr.completion_callback = function(tick_count)
    println("Pipeline completed: $tick_count ticks")
end

# Run in background
task = @async run_pipeline!(pipeline_mgr, max_ticks = Int64(10000))

# Do other work...

# Wait for completion
wait(task)
```

## Data Format

### Input Tick File Format

Semicolon-separated format:
```
yyyymmdd hhmmss uuuuuuu;bid;ask;last;volume
```

Example:
```
20250319 070000 0520000;41971;41970;41971;1
20250319 070001 0520000;41972;41971;41972;2
20250319 070002 0520000;41973;41972;41973;1
```

**Fields**:
- **Timestamp**: yyyymmdd hhmmss uuuuuuu (date, time, microseconds)
- **Bid**: Bid price (integer)
- **Ask**: Ask price (integer)
- **Last**: Last trade price (integer)
- **Volume**: Trade volume (ticks will be replicated by this amount)

### Output: BroadcastMessage

```julia
mutable struct BroadcastMessage
    tick_idx::Int32           # Sequential tick index
    timestamp::Int64          # Encoded timestamp
    raw_price::Int32          # Original last price
    price_delta::Int32        # Price change from previous tick
    normalization::Float32    # Normalization factor applied
    complex_signal::ComplexF32  # I/Q signal after QUAD-4 rotation
    status_flag::UInt8        # Processing status flags
end
```

**Status Flags**:
- `FLAG_OK (0x00)`: Normal processing
- `FLAG_MALFORMED (0x01)`: Original record was malformed
- `FLAG_HOLDLAST (0x02)`: Price held from previous
- `FLAG_CLIPPED (0x04)`: Value was clipped/winsorized
- `FLAG_AGC_LIMIT (0x08)`: AGC hit limit

## Configuration

### TOML Configuration

Load from file:
```julia
config = load_config_from_toml("config/default.toml")
```

Create and save:
```julia
config = PipelineConfig(
    pipeline_name = "my_pipeline",
    tick_file_path = "data/ticks.txt",
    signal_processing = SignalProcessingConfig(
        agc_alpha = Float32(0.0625),
        agc_min_scale = Int32(4),
        agc_max_scale = Int32(50),
        winsorize_threshold = Float32(3.0),
        min_price = Int32(40000),
        max_price = Int32(43000),
        max_jump = Int32(50)
    ),
    flow_control = FlowControlConfig(delay_ms = 0.0),
    channels = ChannelConfig(
        priority_buffer_size = Int32(4096),
        standard_buffer_size = Int32(2048)
    ),
    performance = PerformanceConfig(
        target_latency_us = Int32(500),
        max_latency_us = Int32(1000),
        target_throughput_tps = Float32(10000.0)
    )
)

save_config_to_toml(config, "my_config.toml")
```

Validate:
```julia
is_valid, errors = validate_config(config)
if !is_valid
    for error in errors
        println("Error: $error")
    end
end
```

### Default Configuration

The default configuration (`config/default.toml`) is tuned for YM futures (Dow Jones Mini):
- **Price range**: 40,000 - 43,000
- **Max jump**: 50 ticks
- **AGC alpha**: 0.0625 (1/16)
- **Target latency**: 500μs
- **No flow delay**: Maximum speed processing

## Architecture

### Pipeline Stages

1. **VolumeExpansion**: Read tick file, expand by volume, encode timestamps
2. **TickHotLoopF32**: Signal processing (AGC, EMA, winsorization, QUAD-4 rotation)
3. **TripleSplitSystem**: Multi-consumer broadcasting with priority handling

### Consumer Types

- **PRIORITY**: Blocking delivery (always succeeds, may slow pipeline)
- **MONITORING**: Non-blocking (drops messages on full channel)
- **ANALYTICS**: Non-blocking (drops messages on full channel)

### Signal Processing

All features **ALWAYS ENABLED** (zero branching for performance):

1. **Hard Jump Guard**: Clip price deltas exceeding max_jump
2. **EMA Normalization**: Exponential moving average with alpha=1/16
3. **AGC (Automatic Gain Control)**: Adaptive scaling with min/max limits
4. **Winsorization**: Outlier clipping at ±3σ (configurable)
5. **QUAD-4 Rotation**: Complex signal rotation (0°, 90°, 180°, 270°)

## Examples

See the [`examples/`](examples/) directory for comprehensive examples:

- **basic_usage.jl**: Core functionality and simple patterns
- **advanced_usage.jl**: Async processing, callbacks, lifecycle control
- **config_example.jl**: TOML configuration management

Each example is runnable:
```bash
julia --project=. examples/basic_usage.jl
```

## Testing

Run the test suite:
```bash
julia --project=. -e "using Pkg; Pkg.test()"
```

**Current Status**: 298/298 tests passing ✅

Test coverage:
- BroadcastMessage: 36 tests
- VolumeExpansion: 63 tests
- TickHotLoopF32: 50 tests
- TripleSplitSystem: 41 tests
- PipelineConfig: 53 tests
- PipelineManager: 55 tests

## Performance Tips

### 1. Buffer Sizing
- **PRIORITY consumers**: Size for maximum burst (blocks when full)
- **MONITORING/ANALYTICS**: Size for typical load (drops on overflow)

### 2. Flow Control
- **delay_ms = 0.0**: Maximum speed (use for backtesting)
- **delay_ms > 0.0**: Rate limiting (use for live simulation)

### 3. Consumer Design
- Use async tasks for consumer processing
- Avoid blocking operations in consumer callbacks
- Monitor `messages_dropped` for backpressure indication

### 4. Configuration
- Validate configuration before running pipeline
- Use TOML files for different instruments
- Adjust AGC parameters for different price volatilities

## API Reference

### Core Types

- `BroadcastMessage`: GPU-compatible tick message
- `PipelineConfig`: Comprehensive configuration
- `PipelineManager`: State and lifecycle management
- `TripleSplitManager`: Multi-consumer broadcasting

### Main Functions

- `create_default_config()`: Create default configuration
- `load_config_from_toml(path)`: Load configuration from file
- `validate_config(config)`: Validate configuration
- `create_triple_split_manager()`: Create broadcasting manager
- `subscribe_consumer!(manager, id, type, buffer_size)`: Add consumer
- `create_pipeline_manager(config, split_mgr)`: Create pipeline manager
- `run_pipeline(config, manager; max_ticks)`: Simple pipeline execution
- `run_pipeline!(pipeline_mgr; max_ticks)`: Enhanced pipeline execution
- `stop_pipeline!(pipeline_mgr)`: Graceful shutdown

### Consumer Types

- `PRIORITY`: Blocking delivery
- `MONITORING`: Non-blocking, drop on full
- `ANALYTICS`: Non-blocking, drop on full

## Documentation

- **Design Specification**: [`docs/design/Julia Tick Processing Pipeline Package - Design Specification v2.4.md`](docs/design/)
- **Implementation Plan**: [`docs/todo/TickDataPipeline.jl - Claude Code Implementation Plan.md`](docs/todo/)
- **Session Logs**: [`docs/logs/`](docs/logs/) - Detailed implementation notes for each session
- **Examples**: [`examples/README.md`](examples/README.md) - Example documentation

## Development

### Project Structure

```
TickDataPipeline.jl/
├── Project.toml
├── README.md
├── config/
│   └── default.toml
├── src/
│   ├── TickDataPipeline.jl       # Main module
│   ├── BroadcastMessage.jl       # Core message type
│   ├── VolumeExpansion.jl        # Tick reading and expansion
│   ├── TickHotLoopF32.jl         # Signal processing
│   ├── TripleSplitSystem.jl      # Multi-consumer broadcasting
│   ├── PipelineConfig.jl         # Configuration management
│   └── PipelineOrchestrator.jl   # Main pipeline loop
├── test/
│   ├── runtests.jl
│   ├── test_broadcast_message.jl
│   ├── test_volume_expansion.jl
│   ├── test_tickhotloopf32.jl
│   ├── test_triple_split.jl
│   ├── test_integration.jl
│   └── test_pipeline_manager.jl
├── examples/
│   ├── README.md
│   ├── basic_usage.jl
│   ├── advanced_usage.jl
│   └── config_example.jl
└── docs/
    ├── design/
    ├── logs/
    └── todo/
```

### Dependencies

- **Dates**: Standard library (timestamp handling)
- **TOML**: Standard library (configuration files)
- **Test**: Standard library (testing framework)

No external dependencies required.

## Contributing

This package was developed following strict protocols:

- **Julia Development Protocol v1.7**: Requirements R1-R23
- **Forbidden Practices**: Guidelines F1-F18
- **Test Creation Protocol**: Standards T1-T37

See [`CLAUDE.md`](CLAUDE.md) and protocol files in [`docs/protocol/`](docs/protocol/) for development standards.

## License

MIT License - See LICENSE file for details

## Citation

If you use TickDataPipeline.jl in your research, please cite:

```bibtex
@software{tickdatapipeline2025,
  title = {TickDataPipeline.jl: High-Performance Tick Data Processing},
  author = {Your Name},
  year = {2025},
  url = {https://github.com/yourusername/TickDataPipeline.jl}
}
```

## Support

- **Issues**: Report bugs or request features via GitHub Issues
- **Documentation**: See [`docs/`](docs/) directory
- **Examples**: See [`examples/`](examples/) directory

## Version History

### v0.1.0 (2025-10-03)
- Initial release
- Complete pipeline implementation (Sessions 1-8)
- 298 tests passing
- Comprehensive examples and documentation
- GPU-compatible data structures
- TOML configuration support
- Performance metrics and lifecycle management

# Session 7: Public API & Examples

**Date**: 2025-10-03
**Status**: ✅ COMPLETED
**Test Results**: 298/298 PASSED (no new tests, verified existing functionality)

## Objective

Create comprehensive examples demonstrating user-facing API and common usage patterns.

## Changes Made

### 1. Created Examples Directory Structure
**Directory**: `examples/`

**Purpose**: Provide working code examples for end users.

**Files Created**:
- `basic_usage.jl` - Core functionality and simple patterns
- `advanced_usage.jl` - Async processing, callbacks, lifecycle control
- `config_example.jl` - TOML configuration management
- `README.md` - Examples documentation

### 2. basic_usage.jl
**File**: `examples/basic_usage.jl`

**Topics Covered**:

**Example 1**: Simple Pipeline with Default Configuration
```julia
config = create_default_config()
split_mgr = create_triple_split_manager()
consumer = subscribe_consumer!(split_mgr, "my_consumer", PRIORITY, Int32(1000))
stats = run_pipeline(config, split_mgr, max_ticks = Int64(100))
```

**Example 2**: Pipeline with Custom Configuration
```julia
custom_config = PipelineConfig(
    signal_processing = SignalProcessingConfig(
        agc_alpha = Float32(0.125),
        winsorize_threshold = Float32(2.5),
        max_jump = Int32(25)
    ),
    flow_control = FlowControlConfig(delay_ms = 0.0),
    # ...
)
```

**Example 3**: Multiple Consumers with Different Types
```julia
priority_consumer = subscribe_consumer!(split_mgr, "priority", PRIORITY, Int32(500))
monitoring_consumer = subscribe_consumer!(split_mgr, "monitoring", MONITORING, Int32(500))
analytics_consumer = subscribe_consumer!(split_mgr, "analytics", ANALYTICS, Int32(500))
```

**Example 4**: Enhanced Metrics with PipelineManager
```julia
pipeline_mgr = create_pipeline_manager(config, split_mgr)
stats = run_pipeline!(pipeline_mgr, max_ticks = Int64(100))

println("Average latency: $(round(stats.avg_latency_us, digits=2))μs")
println("Max latency: $(stats.max_latency_us)μs")

signal_pct = (stats.avg_signal_time_us / stats.avg_latency_us) * 100.0
broadcast_pct = (stats.avg_broadcast_time_us / stats.avg_latency_us) * 100.0
```

**Output Example**:
```
======================================================================
Example 1: Simple Pipeline
======================================================================
Starting pipeline:
  Tick file: data/raw/YM 06-25.Last.txt
  Flow delay: 0.0ms
  Consumers: 1
Pipeline completed:
  Ticks processed: 100
  Broadcasts sent: 100
  Errors: 0

Retrieving messages...
  Tick 1: price=41971, delta=0, signal=0.0f0 + 0.0f0im
  Tick 2: price=41970, delta=-1, signal=0.0f0 - 0.11111111f0im
  Retrieved 100 messages
```

### 3. advanced_usage.jl
**File**: `examples/advanced_usage.jl`

**Topics Covered**:

**Example 1**: Async Pipeline with Completion Callback
```julia
pipeline_mgr.completion_callback = function(tick_count)
    println("✓ Pipeline completed: $tick_count ticks processed")
end

task = @async run_pipeline!(pipeline_mgr, max_ticks = Int64(20))
# Do other work...
wait(task)
```

**Example 2**: Real-time Message Processing with Consumer Task
```julia
consumer_task = @async begin
    for msg in consumer.channel
        # Process each message in real-time
        process_message(msg)
    end
end

pipeline_task = @async run_pipeline!(pipeline_mgr, max_ticks = Int64(50))
wait(pipeline_task)
```

**Example 3**: Graceful Pipeline Shutdown
```julia
pipeline_task = @async run_pipeline!(pipeline_mgr, max_ticks = Int64(1000))
sleep(0.2)  # Let it run
stop_pipeline!(pipeline_mgr)
wait(pipeline_task)
```

**Example 4**: Per-Tick Metrics Analysis
```julia
latencies = Int32[]
for msg in tick_channel
    result = process_single_tick_through_pipeline!(pipeline_mgr, msg)
    push!(latencies, result.total_latency_us)
end

# Calculate percentiles
sorted = sort(latencies)
p50 = sorted[div(length(sorted), 2)]
p95 = sorted[div(95 * length(sorted), 100)]
p99 = sorted[div(99 * length(sorted), 100)]
```

**Example 5**: Multiple Pipelines Running Concurrently
```julia
pipeline_mgr1 = create_pipeline_manager(config1, split_mgr1)
pipeline_mgr2 = create_pipeline_manager(config2, split_mgr2)

task1 = @async run_pipeline!(pipeline_mgr1, max_ticks = Int64(30))
task2 = @async run_pipeline!(pipeline_mgr2, max_ticks = Int64(30))

wait(task1)
wait(task2)
```

**Output Example**:
```
======================================================================
Example 2: Real-time Message Consumer
======================================================================
Starting pipeline with real-time consumer...
  Processed 10 messages, avg price: 41975.5
  Processed 20 messages, avg price: 41979.5
  Processed 30 messages, avg price: 41978.17
  Processed 40 messages, avg price: 41979.5
  Processed 50 messages, avg price: 41978.7
✓ Real-time processing complete
```

### 4. config_example.jl
**File**: `examples/config_example.jl`

**Topics Covered**:

**Example 1**: Load Default Configuration from TOML
```julia
config = load_config_from_toml("config/default.toml")
println("AGC alpha: $(config.signal_processing.agc_alpha)")
println("Target latency: $(config.performance.target_latency_us)μs")
```

**Example 2**: Create and Save Custom Configuration
```julia
custom_config = PipelineConfig(
    pipeline_name = "high_frequency_trading",
    description = "Ultra-low latency configuration for HFT",
    performance = PerformanceConfig(
        target_latency_us = Int32(100),
        target_throughput_tps = Float32(50000.0)
    )
)

save_config_to_toml(custom_config, "examples/custom_hft.toml")
loaded_config = load_config_from_toml("examples/custom_hft.toml")
```

**Example 3**: Configuration Validation
```julia
# Valid configuration
is_valid, errors = validate_config(valid_config)

# Invalid configuration
invalid_config = PipelineConfig(
    signal_processing = SignalProcessingConfig(
        agc_min_scale = Int32(100),  # Error: min > max
        agc_max_scale = Int32(50)
    )
)
is_valid, errors = validate_config(invalid_config)
# Returns: (false, ["agc_min_scale must be < agc_max_scale"])
```

**Example 4**: Instrument-Specific Configurations
```julia
# YM (Dow Mini)
ym_config = PipelineConfig(
    pipeline_name = "ym_dow_mini",
    signal_processing = SignalProcessingConfig(
        min_price = Int32(40000),
        max_price = Int32(43000)
    )
)

# ES (S&P Mini)
es_config = PipelineConfig(
    pipeline_name = "es_sp_mini",
    signal_processing = SignalProcessingConfig(
        min_price = Int32(5000),
        max_price = Int32(6000)
    )
)
```

**Example 5**: Configuration from Environment Variables
```julia
function create_config_from_environment()
    tick_file = get(ENV, "TICK_FILE_PATH", "data/raw/YM 06-25.Last.txt")
    agc_alpha = parse(Float32, get(ENV, "AGC_ALPHA", "0.0625"))

    return PipelineConfig(
        tick_file_path = tick_file,
        signal_processing = SignalProcessingConfig(agc_alpha = agc_alpha)
    )
end
```

**Output Example**:
```
======================================================================
Configuration Management Examples
======================================================================

Example 1: Load Default Configuration
----------------------------------------------------------------------
Loaded configuration:
  Pipeline name: default
  Description: Default tick processing pipeline for YM futures
  AGC alpha: 0.0625
  Target latency: 500μs
  Max latency: 1000μs
```

### 5. examples/README.md
**File**: `examples/README.md`

**Content**:
- Examples overview and descriptions
- Quick start guide
- Example data files format
- Common usage patterns (5 patterns)
- Performance tips
- Troubleshooting guide
- Links to additional resources

**Common Patterns Documented**:
1. Simple Synchronous Processing
2. Async Processing with Metrics
3. Custom Configuration
4. TOML Configuration
5. Multiple Consumers

**Troubleshooting Topics**:
- "Tick file not found" warnings
- Consumer channel empty issues
- High latency diagnostics
- Validation errors

## Testing

### Examples Verified
All examples tested and working:

**basic_usage.jl**: ✅ All 4 examples run successfully
- Example 1: Simple Pipeline (100 ticks)
- Example 2: Custom Configuration (validation)
- Example 3: Multiple Consumer Types (3 consumers)
- Example 4: Enhanced Metrics (latency breakdown)

**advanced_usage.jl**: ✅ All 5 examples run successfully
- Example 1: Async with Callbacks (20 ticks)
- Example 2: Real-time Consumer (50 ticks)
- Example 3: Graceful Shutdown (stopped at 12/1000 ticks)
- Example 4: Per-Tick Metrics (100 ticks, percentiles)
- Example 5: Concurrent Pipelines (2 pipelines, 30 ticks each)

**config_example.jl**: ✅ All 5 examples run successfully
- Example 1: Load Default TOML
- Example 2: Create/Save Custom Config
- Example 3: Validation (valid + 3 invalid cases)
- Example 4: Instrument Configs (YM, ES, NQ)
- Example 5: Environment Variables

### Full Test Suite: ✅ 298/298 PASSED
All existing tests continue to pass with no regressions.

## Design Decisions

### 1. Examples as Executable Scripts
**Rationale**: Users can run examples directly to see output.
- Self-contained (create test data as needed)
- Automatic cleanup (finally blocks)
- Real output demonstrates functionality

### 2. Progressive Complexity
**Rationale**: Start simple, build to advanced.
- basic_usage.jl: Core functionality
- advanced_usage.jl: Async and lifecycle
- config_example.jl: Configuration management

### 3. Comprehensive README
**Rationale**: Examples need context and guidance.
- Overview of each example file
- Quick start for immediate usage
- Common patterns as copy-paste templates
- Troubleshooting for common issues

### 4. No Public API Wrapper
**Rationale**: Existing API is already user-friendly.
- Direct use of core types (PipelineConfig, PipelineManager)
- Clear function names (create_pipeline_manager, run_pipeline!)
- Optional complexity (simple run_pipeline vs enhanced run_pipeline!)
- No additional wrapper layer needed

### 5. Temporary Test Files
**Rationale**: Examples work without real data files.
- Advanced examples create temp files
- Automatic cleanup in finally blocks
- Windows file locking handled (sleep before rm)

### 6. Real Performance Numbers
**Rationale**: Show actual latencies, not mock values.
- Examples use real pipeline execution
- Latency numbers demonstrate performance (0.03μs - 10μs)
- Users see what to expect

## Files Created

1. `examples/basic_usage.jl` - NEW: Core functionality examples
2. `examples/advanced_usage.jl` - NEW: Async and lifecycle examples
3. `examples/config_example.jl` - NEW: Configuration examples
4. `examples/README.md` - NEW: Examples documentation

## Protocol Compliance

✅ **R1**: All code output to filesystem (examples/ directory)
✅ **R6**: 100% test pass rate (298/298)
✅ **R7**: Session log created
✅ **R9**: Examples provide comprehensive usage coverage
✅ **R10**: Documentation standards met (examples README)
✅ **R15**: No test modifications (examples don't affect tests)
✅ **R23**: Examples demonstrate correct usage
✅ **F13**: No design changes (examples use existing API)
✅ **F17**: No @test_broken

## Key Features Demonstrated

### 1. Simple Usage ✅
- Default configuration
- Basic pipeline execution
- Message retrieval
- Consumer statistics

### 2. Configuration Management ✅
- TOML load/save
- Custom configurations
- Validation
- Instrument-specific configs
- Environment variables

### 3. Advanced Patterns ✅
- Async execution
- Completion callbacks
- Real-time consumers
- Graceful shutdown
- Per-tick metrics
- Concurrent pipelines

### 4. Performance Analysis ✅
- Latency breakdown (signal vs broadcast)
- Min/max/average statistics
- Percentile calculations (P50, P95, P99)
- Time budget analysis

## User Benefits

### 1. Quick Start
Copy-paste examples get users running immediately.

### 2. Learning Path
Progressive examples from simple to advanced.

### 3. Reference Implementation
Examples show correct usage patterns.

### 4. Troubleshooting
Common issues addressed with solutions.

### 5. Performance Insight
Real numbers show expected latencies.

## Session Complete

Session 7 successfully created comprehensive examples demonstrating all aspects of TickDataPipeline.jl. All examples tested and working. No new tests added (examples verify existing functionality). 298/298 tests passing.

**Next Session**: Session 8 - Testing, Documentation & Polish

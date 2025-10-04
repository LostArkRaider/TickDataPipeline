# Using TickDataPipeline in ComplexBiquadGA

## Internal Package - Setup Guide

This package is for internal use only and will not be published to the Julia General registry.

## Installation Methods

### Method 1: Local Development Mode (Recommended for Active Development)

Use this when you're still making changes to TickDataPipeline while working on ComplexBiquadGA.

```julia
# In ComplexBiquadGA project directory
using Pkg

# Add TickDataPipeline in development mode (creates symlink)
Pkg.develop(path="C:\\Users\\Keith\\source\\repos\\Julia\\TickDataPipeline")

# Or use relative path if projects are in same parent directory
Pkg.develop(path="../TickDataPipeline")
```

**Advantages**:
- Changes to TickDataPipeline immediately available in ComplexBiquadGA
- No need to reinstall after edits
- Easy to test changes across both packages

**Usage in ComplexBiquadGA**:
```julia
using TickDataPipeline

# All exported functions available
config = create_default_config()
split_mgr = create_triple_split_manager()
# ... etc
```

### Method 2: Direct Add by Path (For Stable Versions)

Use this when TickDataPipeline is stable and you want a specific version.

```julia
using Pkg
Pkg.add(path="C:\\Users\\Keith\\source\\repos\\Julia\\TickDataPipeline")
```

**Advantages**:
- Package is copied into ComplexBiquadGA's environment
- More isolated (changes to TickDataPipeline source don't affect ComplexBiquadGA)
- Can have different versions in different projects

### Method 3: Git Repository (For Version Control)

If you're using git for both projects:

1. **Initialize TickDataPipeline as git repo**:
   ```bash
   cd C:\Users\Keith\source\repos\Julia\TickDataPipeline
   git init
   git add .
   git commit -m "Initial commit: TickDataPipeline v0.1.0"
   ```

2. **Add from ComplexBiquadGA**:
   ```julia
   using Pkg
   Pkg.add(url="C:\\Users\\Keith\\source\\repos\\Julia\\TickDataPipeline")

   # Or if you push to a remote git server:
   Pkg.add(url="https://your-internal-git-server.com/TickDataPipeline.jl")
   ```

**Advantages**:
- Version control for both packages
- Can tag versions (v0.1.0, v0.2.0, etc.)
- Easy to roll back changes
- Can share with team via internal git server

## Quick Start in ComplexBiquadGA

### 1. Add the Package

Choose Method 1 (recommended for active development):

```julia
# In Julia REPL, activate ComplexBiquadGA project
julia> cd("C:\\Users\\Keith\\source\\repos\\Julia\\ComplexBiquadGA")
julia> using Pkg
julia> Pkg.activate(".")
julia> Pkg.develop(path="../TickDataPipeline")
```

### 2. Verify Installation

```julia
julia> using TickDataPipeline
julia> println("TickDataPipeline loaded successfully!")
```

### 3. Update ComplexBiquadGA Project.toml

After adding TickDataPipeline, your `ComplexBiquadGA/Project.toml` will automatically include:

```toml
[deps]
TickDataPipeline = "1321d1ed-360f-4df0-b264-cb3ad27dd90d"
# ... other dependencies
```

## Integration Examples

### Replace Old Tick Processing Code

**Before** (in ComplexBiquadGA):
```julia
# Old inline tick processing
function process_ticks(file_path)
    # Custom volume expansion code
    # Custom signal processing code
    # Custom broadcasting code
    # ...
end
```

**After** (using TickDataPipeline):
```julia
using TickDataPipeline

function process_ticks(file_path)
    # Load configuration
    config = load_config_from_toml("config/tick_processing.toml")

    # Create broadcasting manager
    split_mgr = create_triple_split_manager()

    # Subscribe GA consumer
    ga_consumer = subscribe_consumer!(split_mgr, "ga_engine", PRIORITY, Int32(4096))

    # Create pipeline
    pipeline_mgr = create_pipeline_manager(config, split_mgr)

    # Run async
    pipeline_task = @async run_pipeline!(pipeline_mgr, max_ticks = Int64(10000))

    # Process messages for GA
    for msg in ga_consumer.channel
        # Feed to GA engine
        process_ga_tick(msg.complex_signal, msg.raw_price, msg.price_delta)
    end

    wait(pipeline_task)
end
```

### Integration with GA Engine

```julia
using TickDataPipeline

# Create configuration for YM futures
config = PipelineConfig(
    tick_file_path = "data/raw/YM 06-25.Last.txt",
    signal_processing = SignalProcessingConfig(
        agc_alpha = Float32(0.0625),
        agc_min_scale = Int32(4),
        agc_max_scale = Int32(50)
    )
)

# Set up consumers
split_mgr = create_triple_split_manager()

# GA engine gets priority
ga_consumer = subscribe_consumer!(split_mgr, "ga_engine", PRIORITY, Int32(4096))

# Optional monitoring
monitor_consumer = subscribe_consumer!(split_mgr, "monitor", MONITORING, Int32(2048))

# Run pipeline
pipeline_mgr = create_pipeline_manager(config, split_mgr)
stats = run_pipeline!(pipeline_mgr)

println("Processed $(stats.ticks_processed) ticks")
println("Avg latency: $(stats.avg_latency_us)μs")
```

### Access Processed Signals

```julia
# Pipeline produces GPU-compatible BroadcastMessage
for msg in ga_consumer.channel
    # All fields are primitive types, ready for GPU
    tick_idx = msg.tick_idx          # Int32
    timestamp = msg.timestamp         # Int64
    raw_price = msg.raw_price         # Int32
    price_delta = msg.price_delta     # Int32
    normalization = msg.normalization # Float32
    complex_signal = msg.complex_signal # ComplexF32
    status_flag = msg.status_flag     # UInt8

    # Feed to GA
    ga_process!(complex_signal, raw_price)
end
```

## Configuration for ComplexBiquadGA

Create `ComplexBiquadGA/config/tick_processing.toml`:

```toml
pipeline_name = "ComplexBiquadGA_Pipeline"
description = "Tick processing for GA optimization"
version = "1.0"
tick_file_path = "data/raw/YM 06-25.Last.txt"

[signal_processing]
agc_alpha = 0.0625
agc_min_scale = 4
agc_max_scale = 50
winsorize_threshold = 3.0
min_price = 40000
max_price = 43000
max_jump = 50

[flow_control]
delay_ms = 0.0  # Maximum speed for GA

[channels]
priority_buffer_size = 8192  # Larger buffer for GA
standard_buffer_size = 2048

[performance]
target_latency_us = 500
max_latency_us = 1000
target_throughput_tps = 10000.0
```

Then load in ComplexBiquadGA:

```julia
using TickDataPipeline

config = load_config_from_toml("config/tick_processing.toml")
```

## Troubleshooting

### Issue: "Package TickDataPipeline not found"

**Solution**: Make sure you've added the package first:
```julia
using Pkg
Pkg.develop(path="C:\\Users\\Keith\\source\\repos\\Julia\\TickDataPipeline")
```

### Issue: "Cannot find module TickDataPipeline"

**Solution**: Check that you're in the correct project:
```julia
using Pkg
Pkg.activate(".")  # Activate current project
Pkg.status()       # Should show TickDataPipeline in dependencies
```

### Issue: Changes to TickDataPipeline not reflected

**Solution**:
- If using `Pkg.develop()`: Restart Julia REPL
- If using `Pkg.add()`: Need to re-add or switch to develop mode

### Issue: Version conflicts

**Solution**: TickDataPipeline has no external dependencies, so shouldn't conflict.
Check with:
```julia
using Pkg
Pkg.resolve()
```

## Updating TickDataPipeline

### If Using Develop Mode

Changes are automatic - just restart Julia:
```julia
# Make changes to TickDataPipeline source
# Then in ComplexBiquadGA:
exit()  # Exit Julia
julia   # Restart Julia
using TickDataPipeline  # Loads updated version
```

### If Using Add Mode

Need to free and re-add:
```julia
using Pkg
Pkg.free("TickDataPipeline")
Pkg.add(path="C:\\Users\\Keith\\source\\repos\\Julia\\TickDataPipeline")
```

## Testing Integration

### Quick Test

```julia
# In ComplexBiquadGA project
using Pkg
Pkg.activate(".")

using TickDataPipeline

# Verify it works
config = create_default_config()
println("TickDataPipeline integrated successfully!")
println("Config: $(config.pipeline_name)")
```

### Full Integration Test

Create `ComplexBiquadGA/test/test_tick_integration.jl`:

```julia
using Test
using TickDataPipeline

@testset "TickDataPipeline Integration" begin
    # Test basic functionality
    config = create_default_config()
    @test config.pipeline_name == "default"

    # Test configuration
    @test config.signal_processing.agc_alpha == Float32(0.0625)

    # Test manager creation
    split_mgr = create_triple_split_manager()
    @test length(split_mgr.consumers) == 0

    # Test consumer subscription
    consumer = subscribe_consumer!(split_mgr, "test", PRIORITY, Int32(100))
    @test length(split_mgr.consumers) == 1

    println("✓ TickDataPipeline integration tests passed")
end
```

## Performance Considerations

### For GA Application

1. **Buffer Sizing**: GA needs PRIORITY consumer with large buffer (8192+)
   ```julia
   ga_consumer = subscribe_consumer!(split_mgr, "ga", PRIORITY, Int32(8192))
   ```

2. **Flow Control**: Disable delays for maximum speed
   ```julia
   config.flow_control.delay_ms = 0.0
   ```

3. **Async Processing**: Run pipeline in background while GA processes
   ```julia
   pipeline_task = @async run_pipeline!(pipeline_mgr)

   # Process in parallel
   for msg in ga_consumer.channel
       ga_process!(msg)
   end
   ```

## Maintenance

### Keeping TickDataPipeline Updated

Since this is internal:

1. **Make changes** to TickDataPipeline as needed
2. **Run tests**: `julia --project=. -e "using Pkg; Pkg.test()"`
3. **Update version** in TickDataPipeline/Project.toml if major changes
4. **Restart Julia** in ComplexBiquadGA to pick up changes (if using develop mode)

### When to Update Version

Update version in `TickDataPipeline/Project.toml`:
- **0.1.1**: Bug fixes, minor tweaks
- **0.2.0**: New features, backward compatible
- **1.0.0**: Breaking changes to API

## Summary

**Recommended Setup for ComplexBiquadGA**:

1. Use `Pkg.develop(path="../TickDataPipeline")`
2. Create `ComplexBiquadGA/config/tick_processing.toml`
3. Replace old tick processing code with TickDataPipeline calls
4. Use PRIORITY consumer with large buffer for GA
5. Run tests to verify integration

**Total setup time**: ~5 minutes

Your TickDataPipeline is ready to use in ComplexBiquadGA right now! 🚀

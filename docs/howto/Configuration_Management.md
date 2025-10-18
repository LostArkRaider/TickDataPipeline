# Configuration Management

## Overview

TickDataPipeline uses a smart configuration system that:
- **Auto-creates config files** if they don't exist
- **Never silently uses hardcoded defaults** after first run
- **Provides editable configuration** in a standard location
- **Works across different deployment scenarios** (package, local project, etc.)

## Configuration File Location

**Default path**: `config/pipeline/default.toml`

This path is:
- ✅ Unique (avoids conflicts with other `default.toml` files)
- ✅ Auto-created if missing
- ✅ Relative to the package root (works as package or project)
- ✅ Editable by users

## Quick Start

### Most Common Use Case

```julia
using TickDataPipeline

# Load default configuration (creates file if missing)
config = load_default_config()

# Create and run pipeline
manager = create_pipeline_manager(config)
results = run_pipeline(manager)
```

### What Happens on First Run

When you call `load_default_config()` for the first time:

```
[ Info: Configuration file not found: /path/to/config/pipeline/default.toml
[ Info: Creating default configuration...
[ Info: Created directory: /path/to/config/pipeline
[ Info: ✓ Default configuration created at: /path/to/config/pipeline/default.toml
[ Info:   You can now edit this file to customize your pipeline settings.
[ Info: Loading configuration from: /path/to/config/pipeline/default.toml
```

**After this**, the config file exists and you can edit it with your favorite text editor!

### On Subsequent Runs

```
[ Info: Configuration file found: /path/to/config/pipeline/default.toml
[ Info: Loading configuration from: /path/to/config/pipeline/default.toml
```

No file creation - just loads your customized settings.

## API Functions

### `load_default_config()`

**Recommended for most users.**

```julia
config = load_default_config()
```

- Automatically finds the default config file
- Creates it if missing
- Loads and returns configuration

### `load_config_from_toml(path)`

**For custom config locations.**

```julia
# Load custom configuration
config = load_config_from_toml("config/pipeline/production.toml")

# First time: creates file with defaults
# Subsequent: loads your custom settings
```

### `get_default_config_path()`

**Get the path without loading.**

```julia
path = get_default_config_path()
println("Config location: $path")
# Output: Config location: /path/to/TickDataPipeline/config/pipeline/default.toml
```

Useful for:
- Checking if config exists before loading
- Displaying config location to users
- Scripting and automation

### `ensure_config_exists(path)`

**Manually ensure a config file exists.**

```julia
custom_path = "config/pipeline/custom.toml"
ensure_config_exists(custom_path)
# Creates file with defaults if missing
```

### `create_default_config()`

**Get default config object (in-memory only).**

```julia
config = create_default_config()
# Returns PipelineConfig with default values
# Does NOT create any files
```

Useful for:
- Programmatic config generation
- Testing with defaults
- Building custom configs

### `save_config_to_toml(config, path)`

**Save configuration to file.**

```julia
config = create_default_config()
# Modify config...
config.signal_processing.encoder_type = "cpm"

# Save to custom location
save_config_to_toml(config, "config/pipeline/my_config.toml")
```

## Configuration Workflow

### 1. First Time Setup (Automatic)

```julia
using TickDataPipeline

# This creates config/pipeline/default.toml if missing
config = load_default_config()
```

**Result**: You now have an editable config file with all default settings.

### 2. Customize Configuration

Edit `config/pipeline/default.toml` in your text editor:

```toml
[bar_processing]
enabled = true
ticks_per_bar = 13          # Changed from 21
bar_method = "FIR"          # Changed from "boxcar"
normalization_window_bars = 200  # Adjusted for 13-tick bars
```

Save the file.

### 3. Use Customized Configuration

```julia
using TickDataPipeline

# Loads your customized settings
config = load_default_config()

# Pipeline uses your custom settings
manager = create_pipeline_manager(config)
results = run_pipeline(manager)
```

## Multiple Configurations

You can maintain multiple configuration files:

```
config/
└── pipeline/
    ├── default.toml          # Default settings
    ├── development.toml      # Development/testing
    ├── production.toml       # Production settings
    ├── bars_13_ticks.toml    # 13-tick bar configuration
    └── bars_21_ticks.toml    # 21-tick bar configuration
```

Switch between them easily:

```julia
# Use production settings
config = load_config_from_toml("config/pipeline/production.toml")

# Use 13-tick bar settings
config = load_config_from_toml("config/pipeline/bars_13_ticks.toml")
```

## Deployment Scenarios

### Scenario 1: Local Project

```
MyProject/
├── TickDataPipeline/      # Package as subproject
│   ├── src/
│   └── config/
│       └── pipeline/
│           └── default.toml  # Auto-created here
└── my_script.jl
```

Config file is created in the TickDataPipeline directory.

### Scenario 2: Installed Package

```julia
using Pkg
Pkg.add(url="https://github.com/yourorg/TickDataPipeline.jl")

using TickDataPipeline
config = load_default_config()
```

Config file is created in:
```
~/.julia/packages/TickDataPipeline/xxxxx/config/pipeline/default.toml
```

**Note**: In packaged mode, you should copy the config to your project and use `load_config_from_toml()` with an explicit path.

### Scenario 3: Development Mode

```julia
using Pkg
Pkg.develop(path="/path/to/TickDataPipeline")

using TickDataPipeline
config = load_default_config()
```

Config file is created in your development directory:
```
/path/to/TickDataPipeline/config/pipeline/default.toml
```

## Best Practices

### ✅ DO

1. **Use `load_default_config()` for simple cases**
   ```julia
   config = load_default_config()
   ```

2. **Use explicit paths for production**
   ```julia
   config = load_config_from_toml("config/pipeline/production.toml")
   ```

3. **Keep config files in version control** (with sensitive data removed)

4. **Create separate configs for different use cases**
   - `development.toml`
   - `testing.toml`
   - `production.toml`
   - `bars_13_ticks.toml`
   - `bars_21_ticks.toml`

5. **Document config changes in your project**

### ❌ DON'T

1. **Don't call `create_default_config()` and use it directly**
   ```julia
   # BAD: Uses hardcoded defaults, not editable
   config = create_default_config()
   
   # GOOD: Creates file, then loads (editable)
   config = load_default_config()
   ```

2. **Don't hardcode configuration values in scripts**
   ```julia
   # BAD: Hardcoded, not configurable
   manager = create_pipeline_manager(
       PipelineConfig(ticks_per_bar=21, ...)
   )
   
   # GOOD: Load from file
   config = load_default_config()
   manager = create_pipeline_manager(config)
   ```

3. **Don't ignore the auto-created config file**
   - After first run, **edit the TOML file**, don't keep using defaults

## Troubleshooting

### Config file not being created

**Problem**: `load_default_config()` doesn't create the file.

**Solution**: Check write permissions on the config directory.

```julia
path = get_default_config_path()
println("Config path: $path")
println("Directory exists: ", isdir(dirname(path)))
println("Can write: ", iswritable(dirname(path)))
```

### Config changes not taking effect

**Problem**: Modified TOML file but pipeline still uses old settings.

**Solution**: Restart Julia REPL or reload the package.

```julia
# In Julia REPL
exit()  # or Ctrl+D

# Restart Julia and reload
using TickDataPipeline
config = load_default_config()  # Loads fresh from file
```

### Wrong config file being loaded

**Problem**: Pipeline loads config from unexpected location.

**Solution**: Check which file is being loaded.

```julia
path = get_default_config_path()
println("Loading config from: $path")

# Verify the file exists and has your changes
@show isfile(path)
```

### Want to reset to defaults

**Problem**: Config file is corrupted or want fresh defaults.

**Solution**: Delete the config file and reload.

```julia
# Delete config file
path = get_default_config_path()
rm(path)

# This will create a fresh default
config = load_default_config()
```

## Example: Complete Workflow

```julia
using TickDataPipeline

# 1. First run - creates default config
config = load_default_config()
# [ Info: Created config at: /path/to/config/pipeline/default.toml

# 2. Edit the file (in your text editor)
#    Change ticks_per_bar = 13, bar_method = "FIR", etc.

# 3. Restart Julia and reload with your changes
using TickDataPipeline
config = load_default_config()
# [ Info: Loading configuration from: /path/to/config/pipeline/default.toml

# 4. Verify your settings
@show config.bar_processing.ticks_per_bar  # Should show 13
@show config.bar_processing.bar_method     # Should show "FIR"

# 5. Run pipeline with custom settings
manager = create_pipeline_manager(config)
results = run_pipeline(manager)
```

## Configuration File Format

See `config/pipeline/default.toml` for a complete, commented example with all available settings.

Key sections:
- `[signal_processing]` - Encoder selection, AGC, normalization
- `[bar_processing]` - Bar size, FIR filter, thresholds
- `[flow_control]` - Tick rate limiting
- `[channels]` - Buffer sizes
- `[performance]` - Latency and throughput targets

## Summary

The configuration system ensures:
- ✅ **No silent defaults** - config file always created on first run
- ✅ **User-editable** - TOML format is easy to read and modify
- ✅ **Auto-discovery** - `load_default_config()` finds the file automatically
- ✅ **Flexible** - Support for multiple config files
- ✅ **Clear logging** - You always know what's happening

**Most users just need**: `config = load_default_config()` and they're done!

# Configuration Directory

This directory contains pipeline configuration files.

## Structure

```
config/
└── pipeline/
    ├── default.toml           # Main configuration (auto-created)
    ├── development.toml       # Development settings (optional)
    ├── production.toml        # Production settings (optional)
    └── README.md              # This file
```

## Quick Start

The `default.toml` file is **automatically created** when you first load the configuration:

```julia
using TickDataPipeline

# This creates config/pipeline/default.toml if it doesn't exist
config = load_default_config()
```

## Customizing Configuration

1. **Let the system create the default file** (first run):
   ```julia
   config = load_default_config()
   ```

2. **Edit the file** in your text editor:
   ```
   config/pipeline/default.toml
   ```

3. **Reload** with your changes:
   ```julia
   config = load_default_config()
   ```

## Multiple Configurations

You can create multiple configuration files for different scenarios:

```toml
# config/pipeline/development.toml
[bar_processing]
enabled = false  # Disable bars for faster testing
ticks_per_bar = 21
bar_method = "boxcar"

# config/pipeline/production.toml
[bar_processing]
enabled = true
ticks_per_bar = 13
bar_method = "FIR"
normalization_window_bars = 200
```

Load them explicitly:

```julia
# Development
config = load_config_from_toml("config/pipeline/development.toml")

# Production
config = load_config_from_toml("config/pipeline/production.toml")
```

## Configuration Sections

A complete configuration file has these sections:

- **`pipeline_name`** - Identifier for this configuration
- **`[signal_processing]`** - Encoder, AGC, normalization settings
- **`[bar_processing]`** - Bar size, FIR filter, thresholds
- **`[flow_control]`** - Tick rate limiting
- **`[channels]`** - Buffer sizes for broadcasting
- **`[performance]`** - Latency and throughput targets

## Documentation

- **How-to guide**: `docs/howto/Configuration_Management.md`
- **Migration guide**: `docs/migration/Config_Path_Migration.md`
- **Default settings**: `config/pipeline/default.toml` (with comments)

## Notes

- The `default.toml` file is auto-created with sensible defaults
- All settings are documented with inline comments
- Changes take effect after reloading the configuration
- Keep configuration files in version control (except sensitive data)
- The `config/pipeline/` path avoids conflicts with other config files

## Getting Help

See `docs/howto/Configuration_Management.md` for complete documentation on the configuration system.

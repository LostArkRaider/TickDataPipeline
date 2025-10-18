# Configuration Path Migration Guide

## Summary of Changes

**Old path**: `config/default.toml`  
**New path**: `config/pipeline/default.toml`

**Why changed**:
1. **Avoid naming conflicts** - "default.toml" is too generic
2. **Better organization** - All pipeline configs in `/pipeline` subdirectory
3. **Auto-creation** - Config file automatically created if missing
4. **No silent defaults** - Always uses editable config file, never hardcoded values

## Quick Migration

### Simplest Approach (Recommended)

```julia
using TickDataPipeline

# This automatically creates config/pipeline/default.toml
config = load_default_config()
```

Then copy your custom settings from old `config/default.toml` to new `config/pipeline/default.toml`.

## Detailed Migration Steps

### Step 1: Update Code

**Before**:
```julia
config = load_config_from_toml("config/default.toml")
```

**After**:
```julia
config = load_default_config()
```

### Step 2: Move Custom Settings

If you have customizations in `config/default.toml`, copy them to the new location:

```bash
# Create directory (if needed)
mkdir -p config/pipeline

# Copy your old config
cp config/default.toml config/pipeline/default.toml
```

### Step 3: Verify

```julia
config = load_default_config()

# Check your settings are loaded
@show config.bar_processing.ticks_per_bar
@show config.bar_processing.bar_method
```

## What Changed

| Aspect | Old System | New System |
|--------|------------|------------|
| **Path** | `config/default.toml` | `config/pipeline/default.toml` |
| **Auto-creation** | No | Yes |
| **Silent defaults** | Yes (if file missing) | No (creates file with logging) |
| **API** | `load_config_from_toml(path)` | `load_default_config()` |
| **User control** | Must create file manually | Auto-created on first use |

## Benefits

✅ **No silent defaults** - Config file always created  
✅ **User-editable** - Always have a file to customize  
✅ **Clear logging** - Know exactly what's happening  
✅ **No conflicts** - Unique path avoids naming collisions  
✅ **Better organization** - All pipeline configs in one subdirectory

## Backward Compatibility

Old explicit paths still work:
```julia
# Still works
config = load_config_from_toml("config/default.toml")
```

But use the new API for better experience:
```julia
# Recommended
config = load_default_config()
```

## Summary

**Just use `load_default_config()` and you're done!**

The system will:
1. Check if `config/pipeline/default.toml` exists
2. Create it if missing (with clear logging)
3. Load your settings

No manual file management required!

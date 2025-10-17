# DERIVATIVE Encoder Configuration Fix

**Date**: October 16, 2025  
**Issue**: `UndefVarError(:derivative_scale, TickDataPipeline)`  
**Affected Files**: `PipelineConfig.jl`, `PipelineOrchestrator.jl`  
**Status**: ✅ FIXED

---

## Problem Summary

The DERIVATIVE encoder was added to `TickHotLoopF32.jl` but the corresponding configuration field was never added to `PipelineConfig.jl`. This caused `PipelineOrchestrator.jl` to reference an undefined variable `derivative_scale` when calling `process_tick_signal!()`.

### Error Message
```
Warning: Signal processing error: UndefVarError(:derivative_scale, TickDataPipeline)
└ @ TickDataPipeline C:\Users\Keith\source\repos\Julia\TickDataPipeline\src\PipelineOrchestrator.jl:138
```

---

## Root Cause

According to the DERIVATIVE encoder implementation checklist (`docs/howto/DERIVATIVE Encoder Implementation Checklist for TickHotLoopF32.md`), several changes were required:

1. ✅ Add `prev_normalized_ratio::Float32` to `TickHotLoopState` - **DONE**
2. ✅ Add `process_tick_derivative!()` function - **DONE**
3. ✅ Add `derivative_imag_scale::Float32` parameter to `process_tick_signal!()` - **DONE**
4. ❌ Add `derivative_imag_scale::Float32` to `SignalProcessingConfig` - **MISSING**
5. ❌ Update `PipelineOrchestrator.jl` to pass `sp.derivative_imag_scale` - **INCORRECT**

The checklist was partially followed, but the configuration changes were not completed.

---

## Changes Made

### 1. PipelineConfig.jl

#### Change 1.1: Add Field to SignalProcessingConfig Struct
```julia
struct SignalProcessingConfig
    # ... existing fields ...
    amc_carrier_period::Float32
    amc_lut_size::Int32
    derivative_imag_scale::Float32  # ← ADDED
```

#### Change 1.2: Add Default Value in Constructor
```julia
function SignalProcessingConfig(;
    # ... existing parameters ...
    amc_lut_size::Int32 = Int32(1024),
    derivative_imag_scale::Float32 = Float32(4.0)  # ← ADDED (default 4.0)
)
    new(agc_alpha, agc_min_scale, agc_max_scale, winsorize_delta_threshold,
        min_price, max_price, max_jump, encoder_type, cpm_modulation_index, cpm_lut_size,
        amc_carrier_period, amc_lut_size, derivative_imag_scale)  # ← ADDED to new()
end
```

#### Change 1.3: Load from TOML
```julia
signal_processing = SignalProcessingConfig(
    # ... existing fields ...
    amc_lut_size = Int32(get(sp, "amc_lut_size", 1024)),
    derivative_imag_scale = Float32(get(sp, "derivative_imag_scale", 4.0))  # ← ADDED
)
```

#### Change 1.4: Save to TOML
```julia
"signal_processing" => Dict{String,Any}(
    # ... existing fields ...
    "amc_lut_size" => config.signal_processing.amc_lut_size,
    "derivative_imag_scale" => config.signal_processing.derivative_imag_scale  # ← ADDED
),
```

#### Change 1.5: Add Validation
```julia
if sp.encoder_type == "derivative"
    if sp.derivative_imag_scale <= Float32(0.0)
        push!(errors, "derivative_imag_scale must be positive")
    end
end
```

#### Change 1.6: Update Validation Error Message
```julia
if sp.encoder_type != "hexad16" && sp.encoder_type != "cpm" && sp.encoder_type != "amc" && sp.encoder_type != "derivative"
    push!(errors, "encoder_type must be either \"hexad16\", \"cpm\", \"amc\", or \"derivative\"")
end
```

### 2. PipelineOrchestrator.jl

#### Change 2.1: Fix process_single_tick_through_pipeline!() - Line 138
**Before:**
```julia
process_tick_signal!(
    msg,
    pipeline_manager.tickhotloop_state,
    sp.agc_alpha,
    sp.agc_min_scale,
    sp.agc_max_scale,
    sp.winsorize_delta_threshold,
    sp.min_price,
    sp.max_price,
    sp.max_jump,
    sp.encoder_type,
    sp.cpm_modulation_index,
    derivative_scale  # ❌ UNDEFINED VARIABLE
)
```

**After:**
```julia
process_tick_signal!(
    msg,
    pipeline_manager.tickhotloop_state,
    sp.agc_alpha,
    sp.agc_min_scale,
    sp.agc_max_scale,
    sp.winsorize_delta_threshold,
    sp.min_price,
    sp.max_price,
    sp.max_jump,
    sp.encoder_type,
    sp.cpm_modulation_index,
    sp.derivative_imag_scale  # ✅ CORRECT
)
```

#### Change 2.2: Fix run_pipeline() - Line 271
Same change as above.

---

## Testing the Fix

### 1. Verify TickDataPipeline Package

```julia
cd("C:\\Users\\Keith\\source\\repos\\Julia\\TickDataPipeline")

# Activate environment
using Pkg
Pkg.activate(".")

# Test loading
using TickDataPipeline

# Test configuration
config = TickDataPipeline.create_default_config()
println("derivative_imag_scale: $(config.signal_processing.derivative_imag_scale)")
# Should print: derivative_imag_scale: 4.0

# Test validation
is_valid, errors = TickDataPipeline.validate_config(config)
println("Valid: $is_valid")
# Should print: Valid: true
```

### 2. Test with DERIVATIVE Encoder

```julia
using TickDataPipeline

# Create config with derivative encoder
config = TickDataPipeline.PipelineConfig(
    tick_file_path = "data/raw/test_ticks.txt",
    signal_processing = TickDataPipeline.SignalProcessingConfig(
        encoder_type = "derivative",
        derivative_imag_scale = Float32(4.0)
    )
)

# Create pipeline
split_mgr = TickDataPipeline.create_triple_split_manager()
consumer = TickDataPipeline.subscribe_consumer!(split_mgr, "test", TickDataPipeline.PRIORITY, Int32(1024))
pipeline_mgr = TickDataPipeline.create_pipeline_manager(config, split_mgr)

# Run pipeline
@async TickDataPipeline.run_pipeline!(pipeline_mgr, max_ticks=Int64(100))

# Check messages
for msg in consumer.channel
    println("Tick $(msg.tick_idx): z = $(msg.complex_signal)")
    if msg.tick_idx >= 10
        break
    end
end
```

### 3. Update Your Script

Your script (`complexbiquadga/scripts1014/pipeline_reduced_from_working.jl`) doesn't need any changes because it uses `load_config_from_toml()` which now properly loads the `derivative_imag_scale` field.

However, **you must ensure your config TOML file has this parameter**:

```toml
[signal_processing]
encoder_type = "amc"  # or "derivative" if you want to use that encoder
derivative_imag_scale = 4.0  # ADD THIS LINE if using derivative encoder
```

If the TOML file doesn't have it, the default value of `4.0` will be used.

---

## Configuration File Updates

### Default TOML (config/default.toml)

Add the following to the `[signal_processing]` section:

```toml
[signal_processing]
# ... existing parameters ...
encoder_type = "amc"  # Options: "hexad16", "cpm", "amc", "derivative"

# CPM encoder parameters
cpm_modulation_index = 0.5

# DERIVATIVE encoder parameters
derivative_imag_scale = 4.0  # Scaling for imaginary component (2.0-4.0 recommended)
```

---

## How This Happened

The DERIVATIVE encoder was added in stages:
1. First, the core processing logic was added to `TickHotLoopF32.jl`
2. The function signature was updated to accept `derivative_imag_scale::Float32`
3. BUT the configuration system was never updated to provide this parameter
4. `PipelineOrchestrator.jl` used a placeholder variable name `derivative_scale` instead of getting it from config

This is a common integration issue when adding new features - all layers of the stack need to be updated:
- ✅ Processing layer (TickHotLoopF32)
- ❌ Configuration layer (PipelineConfig) - **was missing**
- ❌ Orchestration layer (PipelineOrchestrator) - **used wrong variable**

---

## Verification Checklist

After the fix, verify:

- [x] `SignalProcessingConfig` has `derivative_imag_scale::Float32` field
- [x] Constructor has default value `Float32(4.0)`
- [x] `load_config_from_toml()` loads the field
- [x] `save_config_to_toml()` saves the field
- [x] `validate_config()` validates derivative encoder settings
- [x] `PipelineOrchestrator.jl` line 138 uses `sp.derivative_imag_scale`
- [x] `PipelineOrchestrator.jl` line 271 uses `sp.derivative_imag_scale`
- [ ] Config TOML files updated with `derivative_imag_scale` parameter
- [ ] Scripts tested and working without errors

---

## Next Steps

1. **Update all config TOML files** to include `derivative_imag_scale = 4.0` in the `[signal_processing]` section
2. **Re-run your script** - it should now work without the UndefVarError
3. **Test with derivative encoder** - set `encoder_type = "derivative"` in config to verify it works

---

## Example: Complete Signal Processing Config

```toml
[signal_processing]
# AGC parameters
agc_alpha = 0.0625
agc_min_scale = 4
agc_max_scale = 50

# Winsorization
winsorize_delta_threshold = 10

# Price validation
min_price = 39000
max_price = 44000
max_jump = 50

# Encoder selection
encoder_type = "amc"  # Options: "hexad16", "cpm", "amc", "derivative"

# CPM encoder (only used when encoder_type = "cpm")
cpm_modulation_index = 0.5
cpm_lut_size = 1024

# AMC encoder (only used when encoder_type = "amc")
amc_carrier_period = 16.0
amc_lut_size = 1024

# DERIVATIVE encoder (only used when encoder_type = "derivative")
derivative_imag_scale = 4.0
```

---

**Fix Status**: ✅ Complete  
**Files Modified**: 2  
**Tests Required**: Configuration loading, pipeline execution, derivative encoder operation

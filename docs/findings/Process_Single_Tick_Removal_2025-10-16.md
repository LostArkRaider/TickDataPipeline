# Removal of process_single_tick_through_pipeline! from Public API

**Date**: 2025-10-16
**Issue**: Confusion about intended usage patterns for pipeline processing
**Resolution**: Removed `process_single_tick_through_pipeline!` from public API

---

## Problem

`process_single_tick_through_pipeline!` was exported in the public API, creating confusion about the intended usage patterns. Users might incorrectly assume this function is for general use, when it was actually designed for internal use by `run_pipeline!`.

The function was intended primarily for **internal testing and orchestration**, not for production use.

---

## Changes Made

### 1. Removed from Exports

**File**: `src/TickDataPipeline.jl`

```julia
# BEFORE
export run_pipeline, run_pipeline!
export process_single_tick_through_pipeline!
export stop_pipeline!

# AFTER
export run_pipeline, run_pipeline!
export stop_pipeline!
# Note: process_single_tick_through_pipeline! is internal only (not exported)
```

### 2. Updated Function Documentation

**File**: `src/PipelineOrchestrator.jl`

```julia
"""
    process_single_tick_through_pipeline!(pipeline_manager, msg)

Process single tick through all pipeline stages with metrics.

**INTERNAL FUNCTION** - Not exported. Used internally by run_pipeline!.
For custom processing, use stream_expanded_ticks() directly with component functions.
```

### 3. Updated API Documentation

**File**: `docs/api/BarProcessor.md`

Added clear guidance on recommended usage patterns:

```julia
**Recommended Usage Patterns**:

1. **High-Level Interface** (Recommended for most use cases):
   stats = run_pipeline!(pipeline_mgr, max_ticks=1000)

2. **Manual Component Assembly** (For custom pipelines):
   tick_channel = stream_expanded_ticks(tick_file, 0.0)
   tick_state = create_tickhotloop_state()
   bar_state = create_bar_processor_state(config)

   for msg in tick_channel
       process_tick_signal!(msg, tick_state, ...)
       process_tick_for_bars!(msg, bar_state)
       broadcast_to_all!(split_manager, msg)
   end

**Note**: process_single_tick_through_pipeline! is an internal function (not exported).
```

---

## Recommended Usage Patterns

### Pattern 1: High-Level Interface (Recommended)

For most use cases, use `run_pipeline!`:

```julia
config = PipelineConfig(
    tick_file_path = "data/raw/YM 06-25.Last.txt",
    bar_processing = BarProcessingConfig(
        enabled = true,
        ticks_per_bar = Int32(144)
    )
)

split_mgr = create_triple_split_manager()
consumer = subscribe_consumer!(split_mgr, "consumer", MONITORING, Int32(4096))
pipeline_mgr = create_pipeline_manager(config, split_mgr)

# This handles everything: streaming, signal processing, bar processing, broadcasting
stats = run_pipeline!(pipeline_mgr, max_ticks = Int64(1000))
```

**Advantages**:
- Handles all pipeline stages automatically
- Includes metrics and performance tracking
- Lifecycle management (start/stop)
- Bar processing integrated
- Recommended for production

### Pattern 2: Manual Component Assembly (Advanced)

For custom pipelines or special requirements, use components directly:

```julia
# Setup
tick_channel = stream_expanded_ticks("data/raw/YM 06-25.Last.txt", 0.0)
tick_state = create_tickhotloop_state()
bar_state = create_bar_processor_state(bar_config)
split_mgr = create_triple_split_manager()

# Manual loop - you control everything
for msg in tick_channel
    # Stage 1: Tick signal processing
    process_tick_signal!(msg, tick_state, agc_alpha, agc_min_scale, ...)

    # Stage 2: Bar processing (optional)
    process_tick_for_bars!(msg, bar_state)

    # Your custom processing here
    if msg.bar_idx !== nothing
        custom_bar_handler(msg)
    end

    # Stage 3: Broadcasting
    broadcast_to_all!(split_mgr, msg)
end
```

**Advantages**:
- Full control over processing loop
- Can insert custom logic between stages
- Can skip stages (e.g., no broadcasting)
- Can add instrumentation/logging
- Useful for research and experimentation

**Use when**:
- Building custom analysis pipelines
- Need fine-grained control
- Implementing custom metrics
- Research and experimentation

---

## Impact Assessment

### Files Modified
1. `src/TickDataPipeline.jl` - Removed export
2. `src/PipelineOrchestrator.jl` - Updated docstring
3. `docs/api/BarProcessor.md` - Added usage guidance

### Code Still Works Internally
The function `process_single_tick_through_pipeline!` is still defined and used internally by `run_pipeline!` (line 365 in PipelineOrchestrator.jl). It's just not accessible from outside the package.

### Documentation Already Correct
All Phase 6 documentation already used the correct patterns:
- `docs/howto/Using_Bar_Processing.md` - Uses `run_pipeline!`
- `docs/api/BarProcessor.md` - Shows `stream_expanded_ticks` pattern
- `scripts/validate_bar_processing.jl` - Uses `run_pipeline!`

### Tests Still Pass
All tests continue to pass (3739 tests, 100% pass rate):
- Unit tests: 183/183 pass
- Integration tests: 3556/3556 pass

---

## Why This Change Matters

### Before (Confusing)
```julia
# Three ways to process ticks - which one to use?
run_pipeline!(pipeline_mgr, ...)                    # Option 1
run_pipeline(config, split_mgr, ...)                # Option 2
process_single_tick_through_pipeline!(mgr, msg)     # Option 3 (WRONG!)
```

### After (Clear)
```julia
# Two clear patterns:
run_pipeline!(pipeline_mgr, ...)                    # High-level (recommended)

# OR manual assembly:
for msg in stream_expanded_ticks(...)               # Component-level (advanced)
    process_tick_signal!(msg, ...)
    process_tick_for_bars!(msg, ...)
    broadcast_to_all!(...)
end
```

---

## Migration Guide

### If You Were Using process_single_tick_through_pipeline!

**Old Code** (no longer works):
```julia
for some_loop
    msg = get_message_somehow()
    process_single_tick_through_pipeline!(pipeline_mgr, msg)
end
```

**New Code** (use manual assembly):
```julia
tick_channel = stream_expanded_ticks(tick_file, 0.0)
tick_state = create_tickhotloop_state()
bar_state = create_bar_processor_state(config.bar_processing)
split_mgr = create_triple_split_manager()

for msg in tick_channel
    # Process through all stages
    process_tick_signal!(msg, tick_state, ...)
    process_tick_for_bars!(msg, bar_state)
    broadcast_to_all!(split_mgr, msg)
end
```

**Or Even Better** (use high-level interface):
```julia
# Let run_pipeline! handle everything
stats = run_pipeline!(pipeline_mgr, max_ticks=1000)
```

---

## Summary

- **Removed**: `process_single_tick_through_pipeline!` from public API
- **Reason**: Was causing confusion, intended for internal use only
- **Impact**: None on existing Phase 6 work (already used correct patterns)
- **Recommended**: Use `run_pipeline!` for most cases, `stream_expanded_ticks` loop for custom pipelines
- **Status**: All tests pass (3739/3739)

---

**Completion Date**: 2025-10-16
**Tests Status**: ✓ All passing (3739/3739)
**Documentation Status**: ✓ Updated and consistent

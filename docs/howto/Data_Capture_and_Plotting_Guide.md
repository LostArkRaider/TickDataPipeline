# Data Capture and Plotting User Guide

**TickDataPipeline v0.1.0**

---

## Table of Contents

1. [Overview](#overview)
2. [Data Capture Script](#data-capture-script)
3. [Plotting Script](#plotting-script)
4. [Analysis Scripts](#analysis-scripts)
5. [Common Workflows](#common-workflows)
6. [Troubleshooting](#troubleshooting)

---

## Overview

The TickDataPipeline includes tools for capturing, analyzing, and visualizing tick data processing:

- **stream_ticks_to_jld2.jl** - Captures processed ticks to JLD2 files
- **plot_jld2_data.jl** - Creates interactive HTML plots
- **analyze_winsorization.jl** - Analyzes normalization effectiveness
- **find_price_range.jl** - Discovers min/max prices in raw data
- **jld2_to_csv.jl** - Exports to CSV format

---

## Data Capture Script

**Location:** `scripts/stream_ticks_to_jld2.jl`

### Basic Usage

```bash
# Capture with current settings
julia --project=. scripts/stream_ticks_to_jld2.jl
```

### Configurable Settings

Edit the script to change these parameters:

#### 1. Input Tick File

**Line 11:**
```julia
const TICK_FILE = "data/raw/YM 06-25.Last.txt"
```

Change to your tick data file path.

#### 2. Tick Delay (Flow Control)

**Line 12:**
```julia
const TICK_DELAY_MS = Float64(0.0)  # No delay - max speed
```

**Common values:**
- `0.0` - Maximum speed (no delay)
- `0.1` - 100 microseconds between ticks
- `0.5` - 500 microseconds (good for testing AGC)
- `1.0` - 1 millisecond (10,000 ticks/second)

#### 3. Counter Display Interval

**Line 13:**
```julia
const COUNTER_INTERVAL = Int64(10000)
```

Shows progress every N ticks. Default 10,000.

#### 4. Number of Ticks to Capture

**Line 99:**
```julia
pipeline_task = @async run_pipeline!(pipeline_mgr)  # Capture ALL ticks
```

**To limit ticks:**
```julia
# Capture first 500K ticks
pipeline_task = @async run_pipeline!(pipeline_mgr, max_ticks = Int64(500000))

# Capture first 1M ticks
pipeline_task = @async run_pipeline!(pipeline_mgr, max_ticks = Int64(1000000))

# Capture first 2.5M ticks
pipeline_task = @async run_pipeline!(pipeline_mgr, max_ticks = Int64(2500000))
```

#### 5. Capture Specific Range (Advanced)

To capture only ticks within a specific range (e.g., ticks 2M to 3M):

**Lines 14-15 (add these constants):**
```julia
const START_TICK = Int64(2000000)  # Start at tick 2M
const MAX_TICKS = Int64(1000000)   # Capture 1M ticks (2M to 3M)
```

**Line 99:**
```julia
# Process enough ticks to reach the end of range
pipeline_task = @async run_pipeline!(pipeline_mgr, max_ticks = START_TICK + MAX_TICKS)
```

**Lines 107-109 (modify consumer filter):**
```julia
for msg in consumer.channel
    # Only collect if tick_idx is between START_TICK and (START_TICK + MAX_TICKS)
    if msg.tick_idx >= START_TICK && msg.tick_idx < (START_TICK + MAX_TICKS)
        collect_message!(collector, msg)
    end
end
```

### Output Files

Files are saved with timestamps:
```
data/jld2/processed_ticks_YYYYMMDD_HHMMSS.jld2
```

Example: `processed_ticks_20251005_143000.jld2`

### Signal Processing Parameters

These are configured in `src/PipelineConfig.jl`:

**Lines 32-38:**
```julia
agc_alpha::Float32 = Float32(0.125),           # AGC time constant (1/8)
agc_min_scale::Int32 = Int32(4),               # Minimum AGC scale
agc_max_scale::Int32 = Int32(50),              # Maximum AGC scale
winsorize_threshold::Float32 = Float32(3.0),   # Clip outliers beyond ±3σ
min_price::Int32 = Int32(36600),               # Minimum valid price
max_price::Int32 = Int32(43300),               # Maximum valid price
max_jump::Int32 = Int32(50)                     # Maximum single-tick jump
```

**AGC Alpha Values:**
- `0.0625` (1/16) - Slower adaptation (~73 samples for 99%)
- `0.125` (1/8) - Faster adaptation (~36 samples for 99%) **← Current**
- `0.25` (1/4) - Very fast adaptation (~18 samples for 99%)

---

## Plotting Script

**Location:** `scripts/plot_jld2_data.jl`

### Basic Usage

#### Plot First 10,000 Ticks (Default)
```bash
julia --project=. scripts/plot_jld2_data.jl
```

#### Plot Specific File
```bash
julia --project=. scripts/plot_jld2_data.jl data/jld2/processed_ticks_20251005_143000.jld2
```

### Command-Line Arguments

**Format:** `julia --project=. scripts/plot_jld2_data.jl [jld2_file] [start_tick] [num_ticks]`

**Arguments:**
1. `jld2_file` - Path to JLD2 file (optional, defaults to latest)
2. `start_tick` - Starting tick index (optional, default = 1)
3. `num_ticks` - Number of ticks to plot (optional, default = 10000, 0 = all)

### Examples

#### Plot First 50,000 Ticks
```bash
julia --project=. scripts/plot_jld2_data.jl data/jld2/processed_ticks_20251005_143000.jld2 1 50000
```

#### Plot Ticks 100,000 to 110,000
```bash
julia --project=. scripts/plot_jld2_data.jl data/jld2/processed_ticks_20251005_143000.jld2 100000 10000
```

#### Plot Ticks 2M to 2.01M (Investigating Flat Signals)
```bash
julia --project=. scripts/plot_jld2_data.jl data/jld2/processed_ticks_20251005_143000.jld2 2000000 10000
```

#### Plot ALL Ticks in File (No Sampling)
```bash
julia --project=. scripts/plot_jld2_data.jl data/jld2/processed_ticks_20251005_143000.jld2 1 0
```

### Plot Customization

Edit `scripts/plot_jld2_data.jl` to customize visualization:

#### 1. I/Q Signal Scaling

**Lines 67-68:**
```julia
complex_real_offset = (complex_real .* 6.0) .+ 1.0  # 6x scale, offset by +1.0
complex_imag_offset = (complex_imag .* 6.0) .- 1.0  # 6x scale, offset by -1.0
```

**Adjust scaling multiplier:**
- `6.0` - Current (makes ±0.5 appear as ±3.0)
- `10.0` - More visibility (±0.5 → ±5.0)
- `3.0` - Less scaling (±0.5 → ±1.5)

**Adjust offset for visual separation:**
- `±1.0` - Current separation (2.0 units apart)
- `±1.5` - More separation (3.0 units apart)
- `±0.5` - Less separation (1.0 unit apart)

#### 2. Plot Dimensions

**Lines 160-161:**
```julia
width = 1400,
height = 700
```

Change to fit your screen (e.g., `width = 1920, height = 1080`).

### Output Files

Plots are saved as HTML files:

**Naming convention:**
- Section plots: `[base_name]_plot_[start]_to_[end].html`
- All ticks: `[base_name]_plot_all.html`

Example:
```
data/jld2/processed_ticks_20251005_143000_plot_100000_to_110000.html
```

### Plot Features

The interactive HTML plot includes:

- **Left Y-axis (blue):** Raw price (scaled [0,1])
- **Right Y-axis (red):** Price delta, AGC scale, I/Q signals
- **Purple dotted line:** AGC normalization scale
- **Green line:** Complex Real (I signal, offset +1.0)
- **Orange line:** Complex Imag (Q signal, offset -1.0)
- **Red line:** Price delta (raw tick-to-tick change)

**Hover over data points** to see exact values and tick indices.

---

## Analysis Scripts

### Winsorization Analysis

**Location:** `scripts/analyze_winsorization.jl`

**Usage:**
```bash
# Analyze latest JLD2 file
julia --project=. scripts/analyze_winsorization.jl

# Analyze specific file
julia --project=. scripts/analyze_winsorization.jl data/jld2/processed_ticks_20251005_143000.jld2
```

**Output:**
- Normalized delta distribution statistics
- Percentile analysis (0.1% through 99.9%)
- Count and percentage of clipped ticks
- Threshold comparison (1σ through 5σ)
- Normality check (Gaussian distribution test)
- Recommendations for optimal threshold

**Example interpretation:**
```
Clips: 0.005% of normalized deltas
✓ GOOD: Very few outliers beyond 3σ (< 0.1%)
  Current threshold is appropriate.
```

### Price Range Finder

**Location:** `scripts/find_price_range.jl`

**Usage:**
```bash
# Find price range in default tick file
julia --project=. scripts/find_price_range.jl

# Find price range in specific file
julia --project=. scripts/find_price_range.jl data/raw/YM 06-25.Last.txt
```

**Output:**
```
Results:
  Min price: 36712
  Max price: 43148
  Price range: 6436

Recommended config settings:
  min_price = 36612
  max_price = 43248
```

Use these values to update `src/PipelineConfig.jl` lines 36-37.

### CSV Export

**Location:** `scripts/jld2_to_csv.jl`

**Usage:**
```bash
# Export latest JLD2 to CSV
julia --project=. scripts/jld2_to_csv.jl

# Export specific file
julia --project=. scripts/jld2_to_csv.jl data/jld2/processed_ticks_20251005_143000.jld2
```

**Output:** Creates CSV file with all 8 BroadcastMessage fields:
- tick_idx
- timestamp
- raw_price
- price_delta
- normalization
- complex_signal_real
- complex_signal_imag
- status_flag

---

## Common Workflows

### Workflow 1: Full Dataset Capture and Analysis

```bash
# Step 1: Find the actual price range
julia --project=. scripts/find_price_range.jl

# Step 2: Update config if needed (edit src/PipelineConfig.jl lines 36-37)

# Step 3: Capture all ticks at max speed
# (Ensure line 99 has: pipeline_task = @async run_pipeline!(pipeline_mgr))
julia --project=. scripts/stream_ticks_to_jld2.jl

# Step 4: Analyze winsorization effectiveness
julia --project=. scripts/analyze_winsorization.jl

# Step 5: Plot sections of interest
julia --project=. scripts/plot_jld2_data.jl data/jld2/processed_ticks_20251005_143000.jld2 1 50000
```

### Workflow 2: Investigate Flat I/Q Signals

```bash
# Step 1: Plot the problem area (e.g., ticks 2.2M to 2.3M)
julia --project=. scripts/plot_jld2_data.jl data/jld2/[file].jld2 2200000 100000

# Step 2: Check AGC behavior (purple line in plot)
# - If AGC stuck at 1.0 → price validation issue
# - If AGC stuck high → slow adaptation issue

# Step 3: Export to CSV for detailed analysis
julia --project=. scripts/jld2_to_csv.jl data/jld2/[file].jld2

# Step 4: Check status_flag column
# - FLAG_HOLDLAST (0x02) = price validation rejection
# - FLAG_CLIPPED (0x04) = winsorization clipping
```

### Workflow 3: Test AGC Time Constant Changes

```bash
# Step 1: Edit src/PipelineConfig.jl line 32
# Try different agc_alpha values: 0.0625 (1/16), 0.125 (1/8), 0.25 (1/4)

# Step 2: Capture same data section with different settings
julia --project=. scripts/stream_ticks_to_jld2.jl

# Step 3: Compare plots
julia --project=. scripts/plot_jld2_data.jl data/jld2/[file1].jld2 2000000 100000
julia --project=. scripts/plot_jld2_data.jl data/jld2/[file2].jld2 2000000 100000

# Step 4: Look for AGC (purple line) adaptation speed differences
```

### Workflow 4: Capture Specific Time Period

```bash
# Step 1: Identify tick range of interest from full capture

# Step 2: Edit scripts/stream_ticks_to_jld2.jl
# Add lines 14-15:
#   const START_TICK = Int64(2000000)
#   const MAX_TICKS = Int64(1000000)
# Modify line 99 and lines 107-109 (see "Capture Specific Range" above)

# Step 3: Run capture with slower tick rate for detailed observation
# Edit line 12: const TICK_DELAY_MS = Float64(0.5)
julia --project=. scripts/stream_ticks_to_jld2.jl

# Step 4: Plot the captured range
julia --project=. scripts/plot_jld2_data.jl data/jld2/[file].jld2 1 0
```

---

## Troubleshooting

### Issue: Flat I/Q Signals (Real = +1.0, Imag = -1.0 only)

**Symptoms:**
- Plot shows constant I/Q values (horizontal lines at offsets)
- AGC scale stuck at 1.0
- status_flag = 2 (FLAG_HOLDLAST)

**Root Cause:** Price validation rejecting ticks

**Solution:**
1. Run `julia --project=. scripts/find_price_range.jl`
2. Update `src/PipelineConfig.jl` lines 36-37 with wider range
3. Re-run capture

### Issue: Slow AGC Adaptation

**Symptoms:**
- AGC stays high after volatility decrease
- I/Q signals become tiny during low volatility
- Takes 500+ ticks to adapt

**Root Cause:** AGC time constant too slow

**Solution:**
1. Edit `src/PipelineConfig.jl` line 32
2. Increase `agc_alpha` from 0.0625 to 0.125 or 0.25
3. Re-run capture and compare

### Issue: No Plot File Generated

**Symptoms:**
- Script runs but no HTML file appears

**Root Cause:** JLD2 file path incorrect or file doesn't exist

**Solution:**
1. Check file exists: `ls data/jld2/*.jld2`
2. Use absolute path or run from project root
3. Verify output message shows correct path

### Issue: Plot Shows Sampled Data (Not All Points)

**Symptoms:**
- Plot note says "Plotting X points" but expected more

**Root Cause:** Using default 10,000 tick limit

**Solution:**
Use `num_ticks=0` to plot all:
```bash
julia --project=. scripts/plot_jld2_data.jl [file].jld2 1 0
```

### Issue: Winsorization Clipping Too Much/Too Little

**Symptoms:**
- Many ticks clipped (>1%)
- Or no clipping but outliers visible

**Root Cause:** Threshold mismatch with data distribution

**Solution:**
1. Run `julia --project=. scripts/analyze_winsorization.jl`
2. Check "Clips: X% of normalized deltas"
3. If >1%, increase threshold in `src/PipelineConfig.jl` line 35
4. If <0.01% and outliers present, decrease threshold

### Issue: Price Delta Range Mismatch with Volume

**Symptoms:**
- I/Q signals have range ±3.0 instead of ±0.5

**Root Cause:** Missing 1/6 scaling in TickHotLoopF32.jl

**Solution:**
Verify `src/TickHotLoopF32.jl` lines 227-231 include:
```julia
normalized_ratio = normalized_ratio / Float32(6.0)
normalization_factor = Float32(agc_scale) * Float32(6.0)
```

---

## File References

### Configuration Files
- `src/PipelineConfig.jl` - Signal processing parameters
  - Line 32: agc_alpha
  - Lines 33-34: agc_min_scale, agc_max_scale
  - Line 35: winsorize_threshold
  - Lines 36-37: min_price, max_price
  - Line 38: max_jump

### Data Capture Script
- `scripts/stream_ticks_to_jld2.jl`
  - Line 11: TICK_FILE
  - Line 12: TICK_DELAY_MS
  - Line 13: COUNTER_INTERVAL
  - Line 99: max_ticks parameter
  - Lines 107-109: Consumer message filter

### Plotting Script
- `scripts/plot_jld2_data.jl`
  - Lines 67-68: I/Q scaling and offsets
  - Lines 160-161: Plot dimensions
  - Lines 187-197: Command-line argument parsing

### Signal Processing
- `src/TickHotLoopF32.jl`
  - Line 10: QUAD4 constant
  - Lines 217-231: Normalization and scaling
  - Line 228: Phase calculation
  - Line 231: Normalization factor

---

## Quick Reference

### Most Common Commands

```bash
# Capture all ticks at max speed
julia --project=. scripts/stream_ticks_to_jld2.jl

# Plot first 50K ticks of latest file
julia --project=. scripts/plot_jld2_data.jl [latest_file] 1 50000

# Analyze winsorization of latest capture
julia --project=. scripts/analyze_winsorization.jl

# Find price range in raw data
julia --project=. scripts/find_price_range.jl

# Export to CSV for Excel/Python analysis
julia --project=. scripts/jld2_to_csv.jl
```

### Key Parameter Values

| Parameter | Location | Default | Typical Range |
|-----------|----------|---------|---------------|
| agc_alpha | PipelineConfig.jl:32 | 0.125 | 0.0625 - 0.25 |
| min_price | PipelineConfig.jl:36 | 36600 | Data-dependent |
| max_price | PipelineConfig.jl:37 | 43300 | Data-dependent |
| winsorize_threshold | PipelineConfig.jl:35 | 3.0 | 2.0 - 5.0 |
| tick_delay_ms | stream_ticks_to_jld2.jl:12 | 0.0 | 0.0 - 1.0 |
| I/Q scale | plot_jld2_data.jl:67-68 | 6.0 | 3.0 - 10.0 |

---

**Last Updated:** 2025-10-05
**Version:** 1.0
**TickDataPipeline:** v0.1.0

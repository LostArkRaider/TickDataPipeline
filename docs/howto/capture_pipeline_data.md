# Capture Pipeline Data to JLD2

**Script**: `scripts/capture_pipeline_data.jl`

Captures tick or bar data from the pipeline to timestamped JLD2 files for analysis and plotting.

**Note**: This script can be used from any Julia project that has TickDataPipeline installed. It automatically loads configuration from the installed package's `config/default.toml` file.

## Command Line Arguments

1. **mode** - `ticks` or `bars` (which data to capture)
2. **tick_start** - Starting tick index (skips first N ticks)
3. **num_records** - Number of records to capture (ticks or bars)

## Syntax

```bash
julia --project=. scripts/capture_pipeline_data.jl [mode] [tick_start] [num_records]
```

## Examples

```bash
# Capture 1000 ticks starting from beginning (tick 0)
julia --project=. scripts/capture_pipeline_data.jl ticks 0 1000

# Capture 500 bars starting from tick 10000
julia --project=. scripts/capture_pipeline_data.jl bars 10000 500

# Capture 100 ticks starting from tick 5000
julia --project=. scripts/capture_pipeline_data.jl ticks 5000 100
```

## Output

Files are saved to `data/jld2/` with timestamped filenames:
- `ticks_20251017_001517_start0_n1000.jld2`
- `bars_20251017_001537_start10000_n500.jld2`

## Loading Data

```julia
using JLD2
data = load("data/jld2/ticks_20251017_001517_start0_n1000.jld2", "data")

# Access columns
tick_indices = data["tick_idx"]
prices = data["raw_price"]
signals_real = data["complex_signal_real"]
```

## Data Fields

**Tick Mode** (7 fields):
- `tick_idx`, `raw_price`, `price_delta`
- `complex_signal_real`, `complex_signal_imag`
- `normalization`, `status_flag`

**Bar Mode** (11 fields):
- `bar_idx`, `bar_open_raw`, `bar_high_raw`, `bar_low_raw`, `bar_close_raw`
- `bar_volume`, `bar_ticks`
- `bar_complex_signal_real`, `bar_complex_signal_imag`
- `bar_normalization`, `bar_flags`

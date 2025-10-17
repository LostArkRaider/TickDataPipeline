# scripts/capture_pipeline_data.jl - Capture tick or bar data to JLD2 file
# Usage: julia --project=. scripts/capture_pipeline_data.jl [ticks|bars] [tick_start] [num_records]
#
# This script can be used from any Julia project that has TickDataPipeline installed.
# It automatically loads configuration from the installed package's config/default.toml file.
#
# Arguments:
#   mode        - "ticks" or "bars" - which data to capture
#   tick_start  - Starting tick index (skip first N ticks)
#   num_records - Number of records to capture (ticks or bars depending on mode)
#
# Output: Timestamped JLD2 file in data/jld2/ directory (relative to current working directory)
#
# File Schema (columnar format for easy CSV export and plotting):
#   Dict(
#       "tick_idx" => [...],
#       "raw_price" => [...],
#       ...
#       # Future: add filter outputs here
#       # "filter1_param1" => [...], "filter1_param2" => [...], etc.
#   )

using TickDataPipeline
using JLD2
using Dates
using Printf

# Parse command line arguments
function parse_args()
    if length(ARGS) != 3
        println("Usage: julia --project=. scripts/capture_pipeline_data.jl [ticks|bars] [tick_start] [num_records]")
        println()
        println("Arguments:")
        println("  mode        - 'ticks' or 'bars' - which data to capture")
        println("  tick_start  - Starting tick index (skip first N ticks)")
        println("  num_records - Number of records to capture")
        println()
        println("Examples:")
        println("  julia --project=. scripts/capture_pipeline_data.jl ticks 0 1000")
        println("  julia --project=. scripts/capture_pipeline_data.jl bars 10000 500")
        exit(1)
    end

    mode = lowercase(ARGS[1])
    if mode ∉ ["ticks", "bars"]
        println("ERROR: mode must be 'ticks' or 'bars', got: $mode")
        exit(1)
    end

    tick_start = parse(Int64, ARGS[2])
    num_records = parse(Int64, ARGS[3])

    if tick_start < 0
        println("ERROR: tick_start must be >= 0, got: $tick_start")
        exit(1)
    end

    if num_records <= 0
        println("ERROR: num_records must be > 0, got: $num_records")
        exit(1)
    end

    return mode, tick_start, num_records
end

# Capture tick data (all tick fields except timestamp)
function capture_tick_data(consumer, num_records::Int64)
    # Preallocate arrays for tick fields
    tick_idx = Vector{Int32}(undef, num_records)
    raw_price = Vector{Int32}(undef, num_records)
    price_delta = Vector{Int32}(undef, num_records)
    complex_signal_real = Vector{Float32}(undef, num_records)
    complex_signal_imag = Vector{Float32}(undef, num_records)
    normalization = Vector{Float32}(undef, num_records)
    status_flag = Vector{UInt8}(undef, num_records)

    count = Int64(0)
    for msg in consumer.channel
        count += 1

        # Store tick fields
        tick_idx[count] = msg.tick_idx
        raw_price[count] = msg.raw_price
        price_delta[count] = msg.price_delta
        complex_signal_real[count] = real(msg.complex_signal)
        complex_signal_imag[count] = imag(msg.complex_signal)
        normalization[count] = msg.normalization
        status_flag[count] = msg.status_flag

        if count >= num_records
            break
        end
    end

    # Return columnar format (easy to extend with filter outputs)
    return Dict(
        "tick_idx" => tick_idx,
        "raw_price" => raw_price,
        "price_delta" => price_delta,
        "complex_signal_real" => complex_signal_real,
        "complex_signal_imag" => complex_signal_imag,
        "normalization" => normalization,
        "status_flag" => status_flag
        # Future: add filter outputs here
        # "filter1_param1" => filter1_param1,
        # "filter1_param2" => filter1_param2,
        # ...
    )
end

# Capture bar data (all bar fields except timestamp)
function capture_bar_data(consumer, num_records::Int64)
    # Preallocate arrays for bar fields
    bar_idx = Vector{Union{Int64, Nothing}}(undef, num_records)
    bar_open_raw = Vector{Int32}(undef, num_records)
    bar_high_raw = Vector{Int32}(undef, num_records)
    bar_low_raw = Vector{Int32}(undef, num_records)
    bar_close_raw = Vector{Int32}(undef, num_records)
    bar_volume = Vector{Int32}(undef, num_records)
    bar_ticks = Vector{Int32}(undef, num_records)
    bar_complex_signal_real = Vector{Float32}(undef, num_records)
    bar_complex_signal_imag = Vector{Float32}(undef, num_records)
    bar_normalization = Vector{Float32}(undef, num_records)
    bar_flags = Vector{UInt8}(undef, num_records)

    count = Int64(0)
    bars_captured = Int64(0)

    for msg in consumer.channel
        # Only capture messages that have bar data
        if msg.bar_idx !== nothing
            bars_captured += 1

            # Store bar fields
            bar_idx[bars_captured] = msg.bar_idx
            bar_open_raw[bars_captured] = msg.bar_open_raw
            bar_high_raw[bars_captured] = msg.bar_high_raw
            bar_low_raw[bars_captured] = msg.bar_low_raw
            bar_close_raw[bars_captured] = msg.bar_close_raw
            bar_volume[bars_captured] = msg.bar_volume
            bar_ticks[bars_captured] = msg.bar_ticks
            bar_complex_signal_real[bars_captured] = real(msg.bar_complex_signal)
            bar_complex_signal_imag[bars_captured] = imag(msg.bar_complex_signal)
            bar_normalization[bars_captured] = msg.bar_normalization
            bar_flags[bars_captured] = msg.bar_flags

            if bars_captured >= num_records
                break
            end
        end

        count += 1
    end

    # Trim arrays to actual number of bars captured
    return Dict(
        "bar_idx" => bar_idx[1:bars_captured],
        "bar_open_raw" => bar_open_raw[1:bars_captured],
        "bar_high_raw" => bar_high_raw[1:bars_captured],
        "bar_low_raw" => bar_low_raw[1:bars_captured],
        "bar_close_raw" => bar_close_raw[1:bars_captured],
        "bar_volume" => bar_volume[1:bars_captured],
        "bar_ticks" => bar_ticks[1:bars_captured],
        "bar_complex_signal_real" => bar_complex_signal_real[1:bars_captured],
        "bar_complex_signal_imag" => bar_complex_signal_imag[1:bars_captured],
        "bar_normalization" => bar_normalization[1:bars_captured],
        "bar_flags" => bar_flags[1:bars_captured]
        # Future: add filter outputs here
        # "filter1_param1" => filter1_param1,
        # "filter1_param2" => filter1_param2,
        # ...
    )
end

# Main execution
function main()
    println("="^80)
    println("Pipeline Data Capture")
    println("="^80)
    println()

    # Parse arguments
    mode, tick_start, num_records = parse_args()

    println("Configuration:")
    println("  Mode: $mode")
    println("  Starting tick: $tick_start")
    println("  Records to capture: $num_records")
    println()

    # Load configuration from installed TickDataPipeline package
    pkg_dir = dirname(dirname(pathof(TickDataPipeline)))
    config_path = joinpath(pkg_dir, "config", "default.toml")
    config = load_config_from_toml(config_path)

    # Verify bar processing is enabled if capturing bars
    if mode == "bars" && !config.bar_processing.enabled
        println("ERROR: Bar processing is disabled in config. Enable it in config/default.toml")
        exit(1)
    end

    println("Pipeline setup:")
    println("  Tick file: $(config.tick_file_path)")
    println("  Bar processing: $(config.bar_processing.enabled ? "enabled" : "disabled")")
    if mode == "bars"
        println("  Ticks per bar: $(config.bar_processing.ticks_per_bar)")
    end
    println()

    # Create pipeline manager and consumer
    split_mgr = create_triple_split_manager()
    consumer = subscribe_consumer!(split_mgr, "data_capture", MONITORING, Int32(16384))
    pipeline_mgr = create_pipeline_manager(config, split_mgr)

    # Calculate total ticks needed
    total_ticks = if mode == "bars"
        # Need enough ticks to generate num_records bars
        # Add extra buffer for warmup
        tick_start + (num_records * config.bar_processing.ticks_per_bar) + config.bar_processing.ticks_per_bar
    else
        tick_start + num_records
    end

    println("Starting pipeline...")
    println("  Total ticks to process: $total_ticks")
    println()

    # Run pipeline in background
    pipeline_task = @async run_pipeline!(pipeline_mgr, max_ticks=total_ticks)

    # Skip to start position
    if tick_start > 0
        println("Skipping to tick $tick_start...")
        for i in 1:tick_start
            take!(consumer.channel)
        end
        println("✓ Positioned at tick $tick_start")
        println()
    end

    # Capture data
    println("Capturing $(num_records) $(mode)...")
    data = if mode == "ticks"
        capture_tick_data(consumer, num_records)
    else
        capture_bar_data(consumer, num_records)
    end

    println("✓ Captured $(num_records) $(mode)")
    println()

    # Wait for pipeline to complete
    wait(pipeline_task)

    # Create output directory if needed
    output_dir = "data/jld2"
    if !isdir(output_dir)
        mkpath(output_dir)
        println("Created directory: $output_dir")
    end

    # Generate timestamped filename
    timestamp = Dates.format(now(), "yyyymmdd_HHMMSS")
    filename = joinpath(output_dir, "$(mode)_$(timestamp)_start$(tick_start)_n$(num_records).jld2")

    # Save to JLD2 (no compression)
    println("Saving to JLD2...")
    jldsave(filename; data, compress=false)

    println("✓ Saved to: $filename")
    println()

    # Print summary
    println("="^80)
    println("CAPTURE COMPLETE")
    println("="^80)
    println()
    println("Summary:")
    println("  Mode: $mode")
    println("  Records captured: $num_records")
    println("  Fields captured: $(length(data))")
    println("  Output file: $filename")
    println("  File size: $(round(filesize(filename) / 1024 / 1024, digits=2)) MB")
    println()

    # Show field names
    println("Fields in file:")
    for field in sort(collect(keys(data)))
        println("  - $field")
    end
    println()

    println("="^80)
    println("To load this data:")
    println("  data = load(\"$filename\", \"data\")")
    println("="^80)
end

# Run main
main()

#!/usr/bin/env julia

# Export JLD2 data to CSV file
# Usage: julia --project=. scripts/jld2_to_csv.jl [jld2_file]

using JLD2
using CSV
using DataFrames

"""
Convert JLD2 file to CSV
"""
function jld2_to_csv(jld2_file::String)
    println("Loading data from: $jld2_file")
    data = load(jld2_file)

    println("Total ticks: $(data["total_ticks"])")

    # Create DataFrame from the data
    df = DataFrame(
        tick_idx = data["tick_idx"],
        timestamp = data["timestamp"],
        raw_price = data["raw_price"],
        price_delta = data["price_delta"],
        normalization = data["normalization"],
        complex_signal_real = data["complex_signal_real"],
        complex_signal_imag = data["complex_signal_imag"],
        status_flag = data["status_flag"]
    )

    # Generate output filename
    csv_file = replace(jld2_file, ".jld2" => ".csv")

    println("Writing CSV to: $csv_file")
    CSV.write(csv_file, df)

    println("Export complete!")
    println("Rows written: $(nrow(df))")

    return csv_file
end

"""
Find the most recent JLD2 file in data/jld2/
"""
function find_latest_jld2()::String
    jld2_dir = "data/jld2"
    files = filter(f -> endswith(f, ".jld2"), readdir(jld2_dir))

    if isempty(files)
        error("No JLD2 files found in $jld2_dir")
    end

    # Sort by filename (timestamp embedded) and get latest
    latest = last(sort(files))
    return joinpath(jld2_dir, latest)
end

# Main execution
function main()
    if length(ARGS) > 0
        jld2_file = ARGS[1]
    else
        jld2_file = find_latest_jld2()
    end

    if !isfile(jld2_file)
        error("File not found: $jld2_file")
    end

    jld2_to_csv(jld2_file)
end

# Run if called as script
if abspath(PROGRAM_FILE) == @__FILE__
    main()
else
    # Being included/loaded, export for interactive use
    println("jld2_to_csv() function available")
    println("Usage: jld2_to_csv(\"path/to/file.jld2\")")
end

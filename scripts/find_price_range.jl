#!/usr/bin/env julia

# Find min/max raw price in tick data file
# Usage: julia --project=. scripts/find_price_range.jl [tick_file]

using TickDataPipeline

"""
Find min and max raw price (Last) in tick data file

# Arguments
- `tick_file::String`: Path to tick data file
"""
function find_price_range(tick_file::String)
    if !isfile(tick_file)
        error("File not found: $tick_file")
    end

    println("="^70)
    println("Price Range Analysis")
    println("="^70)
    println("\nAnalyzing file: $tick_file")

    min_price = typemax(Int32)
    max_price = typemin(Int32)
    total_lines = 0
    valid_lines = 0

    open(tick_file, "r") do file
        for line in eachline(file)
            total_lines += 1

            # Skip empty lines
            if isempty(strip(line))
                continue
            end

            # Parse tick line
            parsed = parse_tick_line(line)
            if parsed === nothing
                continue
            end

            (timestamp_str, bid, ask, last, volume) = parsed
            valid_lines += 1

            # Track min/max
            if last < min_price
                min_price = last
            end
            if last > max_price
                max_price = last
            end
        end
    end

    println("\nResults:")
    println("  Total lines: $total_lines")
    println("  Valid ticks: $valid_lines")
    println("  Min price: $min_price")
    println("  Max price: $max_price")
    println("  Price range: $(max_price - min_price)")

    println("\nRecommended config settings:")
    margin = 100  # Add margin for safety
    println("  min_price = $(min_price - margin)")
    println("  max_price = $(max_price + margin)")

    println("\n" * "="^70)

    return (min_price, max_price)
end

# Main execution
function main()
    if length(ARGS) > 0
        tick_file = ARGS[1]
    else
        tick_file = "data/raw/YM 06-25.Last.txt"
    end

    find_price_range(tick_file)
end

# Run if called as script
if abspath(PROGRAM_FILE) == @__FILE__
    main()
else
    println("find_price_range() function available")
    println("Usage: find_price_range(\"path/to/tick_file.txt\")")
end

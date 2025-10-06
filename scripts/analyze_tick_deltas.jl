#!/usr/bin/env julia

# Analyze tick-to-tick price delta distribution
# Computes percentile statistics for winsorization threshold selection
# Usage: julia --project=. scripts/analyze_tick_deltas.jl

using Statistics
using Printf

# Configuration
const TICK_FILE = "data/raw/YM 06-25.Last.txt"

# Parse a single tick line
# Format: YYYYMMDD HHMMSS NNNNNNN;last;bid;ask;volume
function parse_tick_line(line::String)
    parts = split(line, ';')
    if length(parts) < 2
        return nothing
    end

    # Extract 'last' field (second field after semicolon)
    last_str = parts[2]
    last_price = tryparse(Int32, last_str)

    return last_price
end

# Read all ticks and compute deltas
function analyze_tick_deltas()
    println("Reading tick file: $(TICK_FILE)")

    deltas = Int32[]
    abs_deltas = Int32[]
    last_price = nothing
    tick_count = Int64(0)
    invalid_count = Int64(0)

    open(TICK_FILE, "r") do file
        for line in eachline(file)
            tick_count += Int64(1)

            # Progress indicator every 100k ticks
            if tick_count % 100000 == 0
                print("\rProcessing: $(tick_count) ticks...")
                flush(stdout)
            end

            # Parse current tick
            current_price = parse_tick_line(line)

            if current_price === nothing
                invalid_count += Int64(1)
                continue
            end

            # Compute delta if we have a previous price
            if last_price !== nothing
                delta = current_price - last_price
                push!(deltas, delta)
                push!(abs_deltas, abs(delta))
            end

            last_price = current_price
        end
    end

    println("\rProcessing complete: $(tick_count) ticks")
    println("Invalid ticks: $(invalid_count)")
    println("Valid deltas computed: $(length(deltas))")
    println()

    return deltas, abs_deltas
end

# Compute percentile table
function compute_percentile_table(deltas::Vector{Int32}, abs_deltas::Vector{Int32})
    println("=" ^ 80)
    println("TICK DELTA PERCENTILE ANALYSIS")
    println("=" ^ 80)
    println()

    # Basic statistics
    println("BASIC STATISTICS:")
    println("-" ^ 80)
    @printf("Total deltas:          %12d\n", length(deltas))
    @printf("Mean delta:            %12.4f\n", mean(deltas))
    @printf("Std dev delta:         %12.4f\n", std(deltas))
    @printf("Mean abs delta:        %12.4f\n", mean(abs_deltas))
    @printf("Std dev abs delta:     %12.4f\n", std(abs_deltas))
    @printf("Min delta:             %12d\n", minimum(deltas))
    @printf("Max delta:             %12d\n", maximum(deltas))
    println()

    # Percentile analysis for signed deltas
    println("SIGNED DELTA PERCENTILES:")
    println("-" ^ 80)
    @printf("%-15s %12s %12s\n", "Percentile", "Delta Value", "Count Beyond")
    println("-" ^ 80)

    percentiles = [0.1, 0.5, 1.0, 2.5, 5.0, 10.0, 25.0, 50.0, 75.0, 90.0, 95.0, 97.5, 99.0, 99.5, 99.9]

    for p in percentiles
        value = quantile(deltas, p / 100.0)
        count_beyond = sum(deltas .> value)
        @printf("%-15s %12.2f %12d\n", "$(p)%", value, count_beyond)
    end
    println()

    # Percentile analysis for absolute deltas
    println("ABSOLUTE DELTA PERCENTILES:")
    println("-" ^ 80)
    @printf("%-15s %12s %12s %12s\n", "Percentile", "|Delta| Value", "Count Beyond", "% Beyond")
    println("-" ^ 80)

    for p in percentiles
        value = quantile(abs_deltas, p / 100.0)
        count_beyond = sum(abs_deltas .> value)
        pct_beyond = (count_beyond / length(abs_deltas)) * 100.0
        @printf("%-15s %12.2f %12d %11.4f%%\n", "$(p)%", value, count_beyond, pct_beyond)
    end
    println()

    # Zero delta analysis
    zero_count = sum(deltas .== 0)
    zero_pct = (zero_count / length(deltas)) * 100.0
    println("ZERO DELTA ANALYSIS:")
    println("-" ^ 80)
    @printf("Zero deltas:           %12d (%.4f%%)\n", zero_count, zero_pct)
    println()

    # Extreme value analysis
    println("EXTREME VALUE ANALYSIS:")
    println("-" ^ 80)
    thresholds = [1, 2, 3, 5, 10, 20, 50, 100]

    for thresh in thresholds
        count = sum(abs_deltas .> thresh)
        pct = (count / length(abs_deltas)) * 100.0
        @printf("|Delta| > %-3d:         %12d (%.4f%%)\n", thresh, count, pct)
    end
    println()

    # Winsorization recommendations
    println("=" ^ 80)
    println("WINSORIZATION THRESHOLD RECOMMENDATIONS:")
    println("=" ^ 80)
    println()

    # Find thresholds that clip specific percentages
    target_clip_pcts = [0.01, 0.05, 0.1, 0.5, 1.0, 2.0, 5.0]

    println("Threshold to clip specific percentage of data:")
    println("-" ^ 80)
    @printf("%-20s %12s %12s\n", "Target Clip %", "Threshold", "Actual Clip %")
    println("-" ^ 80)

    for target_pct in target_clip_pcts
        # Find threshold that clips approximately target_pct
        target_percentile = 100.0 - target_pct
        threshold = quantile(abs_deltas, target_percentile / 100.0)
        actual_count = sum(abs_deltas .> threshold)
        actual_pct = (actual_count / length(abs_deltas)) * 100.0

        @printf("%-20.2f%% %12.2f %11.4f%%\n", target_pct, threshold, actual_pct)
    end
    println()

    # Specific recommendations
    println("RECOMMENDED THRESHOLDS:")
    println("-" ^ 80)

    # Conservative: 99.9th percentile (clip 0.1%)
    thresh_999 = ceil(Int32, quantile(abs_deltas, 0.999))
    println("Conservative (clip 0.1%):  |delta| > $(thresh_999)")

    # Moderate: 99th percentile (clip 1%)
    thresh_99 = ceil(Int32, quantile(abs_deltas, 0.99))
    println("Moderate (clip 1.0%):      |delta| > $(thresh_99)")

    # Aggressive: 95th percentile (clip 5%)
    thresh_95 = ceil(Int32, quantile(abs_deltas, 0.95))
    println("Aggressive (clip 5.0%):    |delta| > $(thresh_95)")

    println()
    println("=" ^ 80)
end

# Main execution
function main()
    deltas, abs_deltas = analyze_tick_deltas()

    if length(deltas) == 0
        println("ERROR: No valid deltas computed")
        return
    end

    compute_percentile_table(deltas, abs_deltas)
end

# Run
main()

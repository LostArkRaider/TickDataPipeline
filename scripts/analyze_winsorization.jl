#!/usr/bin/env julia

# Analyze winsorization effectiveness
# Compares actual data distribution against winsorization threshold
# Usage: julia --project=. scripts/analyze_winsorization.jl [jld2_file]

using JLD2
using Statistics

"""
Analyze winsorization effectiveness on processed tick data

# Arguments
- `jld2_file::String`: Path to JLD2 file
"""
function analyze_winsorization(jld2_file::String)
    println("="^70)
    println("Winsorization Analysis")
    println("="^70)
    println("\nLoading data from: $jld2_file")
    data = load(jld2_file)

    total_ticks = data["total_ticks"]
    price_delta = data["price_delta"]
    normalization = data["normalization"]
    status_flag = data["status_flag"]

    println("Total ticks: $total_ticks")

    # Calculate normalized ratios (what went into winsorization)
    normalized_ratios = Float32.(price_delta) ./ normalization

    # Filter out zeros and initial ticks
    valid_mask = (price_delta .!= 0) .& (normalization .> 1.0f0)
    valid_ratios = normalized_ratios[valid_mask]

    println("\n" * "="^70)
    println("Normalized Delta Distribution (input to winsorization)")
    println("="^70)

    # Statistics
    μ = mean(valid_ratios)
    σ = std(valid_ratios)

    println("\nBasic Statistics:")
    println("  Count (non-zero): $(length(valid_ratios))")
    println("  Mean (μ): $(round(μ, digits=6))")
    println("  Std Dev (σ): $(round(σ, digits=6))")
    println("  Min: $(round(minimum(valid_ratios), digits=4))")
    println("  Max: $(round(maximum(valid_ratios), digits=4))")

    # Percentiles
    println("\nPercentiles:")
    percentiles = [0.1, 0.5, 1.0, 5.0, 10.0, 25.0, 50.0, 75.0, 90.0, 95.0, 99.0, 99.5, 99.9]
    for p in percentiles
        val = quantile(valid_ratios, p/100.0)
        println("  $(lpad(string(p), 5))%: $(round(val, digits=4))")
    end

    # Count clipped ticks
    FLAG_CLIPPED = UInt8(0x04)
    clipped_count = count(x -> (x & FLAG_CLIPPED) != 0, status_flag)
    clipped_pct = (clipped_count / total_ticks) * 100.0

    println("\n" * "="^70)
    println("Winsorization Impact")
    println("="^70)
    println("\nClipped Ticks:")
    println("  Count: $clipped_count")
    println("  Percentage: $(round(clipped_pct, digits=2))%")

    # Analyze different threshold values
    println("\n" * "="^70)
    println("Threshold Analysis")
    println("="^70)
    println("\nIf we used different thresholds:")
    println("\n  Threshold  |  Outliers Clipped  |  % of Data")
    println("  " * "-"^50)

    thresholds = [1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 5.0]
    for threshold in thresholds
        outliers = count(x -> abs(x) > threshold, valid_ratios)
        outlier_pct = (outliers / length(valid_ratios)) * 100.0
        current = threshold == 3.0 ? " ← CURRENT" : ""
        println("  $(lpad(string(threshold), 9))σ  |  $(lpad(outliers, 17))  |  $(lpad(round(outlier_pct, digits=3), 8))%$current")
    end

    # Sigma multiples analysis
    println("\n" * "="^70)
    println("Data Distribution by Sigma Multiples")
    println("="^70)
    println("\n  Range        |  Count      |  % of Data  |  Cumulative %")
    println("  " * "-"^60)

    sigma_ranges = [
        (0.0, 0.5, "0.0σ - 0.5σ"),
        (0.5, 1.0, "0.5σ - 1.0σ"),
        (1.0, 1.5, "1.0σ - 1.5σ"),
        (1.5, 2.0, "1.5σ - 2.0σ"),
        (2.0, 2.5, "2.0σ - 2.5σ"),
        (2.5, 3.0, "2.5σ - 3.0σ"),
        (3.0, 3.5, "3.0σ - 3.5σ"),
        (3.5, 4.0, "3.5σ - 4.0σ"),
        (4.0, 100.0, "> 4.0σ")
    ]

    cumulative = 0.0
    for (low, high, label) in sigma_ranges
        count_in_range = count(x -> low <= abs(x) < high, valid_ratios)
        pct = (count_in_range / length(valid_ratios)) * 100.0
        cumulative += pct
        println("  $(rpad(label, 13))|  $(lpad(count_in_range, 10))  |  $(lpad(round(pct, digits=2), 9))%  |  $(lpad(round(cumulative, digits=2), 12))%")
    end

    # Recommendations
    println("\n" * "="^70)
    println("Recommendations")
    println("="^70)

    # Count outliers beyond different thresholds
    beyond_3sigma = count(x -> abs(x) > 3.0, valid_ratios)
    beyond_3sigma_pct = (beyond_3sigma / length(valid_ratios)) * 100.0

    println("\nCurrent threshold: 3.0σ")
    println("  Clips: $(round(beyond_3sigma_pct, digits=3))% of normalized deltas")

    if beyond_3sigma_pct < 0.1
        println("\n✓ GOOD: Very few outliers beyond 3σ (< 0.1%)")
        println("  Current threshold is appropriate.")
    elseif beyond_3sigma_pct < 1.0
        println("\n✓ OK: Moderate outliers beyond 3σ (< 1%)")
        println("  Current threshold is reasonable.")
    elseif beyond_3sigma_pct < 5.0
        println("\n⚠ WARNING: Significant outliers beyond 3σ (1-5%)")
        println("  Consider increasing threshold to 3.5σ or 4.0σ")
    else
        println("\n⚠ ALERT: Many outliers beyond 3σ (> 5%)")
        println("  Consider increasing threshold to 4.0σ or 5.0σ")
        println("  Or investigate data quality issues.")
    end

    # Check for normality assumption
    println("\nNormality Check:")
    println("  For normal distribution, expect:")
    println("    68.3% within ±1σ")
    println("    95.4% within ±2σ")
    println("    99.7% within ±3σ")

    within_1sigma = count(x -> abs(x) <= 1.0, valid_ratios) / length(valid_ratios) * 100.0
    within_2sigma = count(x -> abs(x) <= 2.0, valid_ratios) / length(valid_ratios) * 100.0
    within_3sigma = count(x -> abs(x) <= 3.0, valid_ratios) / length(valid_ratios) * 100.0

    println("\n  Actual distribution:")
    println("    $(round(within_1sigma, digits=1))% within ±1σ (expect 68.3%)")
    println("    $(round(within_2sigma, digits=1))% within ±2σ (expect 95.4%)")
    println("    $(round(within_3sigma, digits=1))% within ±3σ (expect 99.7%)")

    if within_3sigma < 95.0
        println("\n  ⚠ Distribution has heavy tails (non-normal)")
        println("    Data is more volatile than normal distribution predicts.")
    elseif within_3sigma > 99.5
        println("\n  ✓ Distribution closely matches normal (Gaussian)")
    else
        println("\n  ✓ Distribution is reasonably normal")
    end

    println("\n" * "="^70)
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

    analyze_winsorization(jld2_file)
end

# Run if called as script
if abspath(PROGRAM_FILE) == @__FILE__
    main()
else
    # Being included/loaded, export for interactive use
    println("analyze_winsorization() function available")
    println("Usage: analyze_winsorization(\"path/to/file.jld2\")")
end

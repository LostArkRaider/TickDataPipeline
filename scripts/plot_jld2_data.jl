#!/usr/bin/env julia

# Plot BroadcastMessage data from JLD2 file
# Creates interactive HTML plot with dual y-axes
# Usage: julia --project=. scripts/plot_jld2_data.jl [jld2_file]

using JLD2
using PlotlyJS

"""
Load and plot tick data from JLD2 file

# Arguments
- `jld2_file::String`: Path to JLD2 file (default: latest in data/jld2/)
- `start_tick::Int`: Starting tick index (default: 1)
- `num_ticks::Int`: Number of ticks to plot (default: 10000, 0 = all)
"""
function plot_tick_data(jld2_file::String; start_tick::Int = 1, num_ticks::Int = 10000)
    # Load data
    println("Loading data from: $jld2_file")
    data = load(jld2_file)

    total_ticks = data["total_ticks"]
    println("Total ticks in file: $total_ticks")

    # Extract all data
    tick_idx = data["tick_idx"]
    raw_price = data["raw_price"]
    price_delta = data["price_delta"]
    normalization = data["normalization"]  # AGC scale
    complex_real = data["complex_signal_real"]
    complex_imag = data["complex_signal_imag"]

    # Select range to plot
    start_idx = max(1, start_tick)
    if num_ticks == 0
        end_idx = length(tick_idx)
        println("Plotting ALL ticks ($(length(tick_idx)) points)")
    else
        end_idx = min(length(tick_idx), start_idx + num_ticks - 1)
        println("Plotting ticks $start_idx to $end_idx ($(end_idx - start_idx + 1) points)")
    end

    # Slice data
    tick_idx = tick_idx[start_idx:end_idx]
    raw_price = raw_price[start_idx:end_idx]
    price_delta = price_delta[start_idx:end_idx]
    normalization = normalization[start_idx:end_idx]
    complex_real = complex_real[start_idx:end_idx]
    complex_imag = complex_imag[start_idx:end_idx]

    # Scale raw price to [0, 1] based on min/max
    min_price = minimum(raw_price)
    max_price = maximum(raw_price)
    price_range = max_price - min_price

    if price_range > 0
        raw_price_scaled = (raw_price .- min_price) ./ price_range
    else
        raw_price_scaled = zeros(length(raw_price))
    end

    # Convert to Float32 for plotting
    price_delta_float = Float32.(price_delta)

    # Scale and offset complex signals for visibility (6x scale, then offset)
    complex_real_offset = (complex_real .* 6.0) .+ 1.0  # 6x scale, offset by +1.0
    complex_imag_offset = (complex_imag .* 6.0) .- 1.0  # 6x scale, offset by -1.0

    # AGC normalization stats
    min_norm = minimum(normalization)
    max_norm = maximum(normalization)

    println("Raw price range: $min_price - $max_price")
    println("Price delta range: $(minimum(price_delta)) - $(maximum(price_delta))")
    println("AGC normalization range: $min_norm - $max_norm")
    println("Complex real range: $(minimum(complex_real)) - $(maximum(complex_real))")
    println("Complex imag range: $(minimum(complex_imag)) - $(maximum(complex_imag))")

    # Create traces
    trace1 = scatter(
        x = tick_idx,
        y = raw_price_scaled,
        name = "Raw Price (scaled)",
        yaxis = "y1",
        line = attr(color = "blue", width = 1),
        mode = "lines"
    )

    trace2 = scatter(
        x = tick_idx,
        y = price_delta_float,
        name = "Price Delta",
        yaxis = "y2",
        line = attr(color = "red", width = 1),
        mode = "lines"
    )

    trace3 = scatter(
        x = tick_idx,
        y = complex_real_offset,
        name = "Complex Real (offset +1.0)",
        yaxis = "y2",
        line = attr(color = "green", width = 1),
        mode = "lines"
    )

    trace4 = scatter(
        x = tick_idx,
        y = complex_imag_offset,
        name = "Complex Imag (offset -1.0)",
        yaxis = "y2",
        line = attr(color = "orange", width = 1),
        mode = "lines"
    )

    trace5 = scatter(
        x = tick_idx,
        y = normalization,
        name = "AGC Scale",
        yaxis = "y2",
        line = attr(color = "purple", width = 2, dash = "dot"),
        mode = "lines"
    )

    # Create layout with dual y-axes
    layout = Layout(
        title = "TickDataPipeline Output: Raw Price, Price Delta, AGC & Complex Signals<br><sub>File: $(basename(jld2_file)) | Total ticks: $total_ticks</sub>",
        xaxis = attr(
            title = "Tick Index",
            showgrid = true,
            gridcolor = "lightgray",
            hoverformat = "d"  # Display as integer (no K suffix)
        ),
        yaxis = attr(
            title = "Raw Price (scaled: $min_price - $max_price)",
            titlefont = attr(color = "blue"),
            tickfont = attr(color = "blue"),
            side = "left",
            range = [0, 1],
            showgrid = true,
            gridcolor = "lightgray"
        ),
        yaxis2 = attr(
            title = "Price Delta / AGC Scale / Complex Signals (6x scaled)<br>AGC: $min_norm - $max_norm (purple) | I/Q: Real +1.0, Imag -1.0",
            titlefont = attr(color = "red"),
            tickfont = attr(color = "red"),
            overlaying = "y",
            side = "right",
            showgrid = false
        ),
        hovermode = "x unified",
        legend = attr(x = 0.01, y = 0.99),
        width = 1400,
        height = 700
    )

    # Create plot
    p = plot([trace1, trace5, trace2, trace3, trace4], layout)

    # Save to HTML with range info in filename
    base_name = replace(jld2_file, ".jld2" => "")
    if num_ticks == 0
        output_file = "$(base_name)_plot_all.html"
    else
        output_file = "$(base_name)_plot_$(start_idx)_to_$(end_idx).html"
    end
    savefig(p, output_file)

    println("\nPlot saved to: $output_file")
    println("Open in browser to view interactive plot")

    return p
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

    # Parse optional arguments
    start_tick = 1
    num_ticks = 10000

    if length(ARGS) >= 2
        start_tick = parse(Int, ARGS[2])
    end

    if length(ARGS) >= 3
        num_ticks = parse(Int, ARGS[3])
    end

    plot_tick_data(jld2_file, start_tick=start_tick, num_ticks=num_ticks)
end

# Run if called as script
if abspath(PROGRAM_FILE) == @__FILE__
    main()
else
    # Being included/loaded, export for interactive use
    println("plot_tick_data() function available")
    println("Usage: plot_tick_data(\"path/to/file.jld2\")")
end

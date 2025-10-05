when we pass in the jld2 file name followed by two integers, what are the two integers?

● The two integers are:

  1. start_tick - Starting tick index (which tick to begin plotting from)
  2. num_ticks - Number of ticks to plot (0 = plot all remaining ticks)

  Examples:

  # Start at tick 1, plot 50,000 ticks (ticks 1-50000)
  julia --project=. scripts/plot_jld2_data.jl data/jld2/processed_ticks_20251004_140629.jld2 1 50000

  # Start at tick 100,000, plot 10,000 ticks (ticks 100000-110000)
  julia --project=. scripts/plot_jld2_data.jl data/jld2/processed_ticks_20251004_140629.jld2 100000 10000

  # Start at tick 500,000, plot all remaining ticks to end
  julia --project=. scripts/plot_jld2_data.jl data/jld2/processed_ticks_20251004_140629.jld2 500000 0

  # Start at tick 1, plot ALL ticks in file
  julia --project=. scripts/plot_jld2_data.jl data/jld2/processed_ticks_20251004_140629.jld2 1 0

Now when you hover over the plot, the x-axis will show the actual tick index as an integer (e.g., "102711" instead of "102.711K").


  - Zero tick delay (line 12)
  - Process ALL ticks from the file (line 99)

 julia --project=. scripts/plot_jld2_data.jl data/jld2/processed_ticks_20251005_102215.jld2 1 0
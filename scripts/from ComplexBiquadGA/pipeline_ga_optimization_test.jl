#!/usr/bin/env julia
# scripts1001/pipeline_ga_optimization_test.jl
# Pipeline GA Optimization Test Script
#
# Purpose: Test pipeline-integrated GA optimization with real-time evolution
# Uses the pipeline's built-in GA system instead of duplicate test systems

using ComplexBiquadGA
using JLD2
using Printf
using Dates

"""
Quick filter parameter extraction
"""
function extract_quick_params(filter_bank)
    params = []
    # Suppress verbose output - just extract parameters
    if hasfield(typeof(filter_bank), :filters)
        # Regular FibonacciFilterBank
        filters = filter_bank.filters
        names = [filter.name for filter in filters]
        fib_numbers = [filter.fibonacci_number for filter in filters]

        for (i, filter) in enumerate(filters)
            # Vectorized params for GPU compatibility: [q_factor, center_freq, b0_mag, a1_mag, state_energy, fib_num, 0, 0, 0, 0, 0, 0, 0]
            # Padded to 13 elements to match chromosome length
            state_energy = abs(filter.x1) + abs(filter.x2) + abs(filter.y1) + abs(filter.y2)
            param = Float64[
                filter.q_factor,
                filter.center_frequency,
                abs(filter.b0),
                abs(filter.a1),
                state_energy,
                Float64(filter.fibonacci_number),
                0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0  # Padding for 13-element chromosome
            ]
            push!(params, param)
            # Suppress individual filter output
        end

    elseif hasfield(typeof(filter_bank), :tick_filters)
        # PLLFibonacciFilterBank
        for (i, tick_filter) in enumerate(filter_bank.tick_filters)
            name = filter_bank.filter_names[i]
            fib_num = filter_bank.fibonacci_numbers[i]

            # Vectorized PLL params for GPU compatibility: 13-element chromosome format
            # [pd_gain, loop_bw, lock_thresh, ring_decay, q_factor, vol_scale, clamp_thresh, extra1, extra2, extra3, extra4, extra5, fib_num]
            state_energy = abs(tick_filter.vco_phase) + abs(tick_filter.vco_frequency) + abs(tick_filter.loop_integrator)
            param = Float64[
                tick_filter.phase_detector_gain,
                tick_filter.loop_bandwidth,
                tick_filter.lock_threshold,
                tick_filter.ring_decay,
                0.5,  # Default q_factor placeholder
                0.1,  # Default volume_scaling placeholder
                1e-8, # Default clamping_threshold placeholder
                state_energy,  # Store state energy in position 8
                0.0, 0.0, 0.0, 0.0,  # Extra parameters for future use
                Float64(fib_num)  # Fib number at end for identification
            ]
            push!(params, param)
            @printf "   %s: PDGain=%.6f, LBW=%.6f, Lock=%.3f, Decay=%.6f, StateE=%.6f\n" name tick_filter.phase_detector_gain tick_filter.loop_bandwidth tick_filter.lock_threshold tick_filter.ring_decay state_energy
        end

    else
        println("⚠️  Unknown filter bank type: $(typeof(filter_bank))")
    end
    return params
end

"""
Display q_factor values for all 9 filters
"""
function display_filter_q_factors(filter_bank, description="Filter Q-factors")
    println("\n📊 $description:")
    println("="^60)

    if hasfield(typeof(filter_bank), :tick_filters)
        # PLLFibonacciFilterBank - Q-factor is in base_filter.q_factor
        for (i, tick_filter) in enumerate(filter_bank.tick_filters)
            name = filter_bank.filter_names[i]
            fib_num = filter_bank.fibonacci_numbers[i]

            # Get q_factor from base_filter (ComplexBiquad structure)
            if hasfield(typeof(tick_filter), :base_filter) && hasfield(typeof(tick_filter.base_filter), :q_factor)
                q_factor = tick_filter.base_filter.q_factor
                @printf "   F%d (%s, %d ticks): Q = %.6f\n" i name fib_num q_factor
            else
                @printf "   F%d (%s, %d ticks): Q = N/A\n" i name fib_num
            end
        end

    elseif hasfield(typeof(filter_bank), :filters)
        # Regular FibonacciFilterBank
        for (i, filter) in enumerate(filter_bank.filters)
            name = filter.name
            fib_num = filter.fibonacci_number
            q_factor = filter.q_factor

            @printf "   F%d (%s, %d ticks): Q = %.6f\n" i name fib_num q_factor
        end

    else
        println("   ⚠️  Unknown filter bank type: $(typeof(filter_bank))")
        # Try to inspect the structure
        println("   Available fields: $(fieldnames(typeof(filter_bank)))")
    end

    println("="^60)
end

"""
Quick parameter comparison
"""
function compare_quick_params(before, after)
    println("\n📊 Parameter Changes:")
    println("="^50)

    any_changes = false

    for i in 1:length(before)
        b = before[i]
        a = after[i]

        # Check key parameters that GA should optimize
        changes = []
        fib_num = Int(a[end])  # Fibonacci number stored at end of vector

        # Determine parameter type based on vector structure
        if length(b) >= 13 && length(a) >= 13
            # Check if this looks like PLL parameters (first 4 elements in expected PLL ranges)
            if b[1] < 1.0 && b[2] < 1.0 && b[3] < 2.0 && b[4] < 1.0
                # PLLFibonacciFilterBank parameters: [pd_gain, loop_bw, lock_thresh, ring_decay, ...]
                pd_diff = abs(a[1] - b[1])
                lbw_diff = abs(a[2] - b[2])
                lock_diff = abs(a[3] - b[3])
                decay_diff = abs(a[4] - b[4])
                state_diff = abs(a[8] - b[8])  # State energy at position 8

                if pd_diff > 1e-6; push!(changes, ("PDGain", b[1], a[1], pd_diff)); end
                if lbw_diff > 1e-6; push!(changes, ("LBW", b[2], a[2], lbw_diff)); end
                if lock_diff > 1e-6; push!(changes, ("Lock", b[3], a[3], lock_diff)); end
                if decay_diff > 1e-6; push!(changes, ("Decay", b[4], a[4], decay_diff)); end
                if state_diff > 1e-10; push!(changes, ("State", b[8], a[8], state_diff)); end

            else
                # Regular FibonacciFilterBank parameters: [q_factor, center_freq, b0_mag, a1_mag, state_energy, ...]
                q_diff = abs(a[1] - b[1])
                cf_diff = abs(a[2] - b[2])
                b0_diff = abs(a[3] - b[3])
                state_diff = abs(a[5] - b[5])  # State energy at position 5

                if q_diff > 1e-6; push!(changes, ("Q", b[1], a[1], q_diff)); end
                if cf_diff > 1e-6; push!(changes, ("CF", b[2], a[2], cf_diff)); end
                if b0_diff > 1e-6; push!(changes, ("b0", b[3], a[3], b0_diff)); end
                if state_diff > 1e-10; push!(changes, ("State", b[5], a[5], state_diff)); end
            end

            if !isempty(changes)
                println("🔧 Filter $i (Fib $fib_num):")
                for (param, before_val, after_val, diff) in changes
                    @printf "   %-5s: %.6f → %.6f (Δ=%+.6f)\n" param before_val after_val (after_val - before_val)
                end
                any_changes = true
            end
        end
    end

    if any_changes
        println("\n✅ OPTIMIZATION DETECTED - Parameters evolved!")
    else
        println("\n⚠️  NO OPTIMIZATION DETECTED - Parameters unchanged")
        println("   Possible reasons:")
        println("   - GA optimization disabled or not triggered")
        println("   - Optimization interval not reached")
        println("   - Processing time too short for meaningful evolution")
    end

    return any_changes
end



"""
Capture filter bank input and output data from BroadcastMessage
BroadcastMessage is the single source of truth for raw_price and input signal
Captures both raw and compensated outputs when group delay compensation is enabled
"""
function capture_filter_data!(filter_inputs, filter_outputs, filter_compensated_outputs,
                             tick_timestamps, raw_prices, tick_indices,
                             last_message_ref, actual_filter_bank, elapsed_time, tick_count)
    try
        # Get the last BroadcastMessage from the reference (single source of truth)
        last_message = last_message_ref[]

        if last_message !== nothing
            # Extract data from BroadcastMessage (single source of truth)
            input_signal = last_message.complex_signal
            raw_price = last_message.raw_price
            tick_index = last_message.tick_index
            timestamp_str = last_message.timestamp

            push!(filter_inputs, input_signal)
            push!(raw_prices, raw_price)
            push!(tick_indices, tick_index)
            push!(tick_timestamps, timestamp_str)

            # DEBUG: Show BroadcastMessage data for first 10 ticks
            if tick_count <= 10
                println("🔧 DEBUG BroadcastMessage Data - Tick $tick_count:")
                println("   tick_index = $(last_message.tick_index)")
                println("   timestamp = $timestamp_str")
                println("   raw_price = $raw_price")
                println("   complex_signal = $input_signal")
                println("   price_delta = $(last_message.price_delta)")
                println("   normalization_factor = $(last_message.normalization_factor)")
            end

            # Get filter outputs from ProductionFilterConsumer's filter bank
            # Note: ProductionFilterConsumer has already processed the BroadcastMessage
            # and updated its filter bank, so we just read the outputs
            current_outputs = ComplexBiquadGA.ProductionFilterBank.get_band_outputs(actual_filter_bank)
            push!(filter_outputs, current_outputs)

            # Get compensated outputs if group delay compensation is enabled
            # Check first filter to see if compensation is enabled
            compensation_enabled = false
            if hasfield(typeof(actual_filter_bank), :tick_filters) && length(actual_filter_bank.tick_filters) > 0
                first_filter = actual_filter_bank.tick_filters[1].base_filter
                if hasfield(typeof(first_filter), :apply_delay_compensation)
                    compensation_enabled = first_filter.apply_delay_compensation
                end
            end

            if compensation_enabled
                current_compensated = ComplexBiquadGA.ProductionFilterBank.get_compensated_band_outputs(actual_filter_bank)
                push!(filter_compensated_outputs, current_compensated)
            else
                push!(filter_compensated_outputs, ComplexF32[])  # Empty array when disabled
            end

            # DEBUG: Show filter outputs for first 10 ticks
            if tick_count <= 10
                println("   filter_outputs ($(length(current_outputs)) filters):")
                for (idx, output) in enumerate(current_outputs)
                    println("      Filter $idx: $output")
                end
                if compensation_enabled && !isempty(filter_compensated_outputs[end])
                    println("   compensated_outputs ($(length(filter_compensated_outputs[end])) filters):")
                    for (idx, output) in enumerate(filter_compensated_outputs[end])
                        println("      Filter $idx: $output")
                    end
                end
            end
        else
            # If no message yet, push empty vectors to maintain array consistency
            push!(filter_inputs, ComplexF32(0.0, 0.0))
            push!(filter_outputs, ComplexF32[])
            push!(filter_compensated_outputs, ComplexF32[])
            push!(raw_prices, Int32(0))
            push!(tick_indices, Int64(0))
            push!(tick_timestamps, "")
        end

    catch e
        @warn "Failed to capture filter data: $e"
        # Push default values to maintain array consistency
        push!(filter_inputs, ComplexF32(0.0, 0.0))
        push!(filter_outputs, ComplexF32[])
        push!(filter_compensated_outputs, ComplexF32[])
        push!(raw_prices, Int32(0))
        push!(tick_indices, Int64(0))
        push!(tick_timestamps, "")
    end
end

"""
Save pipeline filter bank input/output data to JLD2 file
Includes both raw outputs and group delay compensated outputs when enabled
"""
function save_pipeline_filter_data(filter_inputs, filter_outputs, filter_compensated_outputs,
                                  tick_timestamps, raw_prices, tick_indices,
                                  pipeline_filter_bank, pipeline_ga_stats, tick_count, timestamp)
    try
        # Check if group delay compensation was enabled
        compensation_enabled = false
        if hasfield(typeof(pipeline_filter_bank), :tick_filters) && length(pipeline_filter_bank.tick_filters) > 0
            first_filter = pipeline_filter_bank.tick_filters[1].base_filter
            if hasfield(typeof(first_filter), :apply_delay_compensation)
                compensation_enabled = first_filter.apply_delay_compensation
            end
        end

        # Prepare filter bank data structure
        filter_data = Dict(
            "inputs" => filter_inputs,
            "outputs" => filter_outputs,
            "compensated_outputs" => filter_compensated_outputs,
            "timestamps" => tick_timestamps,
            "raw_prices" => raw_prices,
            "tick_indices" => tick_indices,
            "tick_count" => tick_count,
            "capture_time" => timestamp,
            "filter_count" => length(pipeline_filter_bank.tick_filters),
            "fibonacci_numbers" => pipeline_filter_bank.fibonacci_numbers,
            "filter_names" => pipeline_filter_bank.filter_names,
            "pipeline_source" => true,
            "group_delay_compensation_enabled" => compensation_enabled
        )

        # Add GA information if available
        if pipeline_ga_stats !== nothing
            filter_data["ga_generations"] = pipeline_ga_stats.generations
            filter_data["ga_evaluations"] = pipeline_ga_stats.total_evaluations
            filter_data["ga_enabled"] = true
        else
            filter_data["ga_enabled"] = false
            filter_data["ga_generations"] = 0
            filter_data["ga_evaluations"] = 0
        end

        # Save to JLD2 file
        filter_data_file = "scripts1001/pipeline_filter_data_$timestamp.jld2"
        JLD2.save(filter_data_file, filter_data)

        # Minimal output
        println("Data saved: $filter_data_file")

        return filter_data_file

    catch e
        @warn "Failed to save pipeline filter data: $e"
        return nothing
    end
end


"""
Run pipeline GA optimization test with real-time evolution
"""
function run_pipeline_ga_test()
    # GA Control Flag - Set to false to disable GA evolution
    GA_ENABLED = false  # 🔧 Change to true to enable GA evolution

    println("🚀 Pipeline GA Test: 5 minutes, GA=$(GA_ENABLED ? "ON" : "OFF")")

    # Load development configuration
    filter_config = ComplexBiquadGA.ModernConfigSystem.load_filter_config("development")

    # Verify PLL is enabled for GA enhancement
    if !isa(filter_config, ComplexBiquadGA.ModernConfigSystem.ExtendedFilterConfig) || !filter_config.pll.enabled
        error("Pipeline GA test requires ExtendedFilterConfig with PLL enabled")
    end

    # Load individual filter defaults (minimal output)
    individual_defaults_config_name = "development_individual_defaults"
    individual_config = ComplexBiquadGA.ModernConfigSystem.load_individual_filter_defaults(individual_defaults_config_name)

    # DEBUG: Show what config was actually loaded
    println("🔍 DEBUG: Loaded individual_config:")
    println("   Config name: $individual_defaults_config_name")
    println("   Global defaults Q-factor: $(individual_config.global_defaults.q_factor)")
    println("   Number of overrides: $(length(individual_config.override_filter_ids))")
    for (i, filter_id) in enumerate(individual_config.override_filter_ids)
        override_q = individual_config.override_defaults[i].q_factor
        println("   Override [$i]: Filter $filter_id → Q = $override_q")
    end

    # Create pipeline configuration
    tick_file = "data/raw/YM 06-25.Last.txt"

    # Load flow control for 10 TPS
    flow_config = ComplexBiquadGA.load_flow_control_config("config/flow_control_active.toml")
    # Create pipeline manager (minimal output)

    pipeline_config = ComplexBiquadGA.EndToEndPipeline.PipelineConfiguration(
        tick_file, "development",
        output_directory = "test_output",
        individual_filter_config = individual_config,
        target_latency_us = Int32(250),
        max_latency_us = Int32(1500),
        target_throughput_tps = Float32(1000.0),
        memory_limit_mb = Float32(500.0),
        enable_production_consumer = true,
        enable_ab_test_consumer = false,
        enable_simulated_live_consumer = false
    )

    # DEBUG: Verify config was passed to pipeline
    println("🔍 DEBUG: Pipeline config individual_filter_config:")
    if pipeline_config.individual_filter_config !== nothing
        println("   ✅ individual_filter_config is set")
        println("   Global Q-factor: $(pipeline_config.individual_filter_config.global_defaults.q_factor)")
    else
        println("   ❌ individual_filter_config is nothing!")
    end
    pipeline_manager = ComplexBiquadGA.EndToEndPipeline.create_pipeline_manager(pipeline_config)

    # Initialize pipeline
    ComplexBiquadGA.EndToEndPipeline.start_pipeline!(pipeline_manager)

    # Get the ProductionFilterConsumer's filter bank (the one that processes BroadcastMessages)
    # This is separate from pipeline_manager.filter_bank
    production_filter_bank = nothing
    if pipeline_manager.production_consumer_data !== nothing
        production_filter_bank = pipeline_manager.production_consumer_data.consumer.filter_bank
        println("✅ Found ProductionFilterConsumer's filter bank for output capture")
    else
        error("ProductionFilterConsumer not found - cannot capture filter outputs")
    end

    # Display initial Q-factor values for all filters
    display_filter_q_factors(production_filter_bank, "INITIAL Filter Q-factors (ProductionFilterBank)")

    before_filter_params = extract_quick_params(production_filter_bank)

    # Create reference to store last BroadcastMessage
    # BroadcastMessage is returned by process_single_tick_through_pipeline! and is the
    # single source of truth for all tick data (raw_price, complex_signal, etc.)
    last_message_ref = Ref{Union{Nothing, ComplexBiquadGA.BroadcastMessageSystem.BroadcastMessage}}(nothing)

    println("✅ BroadcastMessage capture initialized (single source of truth for tick data)")

    # Process ticks for 5 minutes using proper stream processing path
    max_duration_seconds = 5 * 60  # 5 minutes

    # Initialize filter data collection
    filter_inputs = Vector{ComplexF32}()
    filter_outputs = Vector{Vector{ComplexF32}}()  # One vector per filter (raw VCO outputs)
    filter_compensated_outputs = Vector{Vector{ComplexF32}}()  # Compensated biquad outputs
    tick_timestamps = Vector{String}()  # ASCII timestamp strings from BroadcastMessage
    raw_prices = Vector{Int32}()
    tick_indices = Vector{Int64}()

    start_time = time()
    println("Running for $(max_duration_seconds) seconds (5 minutes)...")
    println("Using properly exported pipeline processing with TickHotLoopF32 integration")

    # Create time-limited tick stream
    tick_stream = ComplexBiquadGA.FlowControlConfig.stream_expanded_ticks(tick_file, flow_config)

    # Process using the optimized stream processing path with AGC fixes
    tick_count = 0
    for tick_line in tick_stream
        tick_count += 1

        # Check if 5 minutes have elapsed
        elapsed_time = time() - start_time
        if elapsed_time >= max_duration_seconds
            println("⏰ Reached 5-minute time limit")
            break
        end

        # Process through pipeline (now uses TickHotLoopF32 integration with AGC fixes)
        result = ComplexBiquadGA.EndToEndPipeline.process_single_tick_through_pipeline!(
            pipeline_manager, tick_line, Int32(tick_count)
        )

        # Extract BroadcastMessage from result (single source of truth)
        if haskey(result, :broadcast_message)
            last_message_ref[] = result.broadcast_message
        end

        # Capture filter input/output data using BroadcastMessage
        capture_filter_data!(filter_inputs, filter_outputs, filter_compensated_outputs,
                           tick_timestamps, raw_prices, tick_indices,
                           last_message_ref, production_filter_bank, time() - start_time, tick_count)

        if tick_count % 5000 == 0  # Progress every 5K ticks
            elapsed = time() - start_time
            actual_tps = tick_count / elapsed
            println("$(tick_count) ($(round(actual_tps, digits=0)) TPS)")
        end
    end

    total_time = time() - start_time
    actual_tps = tick_count / total_time

    println("Complete: $tick_count ticks, $(round(actual_tps, digits=0)) TPS")

    # Extract final parameters
    after_filter_params = extract_quick_params(production_filter_bank)

    # Display final Q-factor values for all filters
    display_filter_q_factors(production_filter_bank, "FINAL Filter Q-factors (ProductionFilterBank)")

    pipeline_ga = pipeline_manager.filter_bank_ga
    pipeline_ga_stats = if pipeline_ga !== nothing
        (generations = pipeline_ga.generation, total_evaluations = pipeline_ga.total_evaluations)
    else
        nothing
    end

    # Stop pipeline
    ComplexBiquadGA.EndToEndPipeline.stop_pipeline!(pipeline_manager)

    # Save filter bank input/output data
    timestamp = Dates.format(now(), "yyyy-mm-dd_HH-MM-SS")
    filter_data_file = save_pipeline_filter_data(filter_inputs, filter_outputs, filter_compensated_outputs,
                                                tick_timestamps, raw_prices, tick_indices,
                                                production_filter_bank, pipeline_ga_stats, tick_count, timestamp)

    # Check for pipeline GA parameter file
    ga_param_file = "data/ga_parameters/development_chromosomes.jld2"
    if isfile(ga_param_file)
        println("📁 Pipeline GA parameters: $ga_param_file")
    else
        println("⚠️  No pipeline GA parameter file found")
    end

    # Analysis using only filter parameter changes (no duplicate GA system)
    filter_changes = compare_quick_params(before_filter_params, after_filter_params)

    # Save simplified results focused on pipeline performance
    results = Dict(
        "test_time" => now(),
        "ticks_processed" => tick_count,
        "processing_time_s" => total_time,
        "actual_tps" => actual_tps,
        "before_filter_params" => before_filter_params,
        "after_filter_params" => after_filter_params,
        "ga_generations" => pipeline_ga_stats !== nothing ? pipeline_ga_stats.generations : 0,
        "ga_total_evaluations" => pipeline_ga_stats !== nothing ? pipeline_ga_stats.total_evaluations : 0,
        "filter_changes_detected" => filter_changes,
        "pipeline_source" => true,
        "individual_defaults_config" => individual_defaults_config_name,
        "ga_enabled" => GA_ENABLED,
        "filter_data_file" => filter_data_file,
        "filter_input_count" => length(filter_inputs),
        "filter_output_count" => length(filter_outputs)
    )

    output_file = "scripts1001/pipeline_ga_test_$timestamp.jld2"
    JLD2.save(output_file, results)

    # Final summary
    println("Results: $output_file")
    if filter_data_file !== nothing
        println("   Filter Data: $filter_data_file")
    end

    return filter_changes
end

# Execute
if abspath(PROGRAM_FILE) == @__FILE__
    run_pipeline_ga_test()
end
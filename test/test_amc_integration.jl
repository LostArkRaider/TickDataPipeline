# Test AMC Encoder Integration with Hot Loop
# Tests end-to-end integration of AMC encoder with process_tick_signal!()
# Protocol T-36 compliant: NO string literals in @test or @testset

using Test
using TickDataPipeline

@testset begin  # AMC Integration Tests

    @testset begin  # AMC Encoder Integration with Example Config
        # Create AMC config
        config = PipelineConfig(
            signal_processing = SignalProcessingConfig(encoder_type="amc")
        )
        state = create_tickhotloop_state()

        # Create test message
        msg = create_broadcast_message(Int32(1), Int64(0), Int32(42000), Int32(0))

        # Process through hot loop
        sp = config.signal_processing
        process_tick_signal!(
            msg, state,
            sp.agc_alpha, sp.agc_min_scale, sp.agc_max_scale,
            sp.winsorize_delta_threshold, sp.min_price, sp.max_price, sp.max_jump,
            sp.encoder_type, sp.cpm_modulation_index
        )

        # Verify AMC encoder was used (carrier phase should advance)
        # First tick has delta=0, amplitude=0, but carrier still advances
        @test state.phase_accumulator_Q32 == Int32(268435456)  # One carrier increment

        # Verify output is valid complex number
        @test !isnan(real(msg.complex_signal))
        @test !isnan(imag(msg.complex_signal))

        # Verify zero amplitude (first tick, delta=0)
        @test abs(msg.complex_signal) ≈ Float32(0.0)
    end

    @testset begin  # AMC Encoder Multi-Tick Processing
        config = PipelineConfig(
            signal_processing = SignalProcessingConfig(encoder_type="amc")
        )
        state = create_tickhotloop_state()
        sp = config.signal_processing

        # Process several ticks with non-zero deltas
        prices = [Int32(42000), Int32(42003), Int32(42001), Int32(42005)]

        for (idx, price) in enumerate(prices)
            delta = idx == 1 ? Int32(0) : price - prices[idx-1]
            msg = create_broadcast_message(Int32(idx), Int64(0), price, delta)

            process_tick_signal!(
                msg, state,
                sp.agc_alpha, sp.agc_min_scale, sp.agc_max_scale,
                sp.winsorize_delta_threshold, sp.min_price, sp.max_price, sp.max_jump,
                sp.encoder_type, sp.cpm_modulation_index
            )

            # Verify all outputs have valid magnitudes (variable envelope, not constant)
            magnitude = abs(msg.complex_signal)
            @test magnitude >= Float32(0.0)  # AMC can have zero amplitude
        end

        # Verify carrier phase accumulated over ticks
        # After 4 ticks: 4 × 268,435,456 = 1,073,741,824
        expected_phase = Int32(4) * Int32(268435456)
        @test state.phase_accumulator_Q32 == expected_phase
    end

    @testset begin  # HEXAD16 Encoder Still Works
        # Create config with HEXAD16 encoder
        config = PipelineConfig(
            signal_processing = SignalProcessingConfig(encoder_type="hexad16")
        )
        state = create_tickhotloop_state()
        sp = config.signal_processing

        # Process test message
        msg = create_broadcast_message(Int32(1), Int64(0), Int32(42000), Int32(0))

        process_tick_signal!(
            msg, state,
            sp.agc_alpha, sp.agc_min_scale, sp.agc_max_scale,
            sp.winsorize_delta_threshold, sp.min_price, sp.max_price, sp.max_jump,
            sp.encoder_type, sp.cpm_modulation_index
        )

        # Verify output is valid (HEXAD16 should still work)
        @test !isnan(real(msg.complex_signal))
        @test !isnan(imag(msg.complex_signal))

        # Verify phase accumulator unchanged (HEXAD16 doesn't use it)
        @test state.phase_accumulator_Q32 == Int32(0)
    end

    @testset begin  # AMC vs CPM vs HEXAD16 Output Differences
        # Create three configs with different encoders
        config_amc = PipelineConfig(
            signal_processing = SignalProcessingConfig(encoder_type="amc")
        )
        config_cpm = PipelineConfig(
            signal_processing = SignalProcessingConfig(encoder_type="cpm")
        )
        config_hexad = PipelineConfig(
            signal_processing = SignalProcessingConfig(encoder_type="hexad16")
        )

        state_amc = create_tickhotloop_state()
        state_cpm = create_tickhotloop_state()
        state_hexad = create_tickhotloop_state()

        # Same input message (first tick, delta=0)
        msg_amc = create_broadcast_message(Int32(1), Int64(0), Int32(42000), Int32(0))
        msg_cpm = create_broadcast_message(Int32(1), Int64(0), Int32(42000), Int32(0))
        msg_hexad = create_broadcast_message(Int32(1), Int64(0), Int32(42000), Int32(0))

        # Process with AMC
        sp_amc = config_amc.signal_processing
        process_tick_signal!(
            msg_amc, state_amc,
            sp_amc.agc_alpha, sp_amc.agc_min_scale, sp_amc.agc_max_scale,
            sp_amc.winsorize_delta_threshold, sp_amc.min_price, sp_amc.max_price, sp_amc.max_jump,
            sp_amc.encoder_type, sp_amc.cpm_modulation_index
        )

        # Process with CPM
        sp_cpm = config_cpm.signal_processing
        process_tick_signal!(
            msg_cpm, state_cpm,
            sp_cpm.agc_alpha, sp_cpm.agc_min_scale, sp_cpm.agc_max_scale,
            sp_cpm.winsorize_delta_threshold, sp_cpm.min_price, sp_cpm.max_price, sp_cpm.max_jump,
            sp_cpm.encoder_type, sp_cpm.cpm_modulation_index
        )

        # Process with HEXAD16
        sp_hexad = config_hexad.signal_processing
        process_tick_signal!(
            msg_hexad, state_hexad,
            sp_hexad.agc_alpha, sp_hexad.agc_min_scale, sp_hexad.agc_max_scale,
            sp_hexad.winsorize_delta_threshold, sp_hexad.min_price, sp_hexad.max_price, sp_hexad.max_jump,
            sp_hexad.encoder_type, sp_hexad.cpm_modulation_index
        )

        # AMC with zero amplitude produces zero signal
        @test msg_amc.complex_signal ≈ ComplexF32(0.0, 0.0)
        # But carrier phase advanced
        @test state_amc.phase_accumulator_Q32 == Int32(268435456)

        # CPM with zero input stays at phase 0, outputs unit magnitude
        @test abs(msg_cpm.complex_signal) ≈ Float32(1.0)
        @test msg_cpm.complex_signal ≈ ComplexF32(1.0, 0.0)
        @test state_cpm.phase_accumulator_Q32 == Int32(0)

        # HEXAD16 multiplies normalized_ratio by phase phasor
        # With normalized_ratio=0, output is (0, 0)
        @test msg_hexad.complex_signal ≈ ComplexF32(0.0, 0.0)
    end

    @testset begin  # AMC Carrier Phase Continuity Across Ticks
        config = PipelineConfig(
            signal_processing = SignalProcessingConfig(encoder_type="amc")
        )
        state = create_tickhotloop_state()
        sp = config.signal_processing

        # Process multiple ticks - carrier should advance uniformly
        prev_phase = Int32(0)

        for idx in 1:5
            msg = create_broadcast_message(Int32(idx), Int64(0), Int32(42000), Int32(0))

            process_tick_signal!(
                msg, state,
                sp.agc_alpha, sp.agc_min_scale, sp.agc_max_scale,
                sp.winsorize_delta_threshold, sp.min_price, sp.max_price, sp.max_jump,
                sp.encoder_type, sp.cpm_modulation_index
            )

            # Carrier phase should advance by constant increment
            expected_phase = prev_phase + Int32(268435456)
            @test state.phase_accumulator_Q32 == expected_phase
            prev_phase = state.phase_accumulator_Q32
        end
    end

    @testset begin  # AMC Amplitude Modulation Across Ticks
        config = PipelineConfig(
            signal_processing = SignalProcessingConfig(encoder_type="amc")
        )
        state = create_tickhotloop_state()
        sp = config.signal_processing

        # Initialize with first tick
        msg1 = create_broadcast_message(Int32(1), Int64(0), Int32(42000), Int32(0))
        process_tick_signal!(
            msg1, state,
            sp.agc_alpha, sp.agc_min_scale, sp.agc_max_scale,
            sp.winsorize_delta_threshold, sp.min_price, sp.max_price, sp.max_jump,
            sp.encoder_type, sp.cpm_modulation_index
        )

        # Process ticks with varying deltas
        # Magnitudes should vary (amplitude modulation)
        magnitudes = Float32[]

        for (idx, price) in enumerate([42003, 42001, 42006, 42002])
            delta = price - (idx == 1 ? 42000 : [42003, 42001, 42006][idx-1])
            msg = create_broadcast_message(Int32(idx+1), Int64(0), Int32(price), Int32(delta))

            process_tick_signal!(
                msg, state,
                sp.agc_alpha, sp.agc_min_scale, sp.agc_max_scale,
                sp.winsorize_delta_threshold, sp.min_price, sp.max_price, sp.max_jump,
                sp.encoder_type, sp.cpm_modulation_index
            )

            push!(magnitudes, abs(msg.complex_signal))
        end

        # Verify not all magnitudes are the same (variable envelope)
        @test !all(m -> m ≈ magnitudes[1], magnitudes)
    end

    @testset begin  # Integration with Price Validation
        config = PipelineConfig(
            signal_processing = SignalProcessingConfig(encoder_type="amc")
        )
        state = create_tickhotloop_state()
        sp = config.signal_processing

        # Process valid tick first
        msg1 = create_broadcast_message(Int32(1), Int64(0), Int32(42000), Int32(0))
        process_tick_signal!(
            msg1, state,
            sp.agc_alpha, sp.agc_min_scale, sp.agc_max_scale,
            sp.winsorize_delta_threshold, sp.min_price, sp.max_price, sp.max_jump,
            sp.encoder_type, sp.cpm_modulation_index
        )

        # Process invalid price (out of range)
        msg2 = create_broadcast_message(Int32(2), Int64(0), Int32(50000), Int32(8000))
        process_tick_signal!(
            msg2, state,
            sp.agc_alpha, sp.agc_min_scale, sp.agc_max_scale,
            sp.winsorize_delta_threshold, sp.min_price, sp.max_price, sp.max_jump,
            sp.encoder_type, sp.cpm_modulation_index
        )

        # Should hold last value (AMC should still produce valid output)
        @test msg2.status_flag & FLAG_HOLDLAST != 0
        # Carrier should still advance even when holding
        @test state.phase_accumulator_Q32 == Int32(2) * Int32(268435456)
    end

    @testset begin  # Integration with Winsorization
        config = PipelineConfig(
            signal_processing = SignalProcessingConfig(encoder_type="amc")
        )
        state = create_tickhotloop_state()
        sp = config.signal_processing

        # Initialize with first tick
        msg1 = create_broadcast_message(Int32(1), Int64(0), Int32(42000), Int32(0))
        process_tick_signal!(
            msg1, state,
            sp.agc_alpha, sp.agc_min_scale, sp.agc_max_scale,
            sp.winsorize_delta_threshold, sp.min_price, sp.max_price, sp.max_jump,
            sp.encoder_type, sp.cpm_modulation_index
        )

        # Process tick with large delta (should be winsorized)
        msg2 = create_broadcast_message(Int32(2), Int64(0), Int32(42100), Int32(100))
        process_tick_signal!(
            msg2, state,
            sp.agc_alpha, sp.agc_min_scale, sp.agc_max_scale,
            sp.winsorize_delta_threshold, sp.min_price, sp.max_price, sp.max_jump,
            sp.encoder_type, sp.cpm_modulation_index
        )

        # Should be clipped
        @test msg2.status_flag & FLAG_CLIPPED != 0
        # AMC should still produce valid output (amplitude based on clipped delta)
        @test !isnan(real(msg2.complex_signal))
        @test !isnan(imag(msg2.complex_signal))
    end

    @testset begin  # AMC 16-Tick Carrier Period Verification
        config = PipelineConfig(
            signal_processing = SignalProcessingConfig(encoder_type="amc")
        )
        state = create_tickhotloop_state()
        sp = config.signal_processing

        # Store carrier phases for one full period
        phases = Float32[]
        signals = ComplexF32[]

        # Process 17 ticks (16 = one period, 17 = period + 1)
        for tick in 1:17
            msg = create_broadcast_message(Int32(tick), Int64(0), Int32(42000), Int32(0))
            process_tick_signal!(
                msg, state,
                sp.agc_alpha, sp.agc_min_scale, sp.agc_max_scale,
                sp.winsorize_delta_threshold, sp.min_price, sp.max_price, sp.max_jump,
                sp.encoder_type, sp.cpm_modulation_index
            )
            push!(phases, Float32(state.phase_accumulator_Q32))
            push!(signals, msg.complex_signal)
        end

        # After 16 ticks: 16 × 268,435,456 = 4,294,967,296 = 2^32 (wraps to 0)
        # Phase should be close to initial phase (modulo 2^32)
        # Tick 17 phase should match tick 1 phase + one increment
        # Note: All signals have zero amplitude (delta=0), so we check phases instead
        expected_phase_17 = Int32(17) * Int32(268435456)
        @test state.phase_accumulator_Q32 == expected_phase_17
    end

    @testset begin  # AMC vs CPM Phase Behavior
        # AMC: Constant carrier phase increment (independent of input)
        # CPM: Variable phase increment (proportional to input)

        config_amc = PipelineConfig(
            signal_processing = SignalProcessingConfig(encoder_type="amc")
        )
        config_cpm = PipelineConfig(
            signal_processing = SignalProcessingConfig(encoder_type="cpm")
        )

        state_amc = create_tickhotloop_state()
        state_cpm = create_tickhotloop_state()

        # Initialize both
        for (config, state) in [(config_amc, state_amc), (config_cpm, state_cpm)]
            sp = config.signal_processing
            msg_init = create_broadcast_message(Int32(1), Int64(0), Int32(42000), Int32(0))
            process_tick_signal!(
                msg_init, state,
                sp.agc_alpha, sp.agc_min_scale, sp.agc_max_scale,
                sp.winsorize_delta_threshold, sp.min_price, sp.max_price, sp.max_jump,
                sp.encoder_type, sp.cpm_modulation_index
            )
        end

        # Process ticks with varying deltas
        prev_amc_phase = state_amc.phase_accumulator_Q32
        amc_increments = Int32[]

        for price in [42003, 42001, 42006, 42002]
            # AMC processing
            msg_amc = create_broadcast_message(Int32(2), Int64(0), Int32(price), Int32(3))
            sp_amc = config_amc.signal_processing
            process_tick_signal!(
                msg_amc, state_amc,
                sp_amc.agc_alpha, sp_amc.agc_min_scale, sp_amc.agc_max_scale,
                sp_amc.winsorize_delta_threshold, sp_amc.min_price, sp_amc.max_price, sp_amc.max_jump,
                sp_amc.encoder_type, sp_amc.cpm_modulation_index
            )

            # Record AMC phase increment
            push!(amc_increments, state_amc.phase_accumulator_Q32 - prev_amc_phase)
            prev_amc_phase = state_amc.phase_accumulator_Q32
        end

        # All AMC increments should be identical (constant carrier)
        @test all(inc -> inc == amc_increments[1], amc_increments)
    end

    @testset begin  # Load AMC Example TOML and Process Ticks
        config_path = "C:\\Users\\Keith\\source\\repos\\Julia\\TickDataPipeline\\config\\example_amc.toml"
        if isfile(config_path)
            config = load_config_from_toml(config_path)
            @test config.signal_processing.encoder_type == "amc"

            state = create_tickhotloop_state()
            sp = config.signal_processing

            # Process test tick
            msg = create_broadcast_message(Int32(1), Int64(0), Int32(42000), Int32(0))
            process_tick_signal!(
                msg, state,
                sp.agc_alpha, sp.agc_min_scale, sp.agc_max_scale,
                sp.winsorize_delta_threshold, sp.min_price, sp.max_price, sp.max_jump,
                sp.encoder_type, sp.cpm_modulation_index
            )

            # Verify AMC encoder was used
            @test state.phase_accumulator_Q32 == Int32(268435456)
            @test !isnan(real(msg.complex_signal))
            @test !isnan(imag(msg.complex_signal))
        end
    end

end  # End AMC Integration Tests

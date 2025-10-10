# Test CPM Encoder Integration with Hot Loop
# Tests end-to-end integration of CPM encoder with process_tick_signal!()
# Protocol T-36 compliant: NO string literals in @test or @testset

using Test
using TickDataPipeline

@testset begin  # CPM Integration Tests

    @testset begin  # CPM Encoder Integration with Default Config
        # Create default config (encoder_type = "cpm")
        config = create_default_config()
        state = create_tickhotloop_state()

        # Create test message
        msg = create_broadcast_message(Int32(1), Int64(0), Int32(42000), Int32(5))

        # Process through hot loop
        sp = config.signal_processing
        process_tick_signal!(
            msg, state,
            sp.agc_alpha, sp.agc_min_scale, sp.agc_max_scale,
            sp.winsorize_delta_threshold, sp.min_price, sp.max_price, sp.max_jump,
            sp.encoder_type, sp.cpm_modulation_index
        )

        # Verify CPM encoder was used (phase accumulator should be non-zero after processing)
        # On first tick, normalized_ratio=0, so phase stays 0
        @test state.phase_accumulator_Q32 == Int32(0)

        # Verify output is valid complex number
        @test !isnan(real(msg.complex_signal))
        @test !isnan(imag(msg.complex_signal))

        # Verify unit magnitude (CPM constant envelope)
        @test abs(msg.complex_signal) ≈ Float32(1.0)
    end

    @testset begin  # CPM Encoder Multi-Tick Processing
        config = create_default_config()
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

            # Verify all outputs have unit magnitude
            @test abs(msg.complex_signal) ≈ Float32(1.0)
        end

        # Verify phase accumulated over ticks (should be non-zero after deltas)
        @test state.phase_accumulator_Q32 != Int32(0)
    end

    @testset begin  # HEXAD16 Encoder Still Works
        # Create config with HEXAD16 encoder
        config = PipelineConfig(
            signal_processing = SignalProcessingConfig(encoder_type="hexad16")
        )
        state = create_tickhotloop_state()
        sp = config.signal_processing

        # Process test message
        msg = create_broadcast_message(Int32(1), Int64(0), Int32(42000), Int32(5))

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

    @testset begin  # CPM vs HEXAD16 Output Differences
        # Create two configs with different encoders
        config_cpm = create_default_config()  # defaults to CPM
        config_hexad = PipelineConfig(
            signal_processing = SignalProcessingConfig(encoder_type="hexad16")
        )

        state_cpm = create_tickhotloop_state()
        state_hexad = create_tickhotloop_state()

        # Same input message (first tick, delta=0)
        msg_cpm = create_broadcast_message(Int32(1), Int64(0), Int32(42000), Int32(0))
        msg_hexad = create_broadcast_message(Int32(1), Int64(0), Int32(42000), Int32(0))

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

        # CPM always produces unit magnitude (constant envelope)
        @test abs(msg_cpm.complex_signal) ≈ Float32(1.0)
        # CPM with zero input starts at phase 0, outputs (1, 0)
        @test msg_cpm.complex_signal ≈ ComplexF32(1.0, 0.0)

        # HEXAD16 multiplies normalized_ratio by phase phasor
        # With normalized_ratio=0, output is (0, 0)
        @test msg_hexad.complex_signal ≈ ComplexF32(0.0, 0.0)
    end

    @testset begin  # CPM Phase Continuity Across Ticks
        config = create_default_config()
        state = create_tickhotloop_state()
        sp = config.signal_processing

        # Process multiple ticks with consistent positive delta
        prev_phase = state.phase_accumulator_Q32

        for idx in 1:5
            msg = create_broadcast_message(Int32(idx), Int64(0), Int32(42000 + idx), Int32(1))

            process_tick_signal!(
                msg, state,
                sp.agc_alpha, sp.agc_min_scale, sp.agc_max_scale,
                sp.winsorize_delta_threshold, sp.min_price, sp.max_price, sp.max_jump,
                sp.encoder_type, sp.cpm_modulation_index
            )

            # Phase should increase (positive delta)
            if idx > 1  # Skip first tick (delta=0)
                # Use unsigned comparison to handle wraparound
                @test reinterpret(UInt32, state.phase_accumulator_Q32) > reinterpret(UInt32, prev_phase)
            end
            prev_phase = state.phase_accumulator_Q32
        end
    end

    @testset begin  # CPM Different Modulation Indices
        # Test h=0.25 vs h=0.5
        config_h025 = PipelineConfig(
            signal_processing = SignalProcessingConfig(
                encoder_type="cpm",
                cpm_modulation_index=Float32(0.25)
            )
        )
        config_h050 = create_default_config()  # h=0.5

        state_h025 = create_tickhotloop_state()
        state_h050 = create_tickhotloop_state()

        # Process same tick with both configs
        msg_h025 = create_broadcast_message(Int32(2), Int64(0), Int32(42005), Int32(5))
        msg_h050 = create_broadcast_message(Int32(2), Int64(0), Int32(42005), Int32(5))

        # Initialize states with first tick
        for (config, state) in [(config_h025, state_h025), (config_h050, state_h050)]
            sp = config.signal_processing
            msg_init = create_broadcast_message(Int32(1), Int64(0), Int32(42000), Int32(0))
            process_tick_signal!(
                msg_init, state,
                sp.agc_alpha, sp.agc_min_scale, sp.agc_max_scale,
                sp.winsorize_delta_threshold, sp.min_price, sp.max_price, sp.max_jump,
                sp.encoder_type, sp.cpm_modulation_index
            )
        end

        # Process second tick with delta=5
        sp_h025 = config_h025.signal_processing
        process_tick_signal!(
            msg_h025, state_h025,
            sp_h025.agc_alpha, sp_h025.agc_min_scale, sp_h025.agc_max_scale,
            sp_h025.winsorize_delta_threshold, sp_h025.min_price, sp_h025.max_price, sp_h025.max_jump,
            sp_h025.encoder_type, sp_h025.cpm_modulation_index
        )

        sp_h050 = config_h050.signal_processing
        process_tick_signal!(
            msg_h050, state_h050,
            sp_h050.agc_alpha, sp_h050.agc_min_scale, sp_h050.agc_max_scale,
            sp_h050.winsorize_delta_threshold, sp_h050.min_price, sp_h050.max_price, sp_h050.max_jump,
            sp_h050.encoder_type, sp_h050.cpm_modulation_index
        )

        # h=0.5 should produce roughly 2x the phase change of h=0.25
        # Both outputs should have unit magnitude
        @test abs(msg_h025.complex_signal) ≈ Float32(1.0)
        @test abs(msg_h050.complex_signal) ≈ Float32(1.0)

        # Phase accumulated should differ (h=0.5 accumulates faster)
        # h=0.5 phase should be roughly 2x h=0.25 phase
        @test abs(state_h050.phase_accumulator_Q32) > abs(state_h025.phase_accumulator_Q32)
    end

    @testset begin  # Integration with Price Validation
        config = create_default_config()
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

        # Should hold last value (CPM should still produce valid output)
        @test msg2.status_flag & FLAG_HOLDLAST != 0
        @test abs(msg2.complex_signal) ≈ Float32(1.0)
    end

    @testset begin  # Integration with Winsorization
        config = create_default_config()
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
        # CPM should still produce unit magnitude output
        @test abs(msg2.complex_signal) ≈ Float32(1.0)
    end

end  # End CPM Integration Tests

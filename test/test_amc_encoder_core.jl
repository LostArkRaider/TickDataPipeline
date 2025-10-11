# Test AMC Encoder Core Functionality
# Tests carrier phase accumulation, amplitude modulation, LUT usage, message interface
# Protocol T-36 compliant: NO string literals in @test or @testset

using Test
using TickDataPipeline

# Test constants matching implementation
const TEST_AMC_Q32_SCALE = Float32(2^32)
const TEST_AMC_INDEX_SHIFT = Int32(22)
const TEST_AMC_INDEX_MASK = UInt32(0x3FF)
const TEST_AMC_DEFAULT_CARRIER_INCREMENT = Int32(268435456)  # 16-tick period (π/8 rad/tick)

@testset begin  # AMC Encoder Core Tests

    @testset begin  # LUT Accuracy Tests (Shared CPM_LUT_1024)
        # Verify 1024 entries exist
        @test length(TickDataPipeline.CPM_LUT_1024) == 1024

        # Verify all entries are unit magnitude (within tolerance)
        for k in 1:1024
            magnitude = abs(TickDataPipeline.CPM_LUT_1024[k])
            @test magnitude ≈ Float32(1.0)
        end

        # Verify specific known angles (0°, 90°, 180°, 270°)
        # 0 degrees (index 1)
        @test real(TickDataPipeline.CPM_LUT_1024[1]) ≈ Float32(1.0)
        @test imag(TickDataPipeline.CPM_LUT_1024[1]) ≈ Float32(0.0)

        # 90 degrees (index 257 = 1024/4 + 1)
        @test isapprox(real(TickDataPipeline.CPM_LUT_1024[257]), Float32(0.0), atol=Float32(1e-6))
        @test imag(TickDataPipeline.CPM_LUT_1024[257]) ≈ Float32(1.0)

        # 180 degrees (index 513 = 1024/2 + 1)
        @test real(TickDataPipeline.CPM_LUT_1024[513]) ≈ Float32(-1.0)
        @test isapprox(imag(TickDataPipeline.CPM_LUT_1024[513]), Float32(0.0), atol=Float32(1e-6))

        # 270 degrees (index 769 = 3*1024/4 + 1)
        @test isapprox(real(TickDataPipeline.CPM_LUT_1024[769]), Float32(0.0), atol=Float32(1e-6))
        @test imag(TickDataPipeline.CPM_LUT_1024[769]) ≈ Float32(-1.0)
    end

    @testset begin  # Carrier Phase Accumulator Initialization
        state = create_tickhotloop_state()
        @test state.phase_accumulator_Q32 == Int32(0)
        @test state.amc_carrier_increment_Q32 == TEST_AMC_DEFAULT_CARRIER_INCREMENT
    end

    @testset begin  # Carrier Increment Calculation (16-tick period)
        # Carrier period = 16 ticks
        # Phase increment per tick = 2π/16 = π/8 radians
        # In Q32: π/8 = 2^32 / 16 = 268,435,456
        carrier_period = Float32(16.0)
        carrier_increment_Q32 = unsafe_trunc(Int32, TEST_AMC_Q32_SCALE / carrier_period)
        @test carrier_increment_Q32 == TEST_AMC_DEFAULT_CARRIER_INCREMENT
    end

    @testset begin  # Constant Carrier Phase Increment
        # Create state and message
        state = create_tickhotloop_state()
        msg = create_broadcast_message(Int32(1), Int64(0), Int32(42500), Int32(5))

        # Process multiple ticks with varying amplitudes
        # Carrier phase should advance by same increment regardless
        initial_phase = state.phase_accumulator_Q32

        # Tick 1: amplitude = 0.5
        process_tick_amc!(msg, state, Float32(0.5), Float32(1.0), FLAG_OK)
        phase_after_tick1 = state.phase_accumulator_Q32
        delta1 = phase_after_tick1 - initial_phase
        @test delta1 == TEST_AMC_DEFAULT_CARRIER_INCREMENT

        # Tick 2: amplitude = 0.8 (different amplitude)
        process_tick_amc!(msg, state, Float32(0.8), Float32(1.0), FLAG_OK)
        phase_after_tick2 = state.phase_accumulator_Q32
        delta2 = phase_after_tick2 - phase_after_tick1
        @test delta2 == TEST_AMC_DEFAULT_CARRIER_INCREMENT

        # Tick 3: amplitude = -0.3 (negative amplitude)
        process_tick_amc!(msg, state, Float32(-0.3), Float32(1.0), FLAG_OK)
        phase_after_tick3 = state.phase_accumulator_Q32
        delta3 = phase_after_tick3 - phase_after_tick2
        @test delta3 == TEST_AMC_DEFAULT_CARRIER_INCREMENT

        # All phase increments should be identical (constant carrier)
        @test delta1 == delta2
        @test delta2 == delta3
    end

    @testset begin  # Carrier Phase Wraparound Behavior
        # Simulate phase accumulation exceeding Int32 max (modulo 2π)
        phase = Int32(2147483647 - 1000)  # Near Int32 max (which represents π)
        delta = Int32(2000)                # Push over
        phase += delta

        # Should wrap to negative (Int32 overflow = modulo 2π behavior)
        @test phase < Int32(0)
        expected = Int32(-2147482649)
        @test phase == expected
    end

    @testset begin  # Index Extraction Bit Manipulation
        # Phase = 0 should give index 0
        phase = Int32(0)
        idx = Int32((reinterpret(UInt32, phase) >> TEST_AMC_INDEX_SHIFT) & TEST_AMC_INDEX_MASK)
        @test idx == Int32(0)

        # Phase = Int32 min (represents π radians in Q32) should give index 512
        phase = typemin(Int32)
        idx = Int32((reinterpret(UInt32, phase) >> TEST_AMC_INDEX_SHIFT) & TEST_AMC_INDEX_MASK)
        @test idx == Int32(512)

        # Phase = -1 (near 2π) should give index 1023
        phase = Int32(-1)
        idx = Int32((reinterpret(UInt32, phase) >> TEST_AMC_INDEX_SHIFT) & TEST_AMC_INDEX_MASK)
        @test idx == Int32(1023)
    end

    @testset begin  # Amplitude Modulation Verification
        # AMC output magnitude should vary with normalized_ratio (NOT constant envelope)
        state = create_tickhotloop_state()
        msg = create_broadcast_message(Int32(1), Int64(0), Int32(42500), Int32(5))

        # Test amplitude = 0.5
        process_tick_amc!(msg, state, Float32(0.5), Float32(1.0), FLAG_OK)
        magnitude1 = abs(msg.complex_signal)
        @test magnitude1 ≈ Float32(0.5)

        # Test amplitude = 0.8
        process_tick_amc!(msg, state, Float32(0.8), Float32(1.0), FLAG_OK)
        magnitude2 = abs(msg.complex_signal)
        @test magnitude2 ≈ Float32(0.8)

        # Test amplitude = 1.0
        process_tick_amc!(msg, state, Float32(1.0), Float32(1.0), FLAG_OK)
        magnitude3 = abs(msg.complex_signal)
        @test magnitude3 ≈ Float32(1.0)

        # Test amplitude = 0.0 (zero signal)
        process_tick_amc!(msg, state, Float32(0.0), Float32(1.0), FLAG_OK)
        magnitude4 = abs(msg.complex_signal)
        @test magnitude4 ≈ Float32(0.0)

        # Verify magnitudes are different (not constant envelope like CPM)
        @test magnitude1 != magnitude2
        @test magnitude2 != magnitude3
    end

    @testset begin  # Message Interface Compatibility
        # Create test message and state
        msg = create_broadcast_message(
            Int32(1),      # tick_idx
            Int64(0),      # timestamp
            Int32(42500),  # raw_price
            Int32(5)       # price_delta
        )
        state = create_tickhotloop_state()

        # Process with normalized_ratio = 0.8
        process_tick_amc!(
            msg,
            state,
            Float32(0.8),  # normalized_ratio
            Float32(1.0),  # normalization_factor
            FLAG_OK
        )

        # Verify output magnitude = 0.8 (amplitude modulation)
        @test abs(msg.complex_signal) ≈ Float32(0.8)
        @test msg.normalization == Float32(1.0)
        @test msg.status_flag == FLAG_OK
        @test state.phase_accumulator_Q32 == TEST_AMC_DEFAULT_CARRIER_INCREMENT
    end

    @testset begin  # Carrier Phase Continuity Across Ticks
        # Create state and message
        state = create_tickhotloop_state()
        msg = create_broadcast_message(Int32(1), Int64(0), Int32(42500), Int32(5))

        # Process 16 ticks (one full carrier period)
        for tick in 1:16
            process_tick_amc!(msg, state, Float32(0.5), Float32(1.0), FLAG_OK)
        end

        # After 16 ticks at π/8 per tick, phase should be ≈ 2π (wraps to 0)
        # Expected: 16 × 268,435,456 = 4,294,967,296 = 2^32 (wraps to 0 in Int32)
        # Due to Int32 wraparound: should be close to 0
        @test abs(state.phase_accumulator_Q32) < Int32(1000)
    end

    @testset begin  # AMC Output Variable Magnitude Verification
        # AMC outputs should have magnitude proportional to normalized_ratio
        state = create_tickhotloop_state()
        msg = create_broadcast_message(Int32(1), Int64(0), Int32(42500), Int32(5))

        # Test various normalized ratios
        test_ratios = [Float32(0.0), Float32(0.25), Float32(0.5),
                       Float32(0.75), Float32(1.0), Float32(-0.5)]

        for ratio in test_ratios
            process_tick_amc!(msg, state, ratio, Float32(1.0), FLAG_OK)
            magnitude = abs(msg.complex_signal)
            expected_magnitude = abs(ratio)
            @test magnitude ≈ expected_magnitude || error("AMC magnitude mismatch for ratio=$ratio")
        end
    end

    @testset begin  # Complex Signal Phase Properties
        # Verify AMC carrier phase advances uniformly
        state = create_tickhotloop_state()
        msg = create_broadcast_message(Int32(1), Int64(0), Int32(42500), Int32(5))

        # Store phases from multiple ticks
        phases = Float32[]
        for tick in 1:4
            process_tick_amc!(msg, state, Float32(1.0), Float32(1.0), FLAG_OK)
            phase_radians = angle(msg.complex_signal)
            push!(phases, phase_radians)
        end

        # Verify phase increments are approximately constant (π/8 radians)
        expected_increment = Float32(π/8)
        for i in 2:4
            delta_phase = phases[i] - phases[i-1]
            # Handle 2π wraparound
            if delta_phase < Float32(-π)
                delta_phase += Float32(2π)
            elseif delta_phase > Float32(π)
                delta_phase -= Float32(2π)
            end
            @test delta_phase ≈ expected_increment || error("Phase increment mismatch at tick $i")
        end
    end

    @testset begin  # Negative Amplitude Handling
        # AMC should preserve sign in amplitude (180° phase shift)
        state = create_tickhotloop_state()
        msg = create_broadcast_message(Int32(1), Int64(0), Int32(42500), Int32(5))

        # Tick 1: positive amplitude
        process_tick_amc!(msg, state, Float32(0.5), Float32(1.0), FLAG_OK)
        signal_positive = msg.complex_signal

        # Reset state for comparison
        state = create_tickhotloop_state()

        # Tick 1: negative amplitude (same magnitude)
        process_tick_amc!(msg, state, Float32(-0.5), Float32(1.0), FLAG_OK)
        signal_negative = msg.complex_signal

        # Magnitudes should be equal
        @test abs(signal_positive) ≈ abs(signal_negative)

        # Signals should be 180° apart (opposite phase)
        # signal_negative ≈ -signal_positive
        @test real(signal_negative) ≈ -real(signal_positive)
        @test imag(signal_negative) ≈ -imag(signal_positive)
    end

    @testset begin  # Zero Amplitude Edge Case
        # AMC with zero amplitude should produce zero signal
        state = create_tickhotloop_state()
        msg = create_broadcast_message(Int32(1), Int64(0), Int32(42500), Int32(5))

        # Process with zero amplitude
        process_tick_amc!(msg, state, Float32(0.0), Float32(1.0), FLAG_OK)

        # Output should be zero
        @test abs(msg.complex_signal) ≈ Float32(0.0)
        @test real(msg.complex_signal) ≈ Float32(0.0)
        @test imag(msg.complex_signal) ≈ Float32(0.0)

        # Carrier phase should still advance
        @test state.phase_accumulator_Q32 == TEST_AMC_DEFAULT_CARRIER_INCREMENT
    end

    @testset begin  # Carrier Period 16-tick Verification
        # Verify that 16 ticks = one full carrier period (2π)
        state = create_tickhotloop_state()
        msg = create_broadcast_message(Int32(1), Int64(0), Int32(42500), Int32(5))

        # Store signals for one full period
        signals = ComplexF32[]
        for tick in 1:17  # 17 ticks = 1 full period + 1
            process_tick_amc!(msg, state, Float32(1.0), Float32(1.0), FLAG_OK)
            push!(signals, msg.complex_signal)
        end

        # Signal at tick 17 should match signal at tick 1 (phase repeats)
        @test signals[17] ≈ signals[1] || error("Carrier phase did not repeat after 16 ticks")
    end

end  # End AMC Encoder Core Tests

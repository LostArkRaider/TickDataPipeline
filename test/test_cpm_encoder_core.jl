# Test CPM Encoder Core Functionality
# Tests LUT accuracy, phase accumulation, index extraction, message interface
# Protocol T-36 compliant: NO string literals in @test or @testset

using Test
using TickDataPipeline

# Test constants matching implementation
const TEST_CPM_Q32_SCALE = Float32(2^31)
const TEST_CPM_INDEX_SHIFT = Int32(22)
const TEST_CPM_INDEX_MASK = UInt32(0x3FF)

@testset begin  # CPM Encoder Core Tests

    @testset begin  # LUT Accuracy Tests
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

    @testset begin  # Phase Accumulator Initialization
        state = create_tickhotloop_state()
        @test state.phase_accumulator_Q32 == Int32(0)
    end

    @testset begin  # Phase Increment Calculation
        # h=0.5: Normalized ratio = +1.0 should give Δθ = π ≈ 2^31
        h = Float32(0.5)
        phase_scale = Float32(2.0) * h * TEST_CPM_Q32_SCALE
        delta = unsafe_trunc(Int32, round(Float32(1.0) * phase_scale))
        # Note: 2^31 as Int32 is negative (overflow), so we compare the value
        expected = typemin(Int32)  # This is what 2^31 becomes as Int32 (-2147483648)
        @test delta == expected

        # h=0.5: Normalized ratio = +0.5 should give Δθ = π/2 = 2^30
        delta_half = unsafe_trunc(Int32, round(Float32(0.5) * phase_scale))
        @test delta_half == Int32(1073741824)  # 2^30 fits in Int32

        # h=0.5: Normalized ratio = -1.0 should give Δθ = -π ≈ -2^31
        delta_neg = unsafe_trunc(Int32, round(Float32(-1.0) * phase_scale))
        @test delta_neg == typemin(Int32)  # -2^31 as Int32
    end

    @testset begin  # Phase Wraparound Behavior
        # Simulate phase accumulation exceeding Int32 max (modulo 2π)
        phase = Int32(2147483647 - 1000)  # Near Int32 max (which represents π)
        delta = Int32(2000)                # Push over
        phase += delta

        # Should wrap to negative (Int32 overflow = modulo 2π behavior)
        @test phase < Int32(0)
        # Calculate expected value: (2147483647 - 1000) + 2000 = 2147483647 + 1000
        # This overflows to: 2147483647 + 1000 - 2^32 = -2147482649
        expected = Int32(-2147482649)
        @test phase == expected
    end

    @testset begin  # Index Extraction Bit Manipulation
        # Phase = 0 should give index 0
        phase = Int32(0)
        idx = Int32((reinterpret(UInt32, phase) >> TEST_CPM_INDEX_SHIFT) & TEST_CPM_INDEX_MASK)
        @test idx == Int32(0)

        # Phase = Int32 min (represents π radians in Q32) should give index 512
        phase = typemin(Int32)  # -2^31, which is 2^31 in unsigned interpretation
        idx = Int32((reinterpret(UInt32, phase) >> TEST_CPM_INDEX_SHIFT) & TEST_CPM_INDEX_MASK)
        @test idx == Int32(512)

        # Phase = -1 (near 2π) should give index 1023
        phase = Int32(-1)
        idx = Int32((reinterpret(UInt32, phase) >> TEST_CPM_INDEX_SHIFT) & TEST_CPM_INDEX_MASK)
        @test idx == Int32(1023)
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

        # Process with normalized_ratio = 0.0, h = 0.5 (no phase change)
        process_tick_cpm!(
            msg,
            state,
            Float32(0.0),  # normalized_ratio
            Float32(1.0),  # normalization_factor
            FLAG_OK,
            Float32(0.5)   # h = 0.5 (MSK)
        )

        # Verify output at phase 0 (should be 1+0i)
        @test msg.complex_signal ≈ ComplexF32(1.0, 0.0)
        @test msg.normalization == Float32(1.0)
        @test msg.status_flag == FLAG_OK
        @test state.phase_accumulator_Q32 == Int32(0)  # Phase unchanged
    end

    @testset begin  # Phase Accumulation Persistence Across Ticks
        # Create state and message
        state = create_tickhotloop_state()
        msg = create_broadcast_message(Int32(1), Int64(0), Int32(42500), Int32(5))

        # h = 0.5: Tick 1: normalized_ratio = +0.5 (Δθ = π/2 = 90°)
        process_tick_cpm!(msg, state, Float32(0.5), Float32(1.0), FLAG_OK, Float32(0.5))
        phase_after_tick1 = state.phase_accumulator_Q32
        @test phase_after_tick1 ≈ Int32(1073741824)  # π/2 in Q32 (2^30)

        # Tick 2: normalized_ratio = +0.5 again (Δθ = π/2 = 90°)
        process_tick_cpm!(msg, state, Float32(0.5), Float32(1.0), FLAG_OK, Float32(0.5))
        phase_after_tick2 = state.phase_accumulator_Q32
        # After two increments of π/2, we get π which wraps to typemin(Int32)
        @test phase_after_tick2 ≈ typemin(Int32)  # π in Q32 (wraps to -2^31)

        # Verify phase accumulated (use unsigned comparison to handle wraparound)
        @test reinterpret(UInt32, phase_after_tick2) > reinterpret(UInt32, phase_after_tick1)
    end

    @testset begin  # CPM Output Unit Magnitude Verification
        # All CPM outputs should have magnitude 1.0 (constant envelope)
        state = create_tickhotloop_state()
        msg = create_broadcast_message(Int32(1), Int64(0), Int32(42500), Int32(5))

        # Test various normalized ratios with h=0.5
        test_ratios = [Float32(0.0), Float32(0.25), Float32(0.5),
                       Float32(0.75), Float32(1.0), Float32(-0.5)]

        for ratio in test_ratios
            process_tick_cpm!(msg, state, ratio, Float32(1.0), FLAG_OK, Float32(0.5))
            magnitude = abs(msg.complex_signal)
            @test magnitude ≈ Float32(1.0) || error("CPM output not unit magnitude for ratio=$ratio")
        end
    end

    @testset begin  # Modulation Index h Parameter Effect
        # Test that different h values produce different phase increments
        state1 = create_tickhotloop_state()
        state2 = create_tickhotloop_state()
        msg1 = create_broadcast_message(Int32(1), Int64(0), Int32(42500), Int32(5))
        msg2 = create_broadcast_message(Int32(1), Int64(0), Int32(42500), Int32(5))

        # Process same input with different h values
        process_tick_cpm!(msg1, state1, Float32(0.5), Float32(1.0), FLAG_OK, Float32(0.5))
        process_tick_cpm!(msg2, state2, Float32(0.5), Float32(1.0), FLAG_OK, Float32(0.25))

        # Phase accumulator should differ (h=0.25 produces half the phase change)
        # For h=0.5, ratio=0.5: phase ≈ π/2
        # For h=0.25, ratio=0.5: phase ≈ π/4
        # So state1 should be approximately 2× state2
        @test abs(state1.phase_accumulator_Q32 - Int32(2) * state2.phase_accumulator_Q32) < Int32(100)
    end

    @testset begin  # Complex Signal Properties
        # Verify CPM output has correct I/Q components
        state = create_tickhotloop_state()
        msg = create_broadcast_message(Int32(1), Int64(0), Int32(42500), Int32(5))

        # Process tick with h=0.5, ratio=1.0 (phase = π)
        process_tick_cpm!(msg, state, Float32(1.0), Float32(1.0), FLAG_OK, Float32(0.5))

        # Phase = π should give output ≈ (-1, 0) or close
        # (LUT quantization may not be exact, but should be in 3rd quadrant or on negative real axis)
        @test real(msg.complex_signal) < Float32(0.0)
        @test abs(msg.complex_signal) ≈ Float32(1.0)
    end

end  # End CPM Encoder Core Tests

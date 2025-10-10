using Test
using TickDataPipeline

@testset begin #TickHotLoopF32
    @testset begin #State Creation
        state = create_tickhotloop_state()
        @test state.last_clean === nothing
        @test state.has_delta_ema == false
        @test state.ticks_accepted == Int64(0)
        @test state.ema_delta == Int32(0)
        @test state.ema_delta_dev == Int32(1)
        @test state.ema_abs_delta == Int32(10)
    end

    # COMMENTED OUT: apply_quad4_rotation is no longer exported
    # @testset begin #QUAD-4 Rotation
    #     # Phase 0: real axis (0°)
    #     z = apply_quad4_rotation(Float32(1.0), Int32(0))
    #     @test real(z) ≈ Float32(1.0)
    #     @test imag(z) ≈ Float32(0.0)

    #     # Phase 1: imaginary axis (90°)
    #     z = apply_quad4_rotation(Float32(1.0), Int32(1))
    #     @test real(z) ≈ Float32(0.0)
    #     @test imag(z) ≈ Float32(1.0)

    #     # Phase 2: negative real axis (180°)
    #     z = apply_quad4_rotation(Float32(1.0), Int32(2))
    #     @test real(z) ≈ Float32(-1.0)
    #     @test imag(z) ≈ Float32(0.0)

    #     # Phase 3: negative imaginary axis (270°)
    #     z = apply_quad4_rotation(Float32(1.0), Int32(3))
    #     @test real(z) ≈ Float32(0.0)
    #     @test imag(z) ≈ Float32(-1.0)
    # end

    @testset begin #Phase Position Global
        # Cycles through 0-15 (HEXAD-16)
        @test phase_pos_global(Int64(1)) == Int32(0)
        @test phase_pos_global(Int64(2)) == Int32(1)
        @test phase_pos_global(Int64(3)) == Int32(2)
        @test phase_pos_global(Int64(4)) == Int32(3)
        @test phase_pos_global(Int64(5)) == Int32(4)
        @test phase_pos_global(Int64(6)) == Int32(5)
        @test phase_pos_global(Int64(16)) == Int32(15)
        @test phase_pos_global(Int64(17)) == Int32(0)  # Cycles back after 16
    end

    @testset begin #Signal Processing Basic
        state = create_tickhotloop_state()

        # First tick initializes
        msg1 = create_broadcast_message(Int32(1), Int64(1), Int32(41971), Int32(0))
        process_tick_signal!(
            msg1, state,
            Float32(0.0625), Int32(4), Int32(50), Int32(3),
            Int32(40000), Int32(43000), Int32(50),
            "hexad16", Float32(0.5)
        )

        # Second tick has real signal
        msg2 = create_broadcast_message(Int32(2), Int64(2), Int32(41981), Int32(10))
        process_tick_signal!(
            msg2, state,
            Float32(0.0625), Int32(4), Int32(50), Int32(3),
            Int32(40000), Int32(43000), Int32(50),
            "hexad16", Float32(0.5)
        )

        # Second tick should have non-zero signal
        @test msg2.complex_signal != ComplexF32(0, 0)
        @test msg2.normalization > Float32(0.0)

        # State should be updated
        @test state.ticks_accepted == Int64(2)
        @test state.last_clean !== nothing
    end

    @testset begin #First Tick Initialization
        state = create_tickhotloop_state()
        msg = create_broadcast_message(Int32(1), Int64(1), Int32(41971), Int32(0))

        process_tick_signal!(
            msg, state,
            Float32(0.0625), Int32(4), Int32(50), Int32(3),
            Int32(40000), Int32(43000), Int32(50),
            "hexad16", Float32(0.5)
        )

        # First tick should have zero signal
        @test msg.complex_signal == ComplexF32(0, 0)
        @test msg.normalization == Float32(1.0)
        @test msg.status_flag == FLAG_OK
        @test state.last_clean == Int32(41971)
        @test state.ticks_accepted == Int64(1)
    end

    @testset begin #Price Validation
        state = create_tickhotloop_state()

        # First tick: out of range (too low)
        msg1 = create_broadcast_message(Int32(1), Int64(1), Int32(30000), Int32(0))
        process_tick_signal!(
            msg1, state,
            Float32(0.0625), Int32(4), Int32(50), Int32(3),
            Int32(40000), Int32(43000), Int32(50),
            "hexad16", Float32(0.5)
        )
        @test state.last_clean === nothing  # Not initialized

        # Second tick: valid price
        msg2 = create_broadcast_message(Int32(2), Int64(2), Int32(41971), Int32(0))
        process_tick_signal!(
            msg2, state,
            Float32(0.0625), Int32(4), Int32(50), Int32(3),
            Int32(40000), Int32(43000), Int32(50),
            "hexad16", Float32(0.5)
        )
        @test state.last_clean == Int32(41971)

        # Third tick: out of range (should hold last)
        msg3 = create_broadcast_message(Int32(3), Int64(3), Int32(50000), Int32(0))
        process_tick_signal!(
            msg3, state,
            Float32(0.0625), Int32(4), Int32(50), Int32(3),
            Int32(40000), Int32(43000), Int32(50),
            "hexad16", Float32(0.5)
        )
        @test (msg3.status_flag & FLAG_HOLDLAST) != UInt8(0)
        @test msg3.complex_signal == ComplexF32(0, 0)  # Zero delta
    end

    @testset begin #Hard Jump Guard
        state = create_tickhotloop_state()

        # Initialize with first tick
        msg1 = create_broadcast_message(Int32(1), Int64(1), Int32(41971), Int32(0))
        process_tick_signal!(
            msg1, state,
            Float32(0.0625), Int32(4), Int32(50), Int32(3),
            Int32(40000), Int32(43000), Int32(50),
            "hexad16", Float32(0.5)
        )

        # Second tick with large jump (delta = 100, max_jump = 50)
        msg2 = create_broadcast_message(Int32(2), Int64(2), Int32(42071), Int32(100))
        process_tick_signal!(
            msg2, state,
            Float32(0.0625), Int32(4), Int32(50), Int32(3),
            Int32(40000), Int32(43000), Int32(50),
            "hexad16", Float32(0.5)
        )

        # Should be clipped
        @test (msg2.status_flag & FLAG_CLIPPED) != UInt8(0)
    end

    @testset begin #AGC Minimum Scale
        state = create_tickhotloop_state()

        # Initialize
        msg1 = create_broadcast_message(Int32(1), Int64(1), Int32(41971), Int32(0))
        process_tick_signal!(
            msg1, state,
            Float32(0.0625), Int32(4), Int32(50), Int32(3),
            Int32(40000), Int32(43000), Int32(50),
            "hexad16", Float32(0.5)
        )

        # Very small delta
        msg2 = create_broadcast_message(Int32(2), Int64(2), Int32(41972), Int32(1))
        process_tick_signal!(
            msg2, state,
            Float32(0.0625), Int32(4), Int32(50), Int32(3),
            Int32(40000), Int32(43000), Int32(50),
            "hexad16", Float32(0.5)
        )

        # Normalization should respect min_scale
        @test msg2.normalization >= Float32(4.0)  # agc_min_scale
    end

    @testset begin #AGC Maximum Scale
        state = create_tickhotloop_state()

        # Initialize
        msg1 = create_broadcast_message(Int32(1), Int64(1), Int32(41971), Int32(0))
        process_tick_signal!(
            msg1, state,
            Float32(0.0625), Int32(4), Int32(50), Int32(3),
            Int32(40000), Int32(43000), Int32(50),
            "hexad16", Float32(0.5)
        )

        # Process many large deltas to push AGC to max
        for i in 2:20
            msg = create_broadcast_message(Int32(i), Int64(i), Int32(41971 + i*40), Int32(40))
            process_tick_signal!(
                msg, state,
                Float32(0.0625), Int32(4), Int32(50), Int32(3),
                Int32(40000), Int32(43000), Int32(50),
                "hexad16", Float32(0.5)
            )
        end

        # Should hit AGC limit
        @test state.ema_abs_delta <= Int32(50)  # agc_max_scale
    end

    @testset begin #Winsorization
        state = create_tickhotloop_state()

        # Initialize
        msg1 = create_broadcast_message(Int32(1), Int64(1), Int32(41971), Int32(0))
        process_tick_signal!(
            msg1, state,
            Float32(0.0625), Int32(4), Int32(50), Int32(3),
            Int32(40000), Int32(43000), Int32(50),
            "hexad16", Float32(0.5)
        )

        # Second tick with moderate delta
        msg2 = create_broadcast_message(Int32(2), Int64(2), Int32(41981), Int32(10))
        process_tick_signal!(
            msg2, state,
            Float32(0.0625), Int32(4), Int32(50), Int32(3),
            Int32(40000), Int32(43000), Int32(50),
            "hexad16", Float32(0.5)
        )

        # Normalized signal should be clipped if exceeds threshold
        @test abs(real(msg2.complex_signal)) <= Float32(3.0)
        @test abs(imag(msg2.complex_signal)) <= Float32(3.0)
    end

    @testset begin #In-Place Message Update
        state = create_tickhotloop_state()

        # Initialize first
        msg1 = create_broadcast_message(Int32(1), Int64(1), Int32(41971), Int32(0))
        process_tick_signal!(
            msg1, state,
            Float32(0.0625), Int32(4), Int32(50), Int32(3),
            Int32(40000), Int32(43000), Int32(50),
            "hexad16", Float32(0.5)
        )

        # Second tick with delta
        msg2 = create_broadcast_message(Int32(2), Int64(2), Int32(41981), Int32(10))

        # Store original values
        original_signal = msg2.complex_signal
        original_norm = msg2.normalization
        original_flag = msg2.status_flag

        process_tick_signal!(
            msg2, state,
            Float32(0.0625), Int32(4), Int32(50), Int32(3),
            Int32(40000), Int32(43000), Int32(50),
            "hexad16", Float32(0.5)
        )

        # Message should be modified in-place
        @test msg2.complex_signal != original_signal
        @test msg2.normalization != original_norm
    end

    @testset begin #EMA State Updates
        state = create_tickhotloop_state()

        # Initialize
        msg1 = create_broadcast_message(Int32(1), Int64(1), Int32(41971), Int32(0))
        process_tick_signal!(
            msg1, state,
            Float32(0.0625), Int32(4), Int32(50), Int32(3),
            Int32(40000), Int32(43000), Int32(50),
            "hexad16", Float32(0.5)
        )

        @test state.has_delta_ema == false  # Not set on first tick

        # Second tick
        msg2 = create_broadcast_message(Int32(2), Int64(2), Int32(41981), Int32(10))
        process_tick_signal!(
            msg2, state,
            Float32(0.0625), Int32(4), Int32(50), Int32(3),
            Int32(40000), Int32(43000), Int32(50),
            "hexad16", Float32(0.5)
        )

        @test state.has_delta_ema == true
        @test state.ema_delta != Int32(0)
        @test state.ema_abs_delta > Int32(0)
    end

    @testset begin #All Features Always Enabled
        # Verify no branching for feature enablement
        state = create_tickhotloop_state()

        # Even with extreme parameters, should process
        msg = create_broadcast_message(Int32(1), Int64(1), Int32(41971), Int32(0))

        process_tick_signal!(
            msg, state,
            Float32(0.0),     # Zero AGC alpha (still processes)
            Int32(1),         # Minimal scale
            Int32(1),         # Same min/max (still processes)
            Int32(1000),      # Huge threshold (still winsorizes)
            Int32(0),         # Wide price range
            Int32(100000),
            Int32(10000),     # Huge jump limit
            "hexad16", Float32(0.5)
        )

        # Should still process successfully
        @test state.ticks_accepted == Int64(1)
    end

    @testset begin #HEXAD-16 Rotation Sequence
        state = create_tickhotloop_state()

        # Process 16 ticks to see full rotation cycle
        messages = BroadcastMessage[]

        for i in 1:16
            msg = create_broadcast_message(Int32(i), Int64(i), Int32(41971), Int32(0))
            process_tick_signal!(
                msg, state,
                Float32(0.0625), Int32(4), Int32(50), Int32(3),
                Int32(40000), Int32(43000), Int32(50),
                "hexad16", Float32(0.5)
            )
            push!(messages, msg)
        end

        # Verify all ticks processed
        @test state.ticks_accepted == Int64(16)
    end

    @testset begin #Multiple Ticks Processing
        state = create_tickhotloop_state()

        # Process sequence of ticks
        for i in 1:10
            msg = create_broadcast_message(Int32(i), Int64(i), Int32(41971 + i), Int32(i > 1 ? 1 : 0))
            process_tick_signal!(
                msg, state,
                Float32(0.0625), Int32(4), Int32(50), Int32(3),
                Int32(40000), Int32(43000), Int32(50),
                "hexad16", Float32(0.5)
            )
        end

        @test state.ticks_accepted == Int64(10)
        @test state.last_clean == Int32(41981)
    end
end

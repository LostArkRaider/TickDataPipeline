# test/test_barprocessor.jl - Bar Processor Unit Tests
# Comprehensive tests for bar aggregation and signal processing
# Protocol T-36 compliant: No string literals in @test

using Test
using TickDataPipeline

# Test Set 1: Configuration Creation and Validation
@testset begin
    # Default configuration
    config = BarProcessingConfig()
    @test config.enabled == false
    @test config.ticks_per_bar == Int32(144)
    @test config.normalization_window_bars == Int32(24)
    @test config.winsorize_bar_threshold == Int32(50)
    @test config.max_bar_jump == Int32(100)
    @test config.bar_derivative_imag_scale == Float32(4.0)

    # Custom configuration
    config_custom = BarProcessingConfig(
        enabled = true,
        ticks_per_bar = Int32(21),
        normalization_window_bars = Int32(120),
        winsorize_bar_threshold = Int32(25),
        max_bar_jump = Int32(75),
        bar_derivative_imag_scale = Float32(2.0)
    )
    @test config_custom.enabled == true
    @test config_custom.ticks_per_bar == Int32(21)
    @test config_custom.normalization_window_bars == Int32(120)
    @test config_custom.winsorize_bar_threshold == Int32(25)
    @test config_custom.max_bar_jump == Int32(75)
    @test config_custom.bar_derivative_imag_scale == Float32(2.0)

    # Validation via PipelineConfig
    full_config = PipelineConfig(
        bar_processing = BarProcessingConfig(
            enabled = true,
            ticks_per_bar = Int32(21),
            normalization_window_bars = Int32(120)
        )
    )
    is_valid, errors = validate_config(full_config)
    @test is_valid == true
    @test isempty(errors)

    # Validation failure: normalization_window_bars < 20 with enabled
    full_config_invalid = PipelineConfig(
        bar_processing = BarProcessingConfig(
            enabled = true,
            normalization_window_bars = Int32(10)
        )
    )
    is_valid_invalid, errors_invalid = validate_config(full_config_invalid)
    @test is_valid_invalid == false
    @test length(errors_invalid) > 0
end

# Test Set 2: State Initialization
@testset begin
    config = BarProcessingConfig(
        enabled = true,
        ticks_per_bar = Int32(21)
    )
    state = create_bar_processor_state(config)

    # Initial values
    @test state.tick_count == Int32(0)
    @test state.bar_idx == Int64(0)
    @test state.bar_open_raw == Int32(0)
    @test state.bar_high_raw == typemin(Int32)
    @test state.bar_low_raw == typemax(Int32)
    @test state.bar_close_raw == Int32(0)

    # Statistics
    @test state.sum_bar_average_high == Int64(0)
    @test state.sum_bar_average_low == Int64(0)
    @test state.bars_completed == Int64(0)
    @test state.cached_bar_normalization == Float32(1.0)
    @test state.ticks_since_recalc == Int32(0)

    # Derivative state
    @test state.prev_bar_average_raw === nothing

    # Config reference
    @test state.config.ticks_per_bar == Int32(21)
end

# Test Set 3: Bar Accumulation (OHLC Tracking)
@testset begin
    config = BarProcessingConfig(enabled = true, ticks_per_bar = Int32(5))
    state = create_bar_processor_state(config)

    # First tick: Initialize OHLC
    msg1 = create_broadcast_message(Int32(1), Int64(1000), Int32(40000), Int32(0))
    process_tick_for_bars!(msg1, state)
    @test state.bar_open_raw == Int32(40000)
    @test state.bar_high_raw == Int32(40000)
    @test state.bar_low_raw == Int32(40000)
    @test state.bar_close_raw == Int32(40000)
    @test state.tick_count == Int32(1)
    @test msg1.bar_idx === nothing  # Bar not complete

    # Second tick: Update HLC
    msg2 = create_broadcast_message(Int32(2), Int64(1001), Int32(40010), Int32(10))
    process_tick_for_bars!(msg2, state)
    @test state.bar_open_raw == Int32(40000)  # Open unchanged
    @test state.bar_high_raw == Int32(40010)  # High updated
    @test state.bar_low_raw == Int32(40000)   # Low unchanged
    @test state.bar_close_raw == Int32(40010)  # Close updated
    @test state.tick_count == Int32(2)

    # Third tick: Lower price
    msg3 = create_broadcast_message(Int32(3), Int64(1002), Int32(39990), Int32(-10))
    process_tick_for_bars!(msg3, state)
    @test state.bar_open_raw == Int32(40000)
    @test state.bar_high_raw == Int32(40010)  # High unchanged
    @test state.bar_low_raw == Int32(39990)   # Low updated
    @test state.bar_close_raw == Int32(39990)  # Close updated
    @test state.tick_count == Int32(3)

    # Fourth tick: Higher price
    msg4 = create_broadcast_message(Int32(4), Int64(1003), Int32(40020), Int32(30))
    process_tick_for_bars!(msg4, state)
    @test state.bar_high_raw == Int32(40020)  # High updated
    @test state.bar_low_raw == Int32(39990)   # Low unchanged
    @test state.tick_count == Int32(4)

    # Fifth tick: Bar completion
    msg5 = create_broadcast_message(Int32(5), Int64(1004), Int32(40015), Int32(-5))
    process_tick_for_bars!(msg5, state)
    @test msg5.bar_idx == Int64(1)  # Bar complete!
    @test msg5.bar_open_raw == Int32(40000)
    @test msg5.bar_high_raw == Int32(40020)
    @test msg5.bar_low_raw == Int32(39990)
    @test msg5.bar_close_raw == Int32(40015)
    @test state.tick_count == Int32(0)  # Reset for next bar
    @test state.bar_idx == Int64(1)
end

# Test Set 4: Bar Completion and Reset
@testset begin
    config = BarProcessingConfig(enabled = true, ticks_per_bar = Int32(3))
    state = create_bar_processor_state(config)

    # Process first bar
    for i in 1:3
        msg = create_broadcast_message(Int32(i), Int64(1000+i), Int32(40000+i), Int32(1))
        process_tick_for_bars!(msg, state)
        if i < 3
            @test msg.bar_idx === nothing  # Not complete
        else
            @test msg.bar_idx == Int64(1)  # Complete
        end
    end

    # Verify reset for second bar
    @test state.tick_count == Int32(0)
    @test state.bar_idx == Int64(1)

    # Process second bar
    for i in 1:3
        msg = create_broadcast_message(Int32(i+3), Int64(1003+i), Int32(40010+i), Int32(1))
        process_tick_for_bars!(msg, state)
        if i < 3
            @test msg.bar_idx === nothing
        else
            @test msg.bar_idx == Int64(2)
        end
    end

    @test state.bars_completed == Int64(2)
end

# Test Set 5: Normalization Calculation
@testset begin
    config = BarProcessingConfig(
        enabled = true,
        ticks_per_bar = Int32(2),
        normalization_window_bars = Int32(10)  # Recalc every 20 ticks
    )
    state = create_bar_processor_state(config)

    # Initial normalization
    initial_norm = state.cached_bar_normalization
    @test initial_norm == Float32(1.0)

    # Complete first bar (high=40100, low=40000)
    msg1 = create_broadcast_message(Int32(1), Int64(1000), Int32(40000), Int32(0))
    process_tick_for_bars!(msg1, state)
    msg2 = create_broadcast_message(Int32(2), Int64(1001), Int32(40100), Int32(100))
    process_tick_for_bars!(msg2, state)

    # Normalization not recalculated yet (need 10 bars)
    @test state.cached_bar_normalization == Float32(1.0)
    @test state.sum_bar_average_high == Int64(40100)
    @test state.sum_bar_average_low == Int64(40000)
    @test state.bars_completed == Int64(1)

    # Complete 9 more bars (total 10 bars = 20 ticks)
    for bar in 2:10
        for tick in 1:2
            price = Int32(40000 + bar * 10 + tick)
            msg = create_broadcast_message(Int32((bar-1)*2 + tick), Int64(1000 + (bar-1)*2 + tick), price, Int32(10))
            process_tick_for_bars!(msg, state)
        end
    end

    # After 10 bars, normalization should be recalculated
    @test state.bars_completed == Int64(10)
    @test state.ticks_since_recalc == Int32(0)  # Reset after recalc

    # Verify normalization is based on avg(high) - avg(low)
    avg_high = Float32(state.sum_bar_average_high) / Float32(10)
    avg_low = Float32(state.sum_bar_average_low) / Float32(10)
    expected_norm = avg_high - avg_low
    @test state.cached_bar_normalization ≈ expected_norm
end

# Test Set 6: Recalculation Period
@testset begin
    config = BarProcessingConfig(
        enabled = true,
        ticks_per_bar = Int32(3),
        normalization_window_bars = Int32(5)  # Recalc every 15 ticks
    )
    state = create_bar_processor_state(config)

    recalc_period = config.normalization_window_bars * config.ticks_per_bar
    @test recalc_period == Int32(15)

    # Process ticks and track recalculation by watching bar completion
    prev_norm = state.cached_bar_normalization
    recalc_bars = Int64[]

    for i in 1:30  # Process 30 ticks (10 bars)
        msg = create_broadcast_message(Int32(i), Int64(1000+i), Int32(40000+i), Int32(1))
        process_tick_for_bars!(msg, state)

        # Check if this message completed a bar and triggered recalc
        if msg.bar_idx !== nothing
            # Bar completed - check if normalization was recalculated
            if state.ticks_since_recalc == Int32(0) && state.bars_completed >= Int64(5)
                push!(recalc_bars, msg.bar_idx)
            end
        end
    end

    # Should have recalculations at bars 5 and 10
    @test length(recalc_bars) >= 2
    @test state.bars_completed == Int64(10)
end

# Test Set 7: Jump Guard Clipping
@testset begin
    config = BarProcessingConfig(
        enabled = true,
        ticks_per_bar = Int32(2),
        max_bar_jump = Int32(50)
    )
    state = create_bar_processor_state(config)

    # First bar: avg = 40050
    msg1 = create_broadcast_message(Int32(1), Int64(1000), Int32(40000), Int32(0))
    process_tick_for_bars!(msg1, state)
    msg2 = create_broadcast_message(Int32(2), Int64(1001), Int32(40100), Int32(100))
    process_tick_for_bars!(msg2, state)
    @test msg2.bar_idx == Int64(1)

    # Second bar: Large jump (delta = 200, exceeds max_jump=50)
    msg3 = create_broadcast_message(Int32(3), Int64(1002), Int32(40200), Int32(100))
    process_tick_for_bars!(msg3, state)
    msg4 = create_broadcast_message(Int32(4), Int64(1003), Int32(40300), Int32(100))
    process_tick_for_bars!(msg4, state)
    @test msg4.bar_idx == Int64(2)

    # Check that bar_price_delta was clipped to max_bar_jump
    @test abs(msg4.bar_price_delta) <= config.max_bar_jump
    @test msg4.bar_flags & FLAG_CLIPPED == FLAG_CLIPPED

    # Third bar: Negative large jump
    msg5 = create_broadcast_message(Int32(5), Int64(1004), Int32(39800), Int32(-200))
    process_tick_for_bars!(msg5, state)
    msg6 = create_broadcast_message(Int32(6), Int64(1005), Int32(39900), Int32(100))
    process_tick_for_bars!(msg6, state)
    @test msg6.bar_idx == Int64(3)
    @test abs(msg6.bar_price_delta) <= config.max_bar_jump
    @test msg6.bar_flags & FLAG_CLIPPED == FLAG_CLIPPED
end

# Test Set 8: Winsorizing
@testset begin
    config = BarProcessingConfig(
        enabled = true,
        ticks_per_bar = Int32(2),
        winsorize_bar_threshold = Int32(100),
        max_bar_jump = Int32(200)  # Set jump guard higher than winsorize
    )
    state = create_bar_processor_state(config)

    # First bar: avg = (40000+40020+40020)/3 ≈ 40013
    msg1 = create_broadcast_message(Int32(1), Int64(1000), Int32(40000), Int32(0))
    process_tick_for_bars!(msg1, state)
    msg2 = create_broadcast_message(Int32(2), Int64(1001), Int32(40020), Int32(20))
    process_tick_for_bars!(msg2, state)
    @test msg2.bar_idx == Int64(1)

    # Second bar: avg = (40030+40050+40050)/3 ≈ 40043, delta ≈ 30 (within threshold)
    msg3 = create_broadcast_message(Int32(3), Int64(1002), Int32(40030), Int32(10))
    process_tick_for_bars!(msg3, state)
    msg4 = create_broadcast_message(Int32(4), Int64(1003), Int32(40050), Int32(20))
    process_tick_for_bars!(msg4, state)
    @test msg4.bar_idx == Int64(2)
    @test msg4.bar_flags == FLAG_OK  # No clipping

    # Third bar: avg = (40200+40400+40400)/3 ≈ 40333, delta ≈ 290 (exceeds threshold)
    msg5 = create_broadcast_message(Int32(5), Int64(1004), Int32(40200), Int32(150))
    process_tick_for_bars!(msg5, state)
    msg6 = create_broadcast_message(Int32(6), Int64(1005), Int32(40400), Int32(200))
    process_tick_for_bars!(msg6, state)
    @test msg6.bar_idx == Int64(3)
    @test abs(msg6.bar_price_delta) <= config.winsorize_bar_threshold
    @test msg6.bar_flags & FLAG_CLIPPED == FLAG_CLIPPED
end

# Test Set 9: Derivative Encoding
@testset begin
    config = BarProcessingConfig(
        enabled = true,
        ticks_per_bar = Int32(2),
        bar_derivative_imag_scale = Float32(4.0)
    )
    state = create_bar_processor_state(config)

    # First bar: bar_price_delta = 0 (no previous bar)
    # Real = 0/normalization = 0
    # Imaginary = (current_normalized - 0) * 4.0 = large value
    msg1 = create_broadcast_message(Int32(1), Int64(1000), Int32(40000), Int32(0))
    process_tick_for_bars!(msg1, state)
    msg2 = create_broadcast_message(Int32(2), Int64(1001), Int32(40100), Int32(100))
    process_tick_for_bars!(msg2, state)
    @test msg2.bar_idx == Int64(1)
    @test msg2.bar_complex_signal !== nothing
    @test real(msg2.bar_complex_signal) == Float32(0.0)  # No delta (first bar)
    @test imag(msg2.bar_complex_signal) != Float32(0.0)  # Velocity from zero

    # Second bar: Both real and imaginary should be non-zero
    msg3 = create_broadcast_message(Int32(3), Int64(1002), Int32(40150), Int32(50))
    process_tick_for_bars!(msg3, state)
    msg4 = create_broadcast_message(Int32(4), Int64(1003), Int32(40200), Int32(50))
    process_tick_for_bars!(msg4, state)
    @test msg4.bar_idx == Int64(2)
    @test real(msg4.bar_complex_signal) != Float32(0.0)  # Position (delta)
    @test imag(msg4.bar_complex_signal) != Float32(0.0)  # Velocity (change in normalized)

    # Third bar: Verify scaling factor is applied
    msg5 = create_broadcast_message(Int32(5), Int64(1004), Int32(40250), Int32(50))
    process_tick_for_bars!(msg5, state)
    msg6 = create_broadcast_message(Int32(6), Int64(1005), Int32(40300), Int32(50))
    process_tick_for_bars!(msg6, state)
    @test msg6.bar_idx == Int64(3)
    # Imaginary component should be scaled by bar_derivative_imag_scale
    @test abs(imag(msg6.bar_complex_signal)) > Float32(0.0)
end

# Test Set 10: Disabled Bar Processing
@testset begin
    config = BarProcessingConfig(enabled = false, ticks_per_bar = Int32(3))
    state = create_bar_processor_state(config)

    # Process ticks with disabled bar processing
    for i in 1:6
        msg = create_broadcast_message(Int32(i), Int64(1000+i), Int32(40000+i*10), Int32(10))
        process_tick_for_bars!(msg, state)

        # All bar fields should remain nothing
        @test msg.bar_idx === nothing
        @test msg.bar_ticks === nothing
        @test msg.bar_volume === nothing
        @test msg.bar_open_raw === nothing
        @test msg.bar_high_raw === nothing
        @test msg.bar_low_raw === nothing
        @test msg.bar_close_raw === nothing
        @test msg.bar_average_raw === nothing
        @test msg.bar_price_delta === nothing
        @test msg.bar_complex_signal === nothing
        @test msg.bar_normalization === nothing
        @test msg.bar_flags === nothing
        @test msg.bar_end_timestamp === nothing
    end

    # State should not advance
    @test state.tick_count == Int32(0)
    @test state.bar_idx == Int64(0)
    @test state.bars_completed == Int64(0)
end

# Additional tests: Bar metadata
@testset begin
    config = BarProcessingConfig(enabled = true, ticks_per_bar = Int32(4))
    state = create_bar_processor_state(config)

    # Complete one bar
    for i in 1:4
        msg = create_broadcast_message(Int32(i), Int64(2000+i), Int32(41000+i*5), Int32(5))
        process_tick_for_bars!(msg, state)
        if i == 4
            # Verify metadata on bar completion
            @test msg.bar_idx == Int64(1)
            @test msg.bar_ticks == Int32(4)
            @test msg.bar_volume == Int32(4)  # 1 contract per tick
            @test msg.bar_end_timestamp == UInt64(2004)  # Last tick timestamp
            @test msg.bar_normalization != Float32(0.0)
        end
    end
end

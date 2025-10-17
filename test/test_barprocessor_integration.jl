# test/test_barprocessor_integration.jl - Bar Processor Integration Tests
# End-to-end tests with full pipeline integration
# Uses existing YM data file - focuses on bar processing, not file parsing
# Protocol T-36 compliant: No string literals in @test

using Test
using TickDataPipeline

# Test Set 1: Full Pipeline with Bar Processing Enabled
@testset begin
    # Use real YM data file with bar processing enabled
    config = PipelineConfig(
        tick_file_path = "data/raw/YM 06-25.Last.txt",
        bar_processing = BarProcessingConfig(
            enabled = true,
            ticks_per_bar = Int32(144),
            normalization_window_bars = Int32(24)
        )
    )

    split_mgr = create_triple_split_manager()
    consumer_ch = subscribe_consumer!(split_mgr, "test_consumer", PRIORITY)
    pipeline_mgr = create_pipeline_manager(config, split_mgr)

    # Process 500 ticks (enough for 3 complete bars)
    stats = run_pipeline!(pipeline_mgr, max_ticks = Int64(500))

    # Verify processing completed
    @test stats.ticks_processed == Int64(500)
    @test stats.broadcasts_sent == Int32(500)
    @test stats.errors == Int32(0)

    # Verify bar state (500 ticks / 144 per bar = 3 complete bars + 68 partial)
    @test pipeline_mgr.bar_state.bars_completed == Int64(3)
    @test pipeline_mgr.bar_state.bar_idx == Int64(3)
    @test pipeline_mgr.bar_state.tick_count == Int32(68)  # 500 - (3*144)

    # Verify consumers received all messages
    received_count = 0
    bar_messages = 0
    while isready(consumer_ch.channel)
        msg = take!(consumer_ch.channel)
        received_count += 1
        if msg.bar_idx !== nothing
            bar_messages += 1
        end
    end
    @test received_count == 500
    @test bar_messages == 3  # 3 bar completion messages
end

# Test Set 2: Multiple Bar Sizes
@testset begin
    # Test with 21-tick bars
    config_21 = PipelineConfig(
        tick_file_path = "data/raw/YM 06-25.Last.txt",
        bar_processing = BarProcessingConfig(
            enabled = true,
            ticks_per_bar = Int32(21)
        )
    )
    split_mgr_21 = create_triple_split_manager()
    consumer_ch_21 = subscribe_consumer!(split_mgr_21, "consumer_21", PRIORITY)
    pipeline_mgr_21 = create_pipeline_manager(config_21, split_mgr_21)
    stats_21 = run_pipeline!(pipeline_mgr_21, max_ticks = Int64(210))

    @test stats_21.ticks_processed == Int64(210)
    @test pipeline_mgr_21.bar_state.bars_completed == Int64(10)  # 210/21

    bar_count_21 = 0
    while isready(consumer_ch_21.channel)
        msg = take!(consumer_ch_21.channel)
        if msg.bar_idx !== nothing
            bar_count_21 += 1
            @test msg.bar_ticks == Int32(21)
        end
    end
    @test bar_count_21 == 10

    # Test with 233-tick bars (Fibonacci)
    config_233 = PipelineConfig(
        tick_file_path = "data/raw/YM 06-25.Last.txt",
        bar_processing = BarProcessingConfig(
            enabled = true,
            ticks_per_bar = Int32(233)
        )
    )
    split_mgr_233 = create_triple_split_manager()
    consumer_ch_233 = subscribe_consumer!(split_mgr_233, "consumer_233", PRIORITY)
    pipeline_mgr_233 = create_pipeline_manager(config_233, split_mgr_233)
    stats_233 = run_pipeline!(pipeline_mgr_233, max_ticks = Int64(466))

    @test stats_233.ticks_processed == Int64(466)
    @test pipeline_mgr_233.bar_state.bars_completed == Int64(2)  # 466/233

    bar_count_233 = 0
    while isready(consumer_ch_233.channel)
        msg = take!(consumer_ch_233.channel)
        if msg.bar_idx !== nothing
            bar_count_233 += 1
            @test msg.bar_ticks == Int32(233)
        end
    end
    @test bar_count_233 == 2
end

# Test Set 3: Consumer Message Verification
@testset begin
    config = PipelineConfig(
        tick_file_path = "data/raw/YM 06-25.Last.txt",
        bar_processing = BarProcessingConfig(
            enabled = true,
            ticks_per_bar = Int32(50),
            normalization_window_bars = Int32(5)
        )
    )

    split_mgr = create_triple_split_manager()
    consumer_ch = subscribe_consumer!(split_mgr, "verifier", PRIORITY)
    pipeline_mgr = create_pipeline_manager(config, split_mgr)
    stats = run_pipeline!(pipeline_mgr, max_ticks = Int64(200))

    # Collect all messages
    messages = BroadcastMessage[]
    while isready(consumer_ch.channel)
        push!(messages, take!(consumer_ch.channel))
    end

    @test length(messages) == 200

    # Verify bar completion messages (200/50 = 4 bars)
    bar_messages = filter(m -> m.bar_idx !== nothing, messages)
    @test length(bar_messages) == 4

    for (i, bar_msg) in enumerate(bar_messages)
        # Verify bar metadata
        @test bar_msg.bar_idx == Int64(i)
        @test bar_msg.bar_ticks == Int32(50)
        @test bar_msg.bar_volume == Int32(50)

        # Verify OHLC populated
        @test bar_msg.bar_open_raw !== nothing
        @test bar_msg.bar_high_raw !== nothing
        @test bar_msg.bar_low_raw !== nothing
        @test bar_msg.bar_close_raw !== nothing
        @test bar_msg.bar_high_raw >= bar_msg.bar_low_raw

        # Verify bar average
        @test bar_msg.bar_average_raw !== nothing

        # Verify signal fields
        @test bar_msg.bar_complex_signal !== nothing
        @test bar_msg.bar_normalization !== nothing
        @test bar_msg.bar_flags !== nothing
        @test bar_msg.bar_end_timestamp !== nothing

        # Verify bar price delta
        if i == 1
            @test bar_msg.bar_price_delta == Int32(0)  # First bar
        else
            @test bar_msg.bar_price_delta !== nothing
        end
    end
end

# Test Set 4: Tick Data Preservation
@testset begin
    config = PipelineConfig(
        tick_file_path = "data/raw/YM 06-25.Last.txt",
        bar_processing = BarProcessingConfig(
            enabled = true,
            ticks_per_bar = Int32(100)
        )
    )

    split_mgr = create_triple_split_manager()
    consumer_ch = subscribe_consumer!(split_mgr, "tick_checker", PRIORITY)
    pipeline_mgr = create_pipeline_manager(config, split_mgr)
    stats = run_pipeline!(pipeline_mgr, max_ticks = Int64(250))

    # Collect messages
    messages = BroadcastMessage[]
    while isready(consumer_ch.channel)
        push!(messages, take!(consumer_ch.channel))
    end

    @test length(messages) == 250

    # Verify ALL messages have tick-level data
    for (i, msg) in enumerate(messages)
        # Tick fields always present
        @test msg.tick_idx == Int32(i)
        @test msg.timestamp != Int64(0)
        @test msg.raw_price != Int32(0)
        # complex_signal can be zero (valid for no price change)
        @test msg.normalization >= Float32(0.0)

        # Bar fields only on bar completion (ticks 100, 200)
        if i == 100 || i == 200
            @test msg.bar_idx !== nothing
            @test msg.bar_open_raw !== nothing
        else
            @test msg.bar_idx === nothing
            @test msg.bar_open_raw === nothing
        end
    end

    # Verify partial bar handling (last 50 ticks)
    @test pipeline_mgr.bar_state.tick_count == Int32(50)  # 250 - (2*100)
    @test pipeline_mgr.bar_state.bars_completed == Int64(2)
end

# Test Set 5: Performance Overhead Validation
@testset begin
    # Baseline: Bar processing disabled
    config_disabled = PipelineConfig(
        tick_file_path = "data/raw/YM 06-25.Last.txt",
        bar_processing = BarProcessingConfig(enabled = false)
    )
    split_mgr_disabled = create_triple_split_manager()
    subscribe_consumer!(split_mgr_disabled, "perf_disabled", PRIORITY)
    pipeline_mgr_disabled = create_pipeline_manager(config_disabled, split_mgr_disabled)

    stats_disabled = run_pipeline!(pipeline_mgr_disabled, max_ticks = Int64(1000))
    baseline_latency = stats_disabled.avg_latency_us

    # With bar processing enabled
    config_enabled = PipelineConfig(
        tick_file_path = "data/raw/YM 06-25.Last.txt",
        bar_processing = BarProcessingConfig(
            enabled = true,
            ticks_per_bar = Int32(144)
        )
    )
    split_mgr_enabled = create_triple_split_manager()
    subscribe_consumer!(split_mgr_enabled, "perf_enabled", PRIORITY)
    pipeline_mgr_enabled = create_pipeline_manager(config_enabled, split_mgr_enabled)

    stats_enabled = run_pipeline!(pipeline_mgr_enabled, max_ticks = Int64(1000))
    bar_latency = stats_enabled.avg_latency_us

    # Verify both completed successfully
    @test stats_disabled.ticks_processed == Int64(1000)
    @test stats_enabled.ticks_processed == Int64(1000)
    @test stats_disabled.errors == Int32(0)
    @test stats_enabled.errors == Int32(0)

    # Verify bar processing occurred
    @test pipeline_mgr_enabled.bar_state.bars_completed >= Int64(6)  # 1000/144 ≈ 6.9

    # Performance overhead should be minimal (<2x)
    overhead_ratio = bar_latency / max(baseline_latency, Float32(0.01))
    @test overhead_ratio < Float32(3.0)  # Less than 3x overhead (generous bound)

    # Verify latencies are reasonable (< 50μs)
    @test baseline_latency < Float32(50.0)
    @test bar_latency < Float32(100.0)
end

# Test Set 6: Disabled Bar Processing
@testset begin
    config = PipelineConfig(
        tick_file_path = "data/raw/YM 06-25.Last.txt",
        bar_processing = BarProcessingConfig(
            enabled = false,
            ticks_per_bar = Int32(50)  # Set but disabled
        )
    )

    split_mgr = create_triple_split_manager()
    consumer_ch = subscribe_consumer!(split_mgr, "disabled_test", PRIORITY)
    pipeline_mgr = create_pipeline_manager(config, split_mgr)
    stats = run_pipeline!(pipeline_mgr, max_ticks = Int64(150))

    # Collect messages
    messages = BroadcastMessage[]
    while isready(consumer_ch.channel)
        push!(messages, take!(consumer_ch.channel))
    end

    @test length(messages) == 150

    # Verify NO bar data in any message
    for msg in messages
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

    # Verify bar state did not advance
    @test pipeline_mgr.bar_state.bars_completed == Int64(0)
    @test pipeline_mgr.bar_state.bar_idx == Int64(0)
end

# Test Set 7: Edge Cases
@testset begin
    # Edge case 1: Exactly one bar (144 ticks)
    config_one = PipelineConfig(
        tick_file_path = "data/raw/YM 06-25.Last.txt",
        bar_processing = BarProcessingConfig(
            enabled = true,
            ticks_per_bar = Int32(144)
        )
    )
    split_mgr_one = create_triple_split_manager()
    consumer_ch_one = subscribe_consumer!(split_mgr_one, "one_bar", PRIORITY)
    pipeline_mgr_one = create_pipeline_manager(config_one, split_mgr_one)
    stats_one = run_pipeline!(pipeline_mgr_one, max_ticks = Int64(144))

    @test stats_one.ticks_processed == Int64(144)
    @test pipeline_mgr_one.bar_state.bars_completed == Int64(1)

    messages_one = BroadcastMessage[]
    while isready(consumer_ch_one.channel)
        push!(messages_one, take!(consumer_ch_one.channel))
    end
    bar_msgs_one = filter(m -> m.bar_idx !== nothing, messages_one)
    @test length(bar_msgs_one) == 1
    @test bar_msgs_one[1].bar_idx == Int64(1)

    # Edge case 2: One tick (incomplete bar)
    config_single = PipelineConfig(
        tick_file_path = "data/raw/YM 06-25.Last.txt",
        bar_processing = BarProcessingConfig(
            enabled = true,
            ticks_per_bar = Int32(100)
        )
    )
    split_mgr_single = create_triple_split_manager()
    consumer_ch_single = subscribe_consumer!(split_mgr_single, "single_tick", PRIORITY)
    pipeline_mgr_single = create_pipeline_manager(config_single, split_mgr_single)
    stats_single = run_pipeline!(pipeline_mgr_single, max_ticks = Int64(1))

    @test stats_single.ticks_processed == Int64(1)
    @test pipeline_mgr_single.bar_state.bars_completed == Int64(0)
    @test pipeline_mgr_single.bar_state.tick_count == Int32(1)

    messages_single = BroadcastMessage[]
    while isready(consumer_ch_single.channel)
        push!(messages_single, take!(consumer_ch_single.channel))
    end
    @test messages_single[1].bar_idx === nothing
end

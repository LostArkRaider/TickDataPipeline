using Test
using TickDataPipeline

@testset begin #PipelineManager
    @testset begin #PipelineManager Creation
        config = create_default_config()
        split_mgr = create_triple_split_manager()

        pipeline_mgr = create_pipeline_manager(config, split_mgr)

        @test pipeline_mgr.config === config
        @test pipeline_mgr.split_manager === split_mgr
        @test pipeline_mgr.is_running == false
        @test pipeline_mgr.completion_callback === nothing
        @test pipeline_mgr.tickhotloop_state.tick_count == Int64(0)

        # Verify metrics initialized
        @test pipeline_mgr.metrics.ticks_processed == Int64(0)
        @test pipeline_mgr.metrics.broadcasts_sent == Int32(0)
        @test pipeline_mgr.metrics.errors == Int32(0)
        @test pipeline_mgr.metrics.max_latency_us == Int32(0)
        @test pipeline_mgr.metrics.min_latency_us == typemax(Int32)
    end

    @testset begin #Single Tick Processing
        config = create_default_config()
        split_mgr = create_triple_split_manager()
        consumer = subscribe_consumer!(split_mgr, "test", PRIORITY, Int32(10))

        pipeline_mgr = create_pipeline_manager(config, split_mgr)

        # Create and process a message
        msg = create_broadcast_message(Int32(1), Int64(1), Int32(41971), Int32(0))
        result = process_single_tick_through_pipeline!(pipeline_mgr, msg)

        @test result.success == true
        @test result.total_latency_us >= Int32(0)
        @test result.signal_processing_time_us >= Int32(0)
        @test result.broadcast_time_us >= Int32(0)
        @test result.consumers_reached == Int32(1)

        # Verify message was processed
        @test msg.complex_signal == ComplexF32(0, 0)  # First tick has zero signal
        @test msg.normalization == Float32(1.0)

        # Verify metrics updated
        @test pipeline_mgr.metrics.total_latency_us >= Int64(0)
        @test pipeline_mgr.metrics.signal_processing_time_us >= Int64(0)
        @test pipeline_mgr.metrics.broadcast_time_us >= Int64(0)

        # Verify consumer received message
        @test consumer.channel.n_avail_items == 1
    end

    @testset begin #Multiple Tick Metrics
        config = create_default_config()
        split_mgr = create_triple_split_manager()
        subscribe_consumer!(split_mgr, "test", PRIORITY, Int32(100))

        pipeline_mgr = create_pipeline_manager(config, split_mgr)

        # Process multiple messages
        for i in 1:10
            msg = create_broadcast_message(Int32(i), Int64(i), Int32(41970 + i), Int32(1))
            result = process_single_tick_through_pipeline!(pipeline_mgr, msg)
            @test result.success == true
        end

        # Verify metrics accumulated
        @test pipeline_mgr.metrics.total_latency_us > Int64(0)
        @test pipeline_mgr.metrics.max_latency_us > Int32(0)
        @test pipeline_mgr.metrics.min_latency_us > Int32(0)
        @test pipeline_mgr.metrics.min_latency_us <= pipeline_mgr.metrics.max_latency_us
    end

    @testset begin #run_pipeline! with PipelineManager
        # Create test file
        test_file = "test_pipeline_mgr.txt"
        open(test_file, "w") do f
            println(f, "20250319 070000 0520000;41971;41970;41971;1")
            println(f, "20250319 070001 0520000;41972;41971;41972;1")
            println(f, "20250319 070002 0520000;41973;41972;41973;1")
            println(f, "20250319 070003 0520000;41974;41973;41974;1")
            println(f, "20250319 070004 0520000;41975;41974;41975;1")
        end

        try
            config = PipelineConfig(
                tick_file_path = test_file,
                flow_control = FlowControlConfig(delay_ms = 0.0)
            )
            split_mgr = create_triple_split_manager()
            consumer = subscribe_consumer!(split_mgr, "test", PRIORITY, Int32(100))

            pipeline_mgr = create_pipeline_manager(config, split_mgr)

            # Run pipeline
            stats = run_pipeline!(pipeline_mgr, max_ticks = Int64(5))

            @test stats.ticks_processed == Int64(5)
            @test stats.broadcasts_sent == Int32(5)
            @test stats.errors == Int32(0)
            @test stats.avg_latency_us >= Float32(0.0)
            @test stats.max_latency_us >= Int32(0)
            @test stats.min_latency_us >= Int32(0)
            @test stats.avg_signal_time_us >= Float32(0.0)
            @test stats.avg_broadcast_time_us >= Float32(0.0)

            # Verify consumer received all messages
            @test consumer.channel.n_avail_items == 5

            # Verify pipeline is no longer running
            @test pipeline_mgr.is_running == false

        finally
            sleep(0.1)
            rm(test_file, force=true)
        end
    end

    @testset begin #Completion Callback
        test_file = "test_callback.txt"
        open(test_file, "w") do f
            println(f, "20250319 070000 0520000;41971;41970;41971;1")
            println(f, "20250319 070001 0520000;41972;41971;41972;1")
            println(f, "20250319 070002 0520000;41973;41972;41973;1")
        end

        try
            config = PipelineConfig(
                tick_file_path = test_file,
                flow_control = FlowControlConfig(delay_ms = 0.0)
            )
            split_mgr = create_triple_split_manager()
            subscribe_consumer!(split_mgr, "test", PRIORITY, Int32(100))

            pipeline_mgr = create_pipeline_manager(config, split_mgr)

            # Set completion callback
            callback_called = Ref(false)
            callback_count = Ref(Int64(0))
            pipeline_mgr.completion_callback = function(count)
                callback_called[] = true
                callback_count[] = count
            end

            # Run pipeline
            stats = run_pipeline!(pipeline_mgr, max_ticks = Int64(3))

            @test callback_called[] == true
            @test callback_count[] == Int64(3)

        finally
            sleep(0.1)
            rm(test_file, force=true)
        end
    end

    @testset begin #Latency Statistics
        test_file = "test_latency.txt"
        open(test_file, "w") do f
            for i in 1:100
                price = 41970 + i
                println(f, "20250319 070000 0520000;$price;$price;$price;1")
            end
        end

        try
            config = PipelineConfig(
                tick_file_path = test_file,
                flow_control = FlowControlConfig(delay_ms = 0.0)
            )
            split_mgr = create_triple_split_manager()
            subscribe_consumer!(split_mgr, "test", PRIORITY, Int32(200))

            pipeline_mgr = create_pipeline_manager(config, split_mgr)
            stats = run_pipeline!(pipeline_mgr, max_ticks = Int64(100))

            @test stats.ticks_processed == Int64(100)
            @test stats.avg_latency_us > Float32(0.0)
            @test stats.max_latency_us >= stats.min_latency_us
            @test stats.min_latency_us > Int32(0)

            # Verify latency components sum correctly (approximately)
            total_time = stats.avg_signal_time_us + stats.avg_broadcast_time_us
            @test abs(stats.avg_latency_us - total_time) < Float32(100.0)  # Within 100μs

        finally
            sleep(0.1)
            rm(test_file, force=true)
        end
    end

    @testset begin #Backward Compatibility
        # Verify old run_pipeline still works
        test_file = "test_compat.txt"
        open(test_file, "w") do f
            println(f, "20250319 070000 0520000;41971;41970;41971;1")
            println(f, "20250319 070001 0520000;41972;41971;41972;1")
        end

        try
            config = PipelineConfig(
                tick_file_path = test_file,
                flow_control = FlowControlConfig(delay_ms = 0.0)
            )
            split_mgr = create_triple_split_manager()
            subscribe_consumer!(split_mgr, "test", PRIORITY, Int32(10))

            # Use old interface
            stats = run_pipeline(config, split_mgr, max_ticks = Int64(2))

            @test stats.ticks_processed == Int64(2)
            @test stats.broadcasts_sent == Int32(2)
            @test stats.errors == Int32(0)

        finally
            sleep(0.1)
            rm(test_file, force=true)
        end
    end
end

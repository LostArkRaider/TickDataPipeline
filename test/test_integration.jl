using Test
using TickDataPipeline

@testset begin #Integration
    @testset begin #Config Creation
        # Load from default config file (single source of truth)
        config = load_config_from_toml("config/default.toml")
        @test config.tick_file_path == "data/raw/YM 06-25.Last.txt"
        @test config.flow_control.delay_ms == 0.0
        @test config.signal_processing.agc_alpha == Float32(0.125)  # From config file
        @test config.signal_processing.agc_min_scale == Int32(4)
        @test config.signal_processing.agc_max_scale == Int32(50)
    end

    @testset begin #Custom Config
        config = PipelineConfig(
            tick_file_path = "test.txt",
            flow_control = FlowControlConfig(delay_ms = 1.0),
            signal_processing = SignalProcessingConfig(
                agc_alpha = Float32(0.1),
                min_price = Int32(1000),
                max_price = Int32(2000)
            )
        )
        @test config.tick_file_path == "test.txt"
        @test config.flow_control.delay_ms == 1.0
        @test config.signal_processing.agc_alpha == Float32(0.1)
        @test config.signal_processing.min_price == Int32(1000)
        @test config.signal_processing.max_price == Int32(2000)
    end

    @testset begin #End-to-End Pipeline
        # Create test data file
        test_file = "test_pipeline.txt"
        open(test_file, "w") do f
            println(f, "20250319 070000 0520000;41971;41970;41971;1")
            println(f, "20250319 070001 0520000;41972;41971;41972;1")
            println(f, "20250319 070002 0520000;41973;41972;41973;1")
            println(f, "20250319 070003 0520000;41974;41973;41974;1")
            println(f, "20250319 070004 0520000;41975;41974;41975;1")
        end

        try
            # Create configuration
            config = PipelineConfig(
                tick_file_path = test_file,
                flow_control = FlowControlConfig(delay_ms = 0.0)
            )

            # Create manager and subscribe consumer
            manager = create_triple_split_manager()
            consumer = subscribe_consumer!(manager, "test_consumer", PRIORITY, Int32(100))

            # Run pipeline
            stats = run_pipeline(config, manager, max_ticks = 5)

            # Verify statistics
            @test stats.ticks_processed == Int64(5)
            @test stats.broadcasts_sent == Int32(5)
            @test stats.errors == Int32(0)

            # Verify consumer received messages
            @test consumer.channel.n_avail_items == 5

            # Verify message content
            msg1 = take!(consumer.channel)
            @test msg1.tick_idx == Int32(1)
            @test msg1.raw_price == Int32(41971)
            @test msg1.price_delta == Int32(0)  # First tick

            msg2 = take!(consumer.channel)
            @test msg2.tick_idx == Int32(2)
            @test msg2.raw_price == Int32(41972)
            @test msg2.price_delta == Int32(1)  # 41972 - 41971

            # Verify signal processing happened
            @test msg2.complex_signal != ComplexF32(0, 0)
            @test msg2.normalization > Float32(0.0)

        finally
            sleep(0.1)
            rm(test_file, force=true)
        end
    end

    @testset begin #Multiple Consumers
        test_file = "test_multi_consumer.txt"
        open(test_file, "w") do f
            for i in 1:10
                price = 41970 + i
                println(f, "20250319 070000 0520000;$price;$price;$price;1")
            end
        end

        try
            config = PipelineConfig(tick_file_path = test_file)
            manager = create_triple_split_manager()

            # Subscribe multiple consumers
            c1 = subscribe_consumer!(manager, "priority", PRIORITY, Int32(100))
            c2 = subscribe_consumer!(manager, "monitoring", MONITORING, Int32(100))
            c3 = subscribe_consumer!(manager, "analytics", ANALYTICS, Int32(100))

            # Run pipeline
            stats = run_pipeline(config, manager, max_ticks = 10)

            @test stats.ticks_processed == Int64(10)
            @test stats.broadcasts_sent == Int32(10)

            # All consumers should receive
            @test c1.channel.n_avail_items == 10
            @test c2.channel.n_avail_items == 10
            @test c3.channel.n_avail_items == 10

        finally
            sleep(0.1)
            rm(test_file, force=true)
        end
    end

    @testset begin #State Preservation
        test_file = "test_state.txt"
        open(test_file, "w") do f
            println(f, "20250319 070000 0520000;41971;41970;41971;1")
            println(f, "20250319 070001 0520000;41981;41980;41981;1")
            println(f, "20250319 070002 0520000;41991;41990;41991;1")
        end

        try
            config = PipelineConfig(tick_file_path = test_file)
            manager = create_triple_split_manager()
            subscribe_consumer!(manager, "test", PRIORITY, Int32(100))

            stats = run_pipeline(config, manager, max_ticks = 3)

            # Verify state was maintained
            @test stats.state.ticks_accepted == Int64(3)
            @test stats.state.last_clean !== nothing
            @test stats.state.has_delta_ema == true

        finally
            sleep(0.1)
            rm(test_file, force=true)
        end
    end

    @testset begin #TOML Config Load/Save
        toml_file = "test_config.toml"

        try
            # Create config and save to TOML
            config = PipelineConfig(
                pipeline_name = "test_pipeline",
                description = "Test configuration",
                version = "1.1",
                tick_file_path = "test.txt",
                signal_processing = SignalProcessingConfig(
                    agc_alpha = Float32(0.125),
                    agc_min_scale = Int32(8),
                    agc_max_scale = Int32(100)
                ),
                flow_control = FlowControlConfig(delay_ms = 2.0),
                channels = ChannelConfig(
                    priority_buffer_size = Int32(8192),
                    standard_buffer_size = Int32(4096)
                ),
                performance = PerformanceConfig(
                    target_latency_us = Int32(250),
                    max_latency_us = Int32(500),
                    target_throughput_tps = Float32(20000.0)
                )
            )

            save_config_to_toml(config, toml_file)
            @test isfile(toml_file)

            # Load config from TOML
            loaded_config = load_config_from_toml(toml_file)

            # Verify all fields
            @test loaded_config.pipeline_name == "test_pipeline"
            @test loaded_config.description == "Test configuration"
            @test loaded_config.version == "1.1"
            @test loaded_config.tick_file_path == "test.txt"

            @test loaded_config.signal_processing.agc_alpha == Float32(0.125)
            @test loaded_config.signal_processing.agc_min_scale == Int32(8)
            @test loaded_config.signal_processing.agc_max_scale == Int32(100)

            @test loaded_config.flow_control.delay_ms == 2.0

            @test loaded_config.channels.priority_buffer_size == Int32(8192)
            @test loaded_config.channels.standard_buffer_size == Int32(4096)

            @test loaded_config.performance.target_latency_us == Int32(250)
            @test loaded_config.performance.max_latency_us == Int32(500)
            @test loaded_config.performance.target_throughput_tps == Float32(20000.0)

        finally
            rm(toml_file, force=true)
        end
    end

    @testset begin #Config Validation
        # Valid config
        valid_config = create_default_config()
        is_valid, errors = validate_config(valid_config)
        @test is_valid
        @test isempty(errors)

        # Invalid AGC range
        invalid_agc = PipelineConfig(
            signal_processing = SignalProcessingConfig(
                agc_min_scale = Int32(100),
                agc_max_scale = Int32(50)
            )
        )
        is_valid, errors = validate_config(invalid_agc)
        @test !is_valid
        @test length(errors) > 0

        # Invalid price range
        invalid_price = PipelineConfig(
            signal_processing = SignalProcessingConfig(
                min_price = Int32(50000),
                max_price = Int32(40000)
            )
        )
        is_valid, errors = validate_config(invalid_price)
        @test !is_valid
        @test length(errors) > 0

        # Invalid latency range
        invalid_latency = PipelineConfig(
            performance = PerformanceConfig(
                target_latency_us = Int32(1000),
                max_latency_us = Int32(500)
            )
        )
        is_valid, errors = validate_config(invalid_latency)
        @test !is_valid
        @test length(errors) > 0
    end
end

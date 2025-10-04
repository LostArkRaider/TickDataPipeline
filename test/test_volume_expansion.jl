using Test
using TickDataPipeline

@testset begin #VolumeExpansion
    @testset begin #Timestamp Encoding
        timestamp = "20250319 070000 0520000"
        encoded = encode_timestamp_to_int64(timestamp)

        @test encoded != Int64(0)
        @test typeof(encoded) == Int64

        # Test round-trip (first 8 chars)
        decoded = decode_timestamp_from_int64(encoded)
        @test decoded == timestamp[1:8]
    end

    @testset begin #Timestamp Encoding Edge Cases
        # Empty string
        @test encode_timestamp_to_int64("") == Int64(0)

        # Short string (still encodes)
        short_encoded = encode_timestamp_to_int64("2025")
        @test short_encoded != Int64(0)
        @test typeof(short_encoded) == Int64

        # Different timestamps produce different encodings
        ts1 = encode_timestamp_to_int64("20250319 070000 0520000")
        ts2 = encode_timestamp_to_int64("20250319 070001 0520000")
        @test ts1 == ts2  # Same first 8 chars

        ts3 = encode_timestamp_to_int64("20250320 070000 0520000")
        @test ts1 != ts3  # Different first 8 chars
    end

    @testset begin #Tick Parsing Valid
        line = "20250319 070000 0520000;41971;41970;41971;1"
        result = parse_tick_line(line)

        @test result !== nothing
        (ts, bid, ask, last, vol) = result
        @test ts == "20250319 070000 0520000"
        @test bid == Int32(41971)
        @test ask == Int32(41970)
        @test last == Int32(41971)
        @test vol == Int32(1)
    end

    @testset begin #Tick Parsing With Volume
        line = "20250319 070001 0520000;41972;41971;41972;3"
        result = parse_tick_line(line)

        @test result !== nothing
        (ts, bid, ask, last, vol) = result
        @test vol == Int32(3)
    end

    @testset begin #Tick Parsing Malformed
        # Wrong number of fields
        bad_line = "20250319;41971;41970"
        @test parse_tick_line(bad_line) === nothing

        # Empty line
        @test parse_tick_line("") === nothing

        # Invalid numbers
        bad_numbers = "20250319 070000 0520000;invalid;41970;41971;1"
        @test parse_tick_line(bad_numbers) === nothing
    end

    @testset begin #Stream Expanded Ticks Basic
        # Create test file
        test_file = "test_ticks_basic.txt"
        open(test_file, "w") do f
            println(f, "20250319 070000 0520000;41971;41970;41971;1")
            println(f, "20250319 070001 0520000;41972;41971;41972;1")
            println(f, "20250319 070002 0520000;41973;41972;41973;1")
        end

        try
            messages = BroadcastMessage[]
            channel = stream_expanded_ticks(test_file, 0.0)

            for msg in channel
                push!(messages, msg)
            end

            # Should have 3 messages (no volume expansion)
            @test length(messages) == 3

            # Check first message
            @test messages[1].tick_idx == Int32(1)
            @test messages[1].raw_price == Int32(41971)
            @test messages[1].price_delta == Int32(0)  # First tick

            # Check second message
            @test messages[2].tick_idx == Int32(2)
            @test messages[2].raw_price == Int32(41972)
            @test messages[2].price_delta == Int32(1)  # 41972 - 41971

            # Check third message
            @test messages[3].tick_idx == Int32(3)
            @test messages[3].raw_price == Int32(41973)
            @test messages[3].price_delta == Int32(1)  # 41973 - 41972

        finally
            rm(test_file, force=true)
        end
    end

    @testset begin #Stream Expanded Ticks With Volume Expansion
        # Create test file with volume > 1
        test_file = "test_ticks_volume.txt"
        open(test_file, "w") do f
            println(f, "20250319 070000 0520000;41971;41970;41971;1")
            println(f, "20250319 070001 0520000;41972;41971;41972;2")
            println(f, "20250319 070002 0520000;41973;41972;41973;1")
        end

        try
            messages = BroadcastMessage[]
            channel = stream_expanded_ticks(test_file, 0.0)

            for msg in channel
                push!(messages, msg)
            end

            # Should have 4 messages (1 + 2 + 1)
            @test length(messages) == 4

            # First tick
            @test messages[1].tick_idx == Int32(1)
            @test messages[1].raw_price == Int32(41971)
            @test messages[1].price_delta == Int32(0)

            # Second tick (from volume expansion, first replica)
            @test messages[2].tick_idx == Int32(2)
            @test messages[2].raw_price == Int32(41972)
            @test messages[2].price_delta == Int32(1)  # 41972 - 41971

            # Third tick (from volume expansion, second replica)
            @test messages[3].tick_idx == Int32(3)
            @test messages[3].raw_price == Int32(41972)  # Same price
            @test messages[3].price_delta == Int32(0)  # 41972 - 41972 = 0

            # Fourth tick
            @test messages[4].tick_idx == Int32(4)
            @test messages[4].raw_price == Int32(41973)
            @test messages[4].price_delta == Int32(1)  # 41973 - 41972

        finally
            rm(test_file, force=true)
        end
    end

    @testset begin #BroadcastMessage Fields Populated
        # Verify all required fields are populated by VolumeExpansion
        test_file = "test_fields.txt"
        open(test_file, "w") do f
            println(f, "20250319 070000 0520000;41971;41970;41971;1")
        end

        try
            channel = stream_expanded_ticks(test_file, 0.0)
            msg = take!(channel)

            # Fields populated by VolumeExpansion
            @test msg.tick_idx == Int32(1)
            @test msg.timestamp != Int64(0)  # Encoded timestamp
            @test msg.raw_price == Int32(41971)
            @test msg.price_delta == Int32(0)

            # Placeholder fields (for TickHotLoopF32)
            @test msg.normalization == Float32(1.0)
            @test msg.complex_signal == ComplexF32(0, 0)
            @test msg.status_flag == FLAG_OK

            # Close channel to release file handle
            close(channel)
        finally
            sleep(0.1)  # Allow file handles to close on Windows
            rm(test_file, force=true)
        end
    end

    @testset begin #Timestamp Encoding in Messages
        test_file = "test_timestamp.txt"
        open(test_file, "w") do f
            println(f, "20250319 070000 0520000;41971;41970;41971;1")
        end

        try
            channel = stream_expanded_ticks(test_file, 0.0)
            msg = take!(channel)

            # Verify timestamp is encoded
            @test typeof(msg.timestamp) == Int64
            @test msg.timestamp != Int64(0)

            # Verify round-trip
            decoded = decode_timestamp_from_int64(msg.timestamp)
            @test decoded == "20250319"  # First 8 chars

            # Close channel to release file handle
            close(channel)
        finally
            sleep(0.1)  # Allow file handles to close on Windows
            rm(test_file, force=true)
        end
    end

    @testset begin #Empty Lines and Malformed Records
        test_file = "test_malformed.txt"
        open(test_file, "w") do f
            println(f, "20250319 070000 0520000;41971;41970;41971;1")
            println(f, "")  # Empty line
            println(f, "malformed;data")  # Malformed
            println(f, "20250319 070001 0520000;41972;41971;41972;1")
        end

        try
            messages = BroadcastMessage[]
            channel = stream_expanded_ticks(test_file, 0.0)

            for msg in channel
                push!(messages, msg)
            end

            # Should skip empty and malformed, keep only 2 valid
            @test length(messages) == 2
            @test messages[1].raw_price == Int32(41971)
            @test messages[2].raw_price == Int32(41972)

        finally
            rm(test_file, force=true)
        end
    end

    @testset begin #Price Delta Calculation
        test_file = "test_delta.txt"
        open(test_file, "w") do f
            println(f, "20250319 070000 0520000;41970;41969;41970;1")
            println(f, "20250319 070001 0520000;41975;41974;41975;1")  # +5
            println(f, "20250319 070002 0520000;41972;41971;41972;1")  # -3
            println(f, "20250319 070003 0520000;41972;41971;41972;1")  # 0
        end

        try
            messages = BroadcastMessage[]
            channel = stream_expanded_ticks(test_file, 0.0)

            for msg in channel
                push!(messages, msg)
            end

            @test messages[1].price_delta == Int32(0)   # First tick
            @test messages[2].price_delta == Int32(5)   # 41975 - 41970
            @test messages[3].price_delta == Int32(-3)  # 41972 - 41975
            @test messages[4].price_delta == Int32(0)   # 41972 - 41972

        finally
            rm(test_file, force=true)
        end
    end

    @testset begin #GPU Type Compatibility
        test_file = "test_gpu_types.txt"
        open(test_file, "w") do f
            println(f, "20250319 070000 0520000;41971;41970;41971;1")
        end

        try
            channel = stream_expanded_ticks(test_file, 0.0)
            msg = take!(channel)

            # Verify GPU-compatible types
            @test typeof(msg.tick_idx) == Int32
            @test typeof(msg.timestamp) == Int64
            @test typeof(msg.raw_price) == Int32
            @test typeof(msg.price_delta) == Int32

            # Close channel to release file handle
            close(channel)
        finally
            sleep(0.1)  # Allow file handles to close on Windows
            rm(test_file, force=true)
        end
    end
end

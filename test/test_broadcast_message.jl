using Test
using TickDataPipeline

@testset begin #BroadcastMessage
    @testset begin #Creation
        msg = create_broadcast_message(
            Int32(1),
            Int64(12345),
            Int32(41971),
            Int32(10)
        )

        @test msg.tick_idx == Int32(1)
        @test msg.timestamp == Int64(12345)
        @test msg.raw_price == Int32(41971)
        @test msg.price_delta == Int32(10)
        @test msg.normalization == Float32(1.0)
        @test msg.complex_signal == ComplexF32(0, 0)
        @test msg.status_flag == FLAG_OK
    end

    @testset begin #In-place Update
        msg = create_broadcast_message(Int32(1), Int64(1), Int32(100), Int32(0))

        update_broadcast_message!(
            msg,
            ComplexF32(0.707, 0.707),
            Float32(2.5),
            FLAG_CLIPPED
        )

        @test msg.complex_signal == ComplexF32(Float32(0.707), Float32(0.707))
        @test msg.normalization == Float32(2.5)
        @test msg.status_flag == FLAG_CLIPPED
    end

    @testset begin #Mutability
        msg = create_broadcast_message(Int32(1), Int64(1), Int32(100), Int32(0))

        # Verify struct is mutable
        @test ismutable(msg)

        # Test direct field mutation
        msg.status_flag = FLAG_HOLDLAST
        @test msg.status_flag == FLAG_HOLDLAST

        msg.normalization = Float32(3.14)
        @test msg.normalization == Float32(3.14)
    end

    @testset begin #GPU Compatibility
        # Verify all fields are primitive types
        msg = create_broadcast_message(Int32(1), Int64(1), Int32(100), Int32(0))

        @test isbitstype(typeof(msg.tick_idx))
        @test isbitstype(typeof(msg.timestamp))
        @test isbitstype(typeof(msg.raw_price))
        @test isbitstype(typeof(msg.price_delta))
        @test isbitstype(typeof(msg.normalization))
        @test isbitstype(typeof(msg.complex_signal))
        @test isbitstype(typeof(msg.status_flag))

        # Verify types are GPU-compatible
        @test typeof(msg.tick_idx) == Int32
        @test typeof(msg.timestamp) == Int64
        @test typeof(msg.raw_price) == Int32
        @test typeof(msg.price_delta) == Int32
        @test typeof(msg.normalization) == Float32
        @test typeof(msg.complex_signal) == ComplexF32
        @test typeof(msg.status_flag) == UInt8
    end

    @testset begin #Status Flags
        # Test flag constants
        @test FLAG_OK == UInt8(0x00)
        @test FLAG_MALFORMED == UInt8(0x01)
        @test FLAG_HOLDLAST == UInt8(0x02)
        @test FLAG_CLIPPED == UInt8(0x04)
        @test FLAG_AGC_LIMIT == UInt8(0x08)

        # Test flag combinations (bitwise OR)
        combined = FLAG_CLIPPED | FLAG_AGC_LIMIT
        @test combined == UInt8(0x0C)

        # Test flag checking (bitwise AND)
        @test (combined & FLAG_CLIPPED) != UInt8(0)
        @test (combined & FLAG_AGC_LIMIT) != UInt8(0)
        @test (combined & FLAG_MALFORMED) == UInt8(0)
    end
end

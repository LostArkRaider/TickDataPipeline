using Test
using TickDataPipeline

@testset begin #TripleSplitSystem
    @testset begin #Manager Creation
        manager = create_triple_split_manager()
        @test manager isa TripleSplitManager
        @test length(manager.consumers) == 0
        @test manager.total_broadcasts == Int32(0)
        @test manager.successful_broadcasts == Int32(0)
    end

    @testset begin #Consumer Subscription
        manager = create_triple_split_manager()

        consumer = subscribe_consumer!(manager, "test1", PRIORITY, Int32(512))
        @test consumer.consumer_id == "test1"
        @test consumer.consumer_type == PRIORITY
        @test consumer.buffer_size == Int32(512)
        @test length(manager.consumers) == 1
    end

    @testset begin #Duplicate Consumer
        manager = create_triple_split_manager()
        subscribe_consumer!(manager, "test1", PRIORITY)

        # Should error on duplicate
        @test_throws ErrorException subscribe_consumer!(manager, "test1", MONITORING)
    end

    @testset begin #Consumer Unsubscription
        manager = create_triple_split_manager()
        subscribe_consumer!(manager, "test1", PRIORITY)

        result = unsubscribe_consumer!(manager, "test1")
        @test result == true
        @test length(manager.consumers) == 0

        # Unsubscribe non-existent
        result = unsubscribe_consumer!(manager, "nonexistent")
        @test result == false
    end

    @testset begin #Broadcast To No Consumers
        manager = create_triple_split_manager()
        msg = create_broadcast_message(Int32(1), Int64(1), Int32(41971), Int32(0))

        (total, successful, dropped) = broadcast_to_all!(manager, msg)
        @test total == Int32(0)
        @test successful == Int32(0)
        @test dropped == Int32(0)
    end

    @testset begin #Broadcast To Single Consumer
        manager = create_triple_split_manager()
        consumer = subscribe_consumer!(manager, "test1", PRIORITY)

        msg = create_broadcast_message(Int32(1), Int64(1), Int32(41971), Int32(10))
        (total, successful, dropped) = broadcast_to_all!(manager, msg)

        @test total == Int32(1)
        @test successful == Int32(1)
        @test dropped == Int32(0)

        # Verify message in channel
        received = take!(consumer.channel)
        @test received.tick_idx == Int32(1)
        @test received.raw_price == Int32(41971)
    end

    @testset begin #Broadcast To Multiple Consumers
        manager = create_triple_split_manager()
        c1 = subscribe_consumer!(manager, "priority", PRIORITY)
        c2 = subscribe_consumer!(manager, "monitoring", MONITORING)
        c3 = subscribe_consumer!(manager, "analytics", ANALYTICS)

        msg = create_broadcast_message(Int32(1), Int64(1), Int32(41971), Int32(10))
        (total, successful, dropped) = broadcast_to_all!(manager, msg)

        @test total == Int32(3)
        @test successful == Int32(3)
        @test dropped == Int32(0)

        # All should receive
        @test isready(c1.channel)
        @test isready(c2.channel)
        @test isready(c3.channel)
    end

    @testset begin #Priority Consumer Handling
        manager = create_triple_split_manager()
        consumer = subscribe_consumer!(manager, "priority", PRIORITY, Int32(10))

        # Send messages
        for i in 1:5
            msg = create_broadcast_message(Int32(i), Int64(i), Int32(41971), Int32(0))
            (_, successful, _) = broadcast_to_all!(manager, msg)
            @test successful == Int32(1)
        end

        # Verify all received
        @test consumer.channel.n_avail_items == 5
    end

    @testset begin #Non-Priority Drops On Full
        manager = create_triple_split_manager()
        consumer = subscribe_consumer!(manager, "monitoring", MONITORING, Int32(2))

        # Fill channel
        for i in 1:2
            msg = create_broadcast_message(Int32(i), Int64(i), Int32(41971), Int32(0))
            broadcast_to_all!(manager, msg)
        end

        # Next message should drop
        msg = create_broadcast_message(Int32(3), Int64(3), Int32(41971), Int32(0))
        (_, successful, dropped) = broadcast_to_all!(manager, msg)
        @test dropped == Int32(1)
    end

    @testset begin #Consumer Stats
        manager = create_triple_split_manager()
        consumer = subscribe_consumer!(manager, "test1", PRIORITY)

        # Send messages
        for i in 1:5
            msg = create_broadcast_message(Int32(i), Int64(i), Int32(41971), Int32(0))
            broadcast_to_all!(manager, msg)
        end

        stats = get_consumer_stats(consumer)
        @test stats.consumer_id == "test1"
        @test stats.consumer_type == PRIORITY
        @test stats.messages_sent == Int32(5)
        @test stats.messages_dropped == Int32(0)
    end

    @testset begin #Manager Stats
        manager = create_triple_split_manager()
        subscribe_consumer!(manager, "test1", PRIORITY)
        subscribe_consumer!(manager, "test2", MONITORING)

        # Send messages
        for i in 1:10
            msg = create_broadcast_message(Int32(i), Int64(i), Int32(41971), Int32(0))
            broadcast_to_all!(manager, msg)
        end

        stats = get_manager_stats(manager)
        @test stats.total_broadcasts == Int32(10)
        @test stats.successful_broadcasts == Int32(10)
        @test stats.consumer_count == Int32(2)
    end

    @testset begin #Thread Safety
        manager = create_triple_split_manager()
        consumer = subscribe_consumer!(manager, "test1", PRIORITY, Int32(1000))

        # Concurrent broadcasts
        tasks = Task[]
        for i in 1:10
            task = @async begin
                msg = create_broadcast_message(Int32(i), Int64(i), Int32(41971), Int32(0))
                broadcast_to_all!(manager, msg)
            end
            push!(tasks, task)
        end

        # Wait for all
        for task in tasks
            wait(task)
        end

        # Should have broadcast all
        stats = get_manager_stats(manager)
        @test stats.total_broadcasts == Int32(10)
    end
end

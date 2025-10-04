# src/TripleSplitSystem.jl - Multi-Consumer Channel Broadcasting
# Design Specification v2.4 Implementation
# Thread-safe broadcasting to multiple consumers with priority handling

# Note: Using parent module's BroadcastMessage
# This module is included in TickDataPipeline

"""
ConsumerType - Type of consumer for priority handling

Priority levels:
- PRIORITY: Always successful, blocking if needed (critical path)
- MONITORING: Non-blocking, drop on overflow (monitoring/alerting)
- ANALYTICS: Non-blocking, drop on overflow (offline analytics)
"""
@enum ConsumerType::Int32 begin
    PRIORITY = Int32(1)
    MONITORING = Int32(2)
    ANALYTICS = Int32(3)
end

"""
ConsumerChannel - Thread-safe consumer channel wrapper

Wraps a Channel{BroadcastMessage} with statistics and thread safety.

# Fields
- `consumer_id::String`: Unique consumer identifier
- `consumer_type::ConsumerType`: Consumer priority type
- `channel::Channel{BroadcastMessage}`: Message channel
- `buffer_size::Int32`: Channel buffer size
- `messages_sent::Int32`: Successful messages sent
- `messages_dropped::Int32`: Messages dropped due to overflow
- `lock::ReentrantLock`: Thread safety lock
"""
mutable struct ConsumerChannel
    consumer_id::String
    consumer_type::ConsumerType
    channel::Channel{BroadcastMessage}
    buffer_size::Int32
    messages_sent::Int32
    messages_dropped::Int32
    lock::ReentrantLock

    function ConsumerChannel(consumer_id::String, consumer_type::ConsumerType, buffer_size::Int32 = Int32(1024))
        new(
            consumer_id,
            consumer_type,
            Channel{BroadcastMessage}(buffer_size),
            buffer_size,
            Int32(0),
            Int32(0),
            ReentrantLock()
        )
    end
end

"""
TripleSplitManager - Multi-consumer broadcasting manager

Manages multiple consumers with priority-based delivery.

# Fields
- `consumers::Vector{ConsumerChannel}`: Active consumers
- `lock::ReentrantLock`: Thread safety for manager operations
- `total_broadcasts::Int32`: Total broadcast operations
- `successful_broadcasts::Int32`: Fully successful broadcasts
"""
mutable struct TripleSplitManager
    consumers::Vector{ConsumerChannel}
    lock::ReentrantLock
    total_broadcasts::Int32
    successful_broadcasts::Int32

    function TripleSplitManager()
        new(ConsumerChannel[], ReentrantLock(), Int32(0), Int32(0))
    end
end

"""
    create_triple_split_manager()::TripleSplitManager

Create new TripleSplitManager instance.

# Returns
- `TripleSplitManager`: New manager instance
"""
function create_triple_split_manager()::TripleSplitManager
    return TripleSplitManager()
end

"""
    subscribe_consumer!(manager, consumer_id, consumer_type, buffer_size)::ConsumerChannel

Subscribe new consumer to receive broadcasts.

# Arguments
- `manager::TripleSplitManager`: Manager instance
- `consumer_id::String`: Unique consumer ID
- `consumer_type::ConsumerType`: Consumer priority type
- `buffer_size::Int32`: Channel buffer size (default: 1024)

# Returns
- `ConsumerChannel`: Created consumer channel

# Errors
- Throws if consumer_id already exists
"""
function subscribe_consumer!(
    manager::TripleSplitManager,
    consumer_id::String,
    consumer_type::ConsumerType,
    buffer_size::Int32 = Int32(1024)
)::ConsumerChannel
    lock(manager.lock) do
        # Check for duplicate
        for consumer in manager.consumers
            if consumer.consumer_id == consumer_id
                error("Consumer already subscribed: $consumer_id")
            end
        end

        # Create and add consumer
        consumer = ConsumerChannel(consumer_id, consumer_type, buffer_size)
        push!(manager.consumers, consumer)
        return consumer
    end
end

"""
    unsubscribe_consumer!(manager, consumer_id)::Bool

Unsubscribe consumer from broadcasts.

# Arguments
- `manager::TripleSplitManager`: Manager instance
- `consumer_id::String`: Consumer ID to remove

# Returns
- `Bool`: true if removed, false if not found
"""
function unsubscribe_consumer!(manager::TripleSplitManager, consumer_id::String)::Bool
    lock(manager.lock) do
        idx = findfirst(c -> c.consumer_id == consumer_id, manager.consumers)
        if idx === nothing
            return false
        end

        # Close channel and remove
        close(manager.consumers[idx].channel)
        deleteat!(manager.consumers, idx)
        return true
    end
end

"""
    broadcast_to_all!(manager, message)::Tuple{Int32, Int32, Int32}

Broadcast message to all subscribed consumers.

Priority handling:
- PRIORITY consumers: Blocking put! (always succeeds)
- MONITORING/ANALYTICS: Non-blocking, drop on full channel

# Arguments
- `manager::TripleSplitManager`: Manager instance
- `message::BroadcastMessage`: Message to broadcast

# Returns
- `Tuple{Int32, Int32, Int32}`: (total_consumers, successful, dropped)
"""
function broadcast_to_all!(
    manager::TripleSplitManager,
    message::BroadcastMessage
)::Tuple{Int32, Int32, Int32}
    # Snapshot consumers (minimize lock time)
    consumers_snapshot = lock(manager.lock) do
        copy(manager.consumers)
    end

    total_consumers = Int32(length(consumers_snapshot))
    successful = Int32(0)
    dropped = Int32(0)

    if total_consumers == Int32(0)
        return (total_consumers, successful, dropped)
    end

    # Deliver to each consumer
    for consumer in consumers_snapshot
        if deliver_to_consumer!(consumer, message)
            successful += Int32(1)
        else
            dropped += Int32(1)
        end
    end

    # Update manager stats
    lock(manager.lock) do
        manager.total_broadcasts += Int32(1)
        if dropped == Int32(0)
            manager.successful_broadcasts += Int32(1)
        end
    end

    return (total_consumers, successful, dropped)
end

"""
    deliver_to_consumer!(consumer, message)::Bool

Deliver message to single consumer with priority handling.

# Arguments
- `consumer::ConsumerChannel`: Target consumer
- `message::BroadcastMessage`: Message to deliver

# Returns
- `Bool`: true if delivered, false if dropped
"""
function deliver_to_consumer!(
    consumer::ConsumerChannel,
    message::BroadcastMessage
)::Bool
    # Check if channel closed
    if consumer.channel.state == :closed
        return false
    end

    lock(consumer.lock) do
        if consumer.consumer_type == PRIORITY
            # Priority consumer: blocking put (always succeeds)
            try
                put!(consumer.channel, message)
                consumer.messages_sent += Int32(1)
                return true
            catch
                consumer.messages_dropped += Int32(1)
                return false
            end
        else
            # Non-priority: check space first, drop if full
            if consumer.channel.n_avail_items < consumer.buffer_size
                try
                    put!(consumer.channel, message)
                    consumer.messages_sent += Int32(1)
                    return true
                catch
                    consumer.messages_dropped += Int32(1)
                    return false
                end
            else
                # Channel full, drop message
                consumer.messages_dropped += Int32(1)
                return false
            end
        end
    end
end

"""
    get_consumer_stats(consumer)::NamedTuple

Get statistics for a consumer channel.

# Arguments
- `consumer::ConsumerChannel`: Consumer to query

# Returns
- `NamedTuple`: Statistics (messages_sent, messages_dropped, fill_ratio)
"""
function get_consumer_stats(consumer::ConsumerChannel)::NamedTuple
    lock(consumer.lock) do
        fill_ratio = Float32(consumer.channel.n_avail_items) / Float32(consumer.buffer_size)
        return (
            consumer_id = consumer.consumer_id,
            consumer_type = consumer.consumer_type,
            messages_sent = consumer.messages_sent,
            messages_dropped = consumer.messages_dropped,
            fill_ratio = fill_ratio,
            buffer_size = consumer.buffer_size
        )
    end
end

"""
    get_manager_stats(manager)::NamedTuple

Get overall manager statistics.

# Arguments
- `manager::TripleSplitManager`: Manager to query

# Returns
- `NamedTuple`: Statistics (total_broadcasts, successful_broadcasts, consumer_count)
"""
function get_manager_stats(manager::TripleSplitManager)::NamedTuple
    lock(manager.lock) do
        return (
            total_broadcasts = manager.total_broadcasts,
            successful_broadcasts = manager.successful_broadcasts,
            consumer_count = Int32(length(manager.consumers))
        )
    end
end

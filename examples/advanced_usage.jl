# Advanced Usage Example - TickDataPipeline.jl
# Demonstrates async processing, callbacks, and lifecycle control

using TickDataPipeline

# ============================================================================
# Example 1: Async Pipeline with Completion Callback
# ============================================================================

println("=" ^ 70)
println("Example 1: Async Pipeline with Callbacks")
println("=" ^ 70)

# Create test data file
test_file = "examples/test_async.txt"
open(test_file, "w") do f
    for i in 1:20
        price = 41970 + i
        println(f, "20250319 070000 0520000;$price;$price;$price;1")
    end
end

try
    config = PipelineConfig(
        tick_file_path = test_file,
        flow_control = FlowControlConfig(delay_ms = 10.0)  # 10ms between ticks
    )
    split_mgr = create_triple_split_manager()
    subscribe_consumer!(split_mgr, "async_consumer", PRIORITY, Int32(100))

    pipeline_mgr = create_pipeline_manager(config, split_mgr)

    # Set completion callback
    completion_received = Ref(false)
    pipeline_mgr.completion_callback = function(tick_count)
        println("\n✓ Pipeline completed: $tick_count ticks processed")
        completion_received[] = true
    end

    # Start pipeline in background task
    println("Starting async pipeline...")
    task = @async run_pipeline!(pipeline_mgr, max_ticks = Int64(20))

    # Simulate doing other work while pipeline runs
    println("Pipeline running in background...")
    sleep(0.1)
    println("Doing other work...")
    sleep(0.1)

    # Wait for completion
    wait(task)

    @assert completion_received[] "Completion callback not received!"
    println("✓ Async execution successful")

finally
    sleep(0.1)
    rm(test_file, force=true)
end

# ============================================================================
# Example 2: Real-time Message Processing with Consumer Task
# ============================================================================

println("\n" * "=" ^ 70)
println("Example 2: Real-time Message Consumer")
println("=" ^ 70)

test_file = "examples/test_realtime.txt"
open(test_file, "w") do f
    for i in 1:50
        price = 41970 + (i % 20)  # Some price variation
        println(f, "20250319 070000 0520000;$price;$price;$price;1")
    end
end

try
    config = PipelineConfig(
        tick_file_path = test_file,
        flow_control = FlowControlConfig(delay_ms = 5.0)
    )
    split_mgr = create_triple_split_manager()
    consumer = subscribe_consumer!(split_mgr, "realtime", PRIORITY, Int32(200))

    # Create consumer task that processes messages in real-time
    messages_processed = Ref(Int32(0))
    price_sum = Ref(Int64(0))

    consumer_task = @async begin
        for msg in consumer.channel
            messages_processed[] += Int32(1)
            price_sum[] += Int64(msg.raw_price)

            # Print every 10th message
            if messages_processed[] % Int32(10) == Int32(0)
                avg_price = Float32(price_sum[]) / Float32(messages_processed[])
                println("  Processed $(messages_processed[]) messages, " *
                        "avg price: $(round(avg_price, digits=2))")
            end
        end
    end

    # Start pipeline
    pipeline_mgr = create_pipeline_manager(config, split_mgr)
    println("Starting pipeline with real-time consumer...")

    pipeline_task = @async run_pipeline!(pipeline_mgr, max_ticks = Int64(50))

    # Wait for both tasks
    wait(pipeline_task)
    sleep(0.1)  # Give consumer task time to process remaining messages

    println("\n✓ Real-time processing complete")
    println("  Final message count: $(messages_processed[])")

finally
    sleep(0.1)
    rm(test_file, force=true)
end

# ============================================================================
# Example 3: Graceful Pipeline Shutdown
# ============================================================================

println("\n" * "=" ^ 70)
println("Example 3: Graceful Shutdown")
println("=" ^ 70)

test_file = "examples/test_shutdown.txt"
open(test_file, "w") do f
    for i in 1:1000  # Large file
        price = 41970 + (i % 50)
        println(f, "20250319 070000 0520000;$price;$price;$price;1")
    end
end

try
    config = PipelineConfig(
        tick_file_path = test_file,
        flow_control = FlowControlConfig(delay_ms = 2.0)
    )
    split_mgr = create_triple_split_manager()
    subscribe_consumer!(split_mgr, "shutdown_test", PRIORITY, Int32(2000))

    pipeline_mgr = create_pipeline_manager(config, split_mgr)

    # Start pipeline
    println("Starting pipeline (will be stopped early)...")
    pipeline_task = @async run_pipeline!(pipeline_mgr, max_ticks = Int64(1000))

    # Let it run for a bit
    sleep(0.2)

    # Stop pipeline gracefully
    println("Requesting pipeline stop...")
    stop_pipeline!(pipeline_mgr)

    # Wait for shutdown
    wait(pipeline_task)

    stats = (
        ticks_processed = pipeline_mgr.metrics.ticks_processed,
        broadcasts_sent = pipeline_mgr.metrics.broadcasts_sent
    )

    println("\n✓ Pipeline stopped gracefully")
    println("  Ticks processed before stop: $(stats.ticks_processed)")
    println("  (Would have processed 1000)")

finally
    sleep(0.5)  # Longer sleep for Windows file locking
    rm(test_file, force=true)
end

# ============================================================================
# Example 4: Per-Tick Metrics Analysis
# ============================================================================

println("\n" * "=" ^ 70)
println("Example 4: Per-Tick Metrics Analysis")
println("=" ^ 70)

test_file = "examples/test_metrics.txt"
open(test_file, "w") do f
    for i in 1:100
        price = 41970 + (i % 30)
        println(f, "20250319 070000 0520000;$price;$price;$price;1")
    end
end

try
    config = PipelineConfig(
        tick_file_path = test_file,
        flow_control = FlowControlConfig(delay_ms = 0.0)
    )
    split_mgr = create_triple_split_manager()
    consumer = subscribe_consumer!(split_mgr, "metrics", PRIORITY, Int32(200))

    pipeline_mgr = create_pipeline_manager(config, split_mgr)

    # Track per-tick metrics
    latencies = Int32[]

    # Custom processing loop
    println("Processing with per-tick metrics collection...")

    tick_channel = stream_expanded_ticks(test_file, 0.0)
    for msg in tick_channel
        if pipeline_mgr.metrics.ticks_processed >= Int64(100)
            break
        end

        # Process single tick and capture metrics
        result = process_single_tick_through_pipeline!(pipeline_mgr, msg)

        # Collect latency
        push!(latencies, result.total_latency_us)

        # Update counts
        pipeline_mgr.metrics.ticks_processed += Int64(1)
        if result.success
            pipeline_mgr.metrics.broadcasts_sent += Int32(1)
        end
    end

    # Analyze latencies
    println("\nLatency Analysis:")
    println("  Min: $(minimum(latencies))μs")
    println("  Max: $(maximum(latencies))μs")
    println("  Mean: $(round(sum(latencies) / length(latencies), digits=2))μs")

    # Calculate percentiles
    sorted = sort(latencies)
    p50 = sorted[div(length(sorted), 2)]
    p95 = sorted[div(95 * length(sorted), 100)]
    p99 = sorted[div(99 * length(sorted), 100)]

    println("  P50: $(p50)μs")
    println("  P95: $(p95)μs")
    println("  P99: $(p99)μs")

finally
    sleep(0.1)
    rm(test_file, force=true)
end

# ============================================================================
# Example 5: Multiple Pipelines Running Concurrently
# ============================================================================

println("\n" * "=" ^ 70)
println("Example 5: Concurrent Pipelines")
println("=" ^ 70)

# Create two test files
test_file1 = "examples/test_concurrent1.txt"
test_file2 = "examples/test_concurrent2.txt"

open(test_file1, "w") do f
    for i in 1:30
        println(f, "20250319 070000 0520000;41970;41970;41970;1")
    end
end

open(test_file2, "w") do f
    for i in 1:30
        println(f, "20250319 070000 0520000;41980;41980;41980;1")
    end
end

try
    # Pipeline 1
    config1 = PipelineConfig(tick_file_path = test_file1,
                            flow_control = FlowControlConfig(delay_ms = 5.0))
    split_mgr1 = create_triple_split_manager()
    subscribe_consumer!(split_mgr1, "pipeline1", PRIORITY, Int32(100))
    pipeline_mgr1 = create_pipeline_manager(config1, split_mgr1)
    pipeline_mgr1.completion_callback = (n) -> println("  Pipeline 1 complete: $n ticks")

    # Pipeline 2
    config2 = PipelineConfig(tick_file_path = test_file2,
                            flow_control = FlowControlConfig(delay_ms = 5.0))
    split_mgr2 = create_triple_split_manager()
    subscribe_consumer!(split_mgr2, "pipeline2", PRIORITY, Int32(100))
    pipeline_mgr2 = create_pipeline_manager(config2, split_mgr2)
    pipeline_mgr2.completion_callback = (n) -> println("  Pipeline 2 complete: $n ticks")

    # Start both pipelines
    println("Starting two pipelines concurrently...")
    task1 = @async run_pipeline!(pipeline_mgr1, max_ticks = Int64(30))
    task2 = @async run_pipeline!(pipeline_mgr2, max_ticks = Int64(30))

    # Wait for both
    wait(task1)
    wait(task2)

    println("\n✓ Both pipelines completed successfully")

finally
    sleep(0.1)
    rm(test_file1, force=true)
    rm(test_file2, force=true)
end

println("\n" * "=" ^ 70)
println("Advanced examples completed successfully!")
println("=" ^ 70)

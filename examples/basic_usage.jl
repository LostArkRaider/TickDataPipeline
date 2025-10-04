# Basic Usage Example - TickDataPipeline.jl
# Demonstrates simple pipeline setup and execution

using TickDataPipeline

# ============================================================================
# Example 1: Simple Pipeline with Default Configuration
# ============================================================================

println("=" ^ 70)
println("Example 1: Simple Pipeline")
println("=" ^ 70)

# Create default configuration
config = create_default_config()

# Create broadcasting manager
split_mgr = create_triple_split_manager()

# Subscribe a priority consumer
consumer = subscribe_consumer!(split_mgr, "my_consumer", PRIORITY, Int32(1000))

# Run pipeline (simple interface)
# Note: This example assumes you have a tick data file
# If file doesn't exist, it will show a warning
stats = run_pipeline(config, split_mgr, max_ticks = Int64(100))

println("\nPipeline Statistics:")
println("  Ticks processed: $(stats.ticks_processed)")
println("  Broadcasts sent: $(stats.broadcasts_sent)")
println("  Errors: $(stats.errors)")

# Retrieve messages from consumer
println("\nRetrieving messages...")
let message_count = Int32(0)
    while consumer.channel.n_avail_items > 0
        msg = take!(consumer.channel)
        message_count += Int32(1)

        # Print first few messages
        if message_count <= 5
            println("  Tick $(msg.tick_idx): price=$(msg.raw_price), " *
                    "delta=$(msg.price_delta), signal=$(msg.complex_signal)")
        end
    end
    println("  Retrieved $message_count messages")
end

# ============================================================================
# Example 2: Pipeline with Custom Configuration
# ============================================================================

println("\n" * "=" ^ 70)
println("Example 2: Custom Configuration")
println("=" ^ 70)

# Create custom configuration
custom_config = PipelineConfig(
    tick_file_path = "data/raw/YM 06-25.Last.txt",
    signal_processing = SignalProcessingConfig(
        agc_alpha = Float32(0.125),          # Faster AGC
        agc_min_scale = Int32(2),
        agc_max_scale = Int32(100),
        winsorize_threshold = Float32(2.5),   # Tighter clipping
        min_price = Int32(40000),
        max_price = Int32(43000),
        max_jump = Int32(25)                  # Smaller max jump
    ),
    flow_control = FlowControlConfig(delay_ms = 0.0),
    channels = ChannelConfig(
        priority_buffer_size = Int32(2048),
        standard_buffer_size = Int32(1024)
    ),
    performance = PerformanceConfig(
        target_latency_us = Int32(250),       # Tighter target
        max_latency_us = Int32(500),
        target_throughput_tps = Float32(20000.0)
    ),
    pipeline_name = "custom_example",
    description = "Example with custom parameters"
)

# Validate configuration
is_valid, errors = validate_config(custom_config)
if is_valid
    println("✓ Configuration valid")
else
    println("✗ Configuration errors:")
    for error in errors
        println("  - $error")
    end
end

# ============================================================================
# Example 3: Multiple Consumers with Different Types
# ============================================================================

println("\n" * "=" ^ 70)
println("Example 3: Multiple Consumer Types")
println("=" ^ 70)

config = create_default_config()
split_mgr = create_triple_split_manager()

# Subscribe different consumer types
priority_consumer = subscribe_consumer!(split_mgr, "priority", PRIORITY, Int32(500))
monitoring_consumer = subscribe_consumer!(split_mgr, "monitoring", MONITORING, Int32(500))
analytics_consumer = subscribe_consumer!(split_mgr, "analytics", ANALYTICS, Int32(500))

println("Subscribed consumers:")
println("  - priority (PRIORITY)")
println("  - monitoring (MONITORING)")
println("  - analytics (ANALYTICS)")

# Run pipeline
stats = run_pipeline(config, split_mgr, max_ticks = Int64(50))

println("\nConsumer statistics:")
println("  Priority: $(priority_consumer.messages_sent) sent, " *
        "$(priority_consumer.messages_dropped) dropped")
println("  Monitoring: $(monitoring_consumer.messages_sent) sent, " *
        "$(monitoring_consumer.messages_dropped) dropped")
println("  Analytics: $(analytics_consumer.messages_sent) sent, " *
        "$(analytics_consumer.messages_dropped) dropped")

# ============================================================================
# Example 4: Using PipelineManager for Enhanced Metrics
# ============================================================================

println("\n" * "=" ^ 70)
println("Example 4: Enhanced Metrics with PipelineManager")
println("=" ^ 70)

config = create_default_config()
split_mgr = create_triple_split_manager()
subscribe_consumer!(split_mgr, "consumer1", PRIORITY, Int32(1000))

# Create pipeline manager
pipeline_mgr = create_pipeline_manager(config, split_mgr)

# Run with enhanced metrics
stats = run_pipeline!(pipeline_mgr, max_ticks = Int64(100))

println("\nEnhanced Statistics:")
println("  Ticks processed: $(stats.ticks_processed)")
println("  Broadcasts sent: $(stats.broadcasts_sent)")
println("  Errors: $(stats.errors)")
println("  Average latency: $(round(stats.avg_latency_us, digits=2))μs")
println("  Min latency: $(stats.min_latency_us)μs")
println("  Max latency: $(stats.max_latency_us)μs")
println("  Avg signal processing: $(round(stats.avg_signal_time_us, digits=2))μs")
println("  Avg broadcast time: $(round(stats.avg_broadcast_time_us, digits=2))μs")

# Performance analysis
if stats.ticks_processed > Int64(0)
    signal_pct = (stats.avg_signal_time_us / stats.avg_latency_us) * Float32(100.0)
    broadcast_pct = (stats.avg_broadcast_time_us / stats.avg_latency_us) * Float32(100.0)

    println("\nTime breakdown:")
    println("  Signal processing: $(round(signal_pct, digits=1))%")
    println("  Broadcasting: $(round(broadcast_pct, digits=1))%")
end

println("\n" * "=" ^ 70)
println("Examples completed successfully!")
println("=" ^ 70)

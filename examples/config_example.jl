# Configuration Example - TickDataPipeline.jl
# Demonstrates TOML configuration loading, saving, and validation

using TickDataPipeline

println("=" ^ 70)
println("Configuration Management Examples")
println("=" ^ 70)

# ============================================================================
# Example 1: Load Default Configuration from TOML
# ============================================================================

println("\nExample 1: Load Default Configuration")
println("-" ^ 70)

# Load the default config from TOML file
config = load_config_from_toml("config/default.toml")

println("Loaded configuration:")
println("  Pipeline name: $(config.pipeline_name)")
println("  Description: $(config.description)")
println("  Tick file: $(config.tick_file_path)")
println("\nSignal Processing:")
println("  AGC alpha: $(config.signal_processing.agc_alpha)")
println("  AGC min scale: $(config.signal_processing.agc_min_scale)")
println("  AGC max scale: $(config.signal_processing.agc_max_scale)")
println("  Winsorize threshold: $(config.signal_processing.winsorize_threshold)σ")
println("  Price range: $(config.signal_processing.min_price) - $(config.signal_processing.max_price)")
println("  Max jump: $(config.signal_processing.max_jump)")
println("\nFlow Control:")
println("  Delay: $(config.flow_control.delay_ms)ms")
println("\nChannels:")
println("  Priority buffer: $(config.channels.priority_buffer_size)")
println("  Standard buffer: $(config.channels.standard_buffer_size)")
println("\nPerformance:")
println("  Target latency: $(config.performance.target_latency_us)μs")
println("  Max latency: $(config.performance.max_latency_us)μs")
println("  Target throughput: $(config.performance.target_throughput_tps) tps")

# ============================================================================
# Example 2: Create and Save Custom Configuration
# ============================================================================

println("\n\nExample 2: Create and Save Custom Configuration")
println("-" ^ 70)

# Create custom configuration
custom_config = PipelineConfig(
    pipeline_name = "high_frequency_trading",
    description = "Ultra-low latency configuration for HFT",
    version = "2.0",
    tick_file_path = "data/raw/ES 06-25.Last.txt",
    signal_processing = SignalProcessingConfig(
        agc_alpha = Float32(0.03125),      # Slower AGC (1/32)
        agc_min_scale = Int32(2),
        agc_max_scale = Int32(200),         # Higher max scale
        winsorize_threshold = Float32(4.0), # Wider threshold
        min_price = Int32(5000),            # ES futures range
        max_price = Int32(6000),
        max_jump = Int32(100)
    ),
    flow_control = FlowControlConfig(delay_ms = 0.0),  # Maximum speed
    channels = ChannelConfig(
        priority_buffer_size = Int32(8192),  # Larger buffers
        standard_buffer_size = Int32(4096)
    ),
    performance = PerformanceConfig(
        target_latency_us = Int32(100),      # Tighter latency
        max_latency_us = Int32(250),
        target_throughput_tps = Float32(50000.0)  # Higher throughput
    )
)

# Save to TOML file
output_path = "examples/custom_hft.toml"
save_config_to_toml(custom_config, output_path)
println("✓ Saved custom configuration to: $output_path")

# Load it back to verify
loaded_config = load_config_from_toml(output_path)
println("✓ Successfully loaded back from TOML")
println("  Pipeline name: $(loaded_config.pipeline_name)")
println("  Target latency: $(loaded_config.performance.target_latency_us)μs")

# Clean up
rm(output_path, force=true)

# ============================================================================
# Example 3: Configuration Validation
# ============================================================================

println("\n\nExample 3: Configuration Validation")
println("-" ^ 70)

# Valid configuration
println("Testing valid configuration...")
valid_config = create_default_config()
is_valid, errors = validate_config(valid_config)

if is_valid
    println("✓ Configuration is valid")
else
    println("✗ Configuration has errors:")
    for error in errors
        println("  - $error")
    end
end

# Invalid configuration - AGC range reversed
println("\nTesting invalid AGC range...")
invalid_agc = PipelineConfig(
    signal_processing = SignalProcessingConfig(
        agc_min_scale = Int32(100),  # Invalid: min > max
        agc_max_scale = Int32(50)
    )
)
is_valid, errors = validate_config(invalid_agc)

if !is_valid
    println("✓ Correctly detected errors:")
    for error in errors
        println("  - $error")
    end
else
    println("✗ Failed to detect invalid configuration!")
end

# Invalid configuration - price range reversed
println("\nTesting invalid price range...")
invalid_price = PipelineConfig(
    signal_processing = SignalProcessingConfig(
        min_price = Int32(50000),  # Invalid: min > max
        max_price = Int32(40000)
    )
)
is_valid, errors = validate_config(invalid_price)

if !is_valid
    println("✓ Correctly detected errors:")
    for error in errors
        println("  - $error")
    end
end

# Invalid configuration - negative delay
println("\nTesting invalid flow control...")
invalid_flow = PipelineConfig(
    flow_control = FlowControlConfig(delay_ms = -1.0)  # Invalid: negative
)
is_valid, errors = validate_config(invalid_flow)

if !is_valid
    println("✓ Correctly detected errors:")
    for error in errors
        println("  - $error")
    end
end

# ============================================================================
# Example 4: Multiple Configurations for Different Instruments
# ============================================================================

println("\n\nExample 4: Instrument-Specific Configurations")
println("-" ^ 70)

# YM (Dow Mini) configuration
ym_config = PipelineConfig(
    pipeline_name = "ym_dow_mini",
    description = "Dow Jones Mini futures",
    tick_file_path = "data/raw/YM 06-25.Last.txt",
    signal_processing = SignalProcessingConfig(
        min_price = Int32(40000),
        max_price = Int32(43000),
        max_jump = Int32(50)
    )
)

# ES (S&P Mini) configuration
es_config = PipelineConfig(
    pipeline_name = "es_sp_mini",
    description = "S&P 500 Mini futures",
    tick_file_path = "data/raw/ES 06-25.Last.txt",
    signal_processing = SignalProcessingConfig(
        min_price = Int32(5000),
        max_price = Int32(6000),
        max_jump = Int32(100)
    )
)

# NQ (Nasdaq Mini) configuration
nq_config = PipelineConfig(
    pipeline_name = "nq_nasdaq_mini",
    description = "Nasdaq 100 Mini futures",
    tick_file_path = "data/raw/NQ 06-25.Last.txt",
    signal_processing = SignalProcessingConfig(
        min_price = Int32(18000),
        max_price = Int32(21000),
        max_jump = Int32(200)
    )
)

# Save all configurations
instruments = [
    ("YM", ym_config),
    ("ES", es_config),
    ("NQ", nq_config)
]

for (name, cfg) in instruments
    path = "examples/config_$(lowercase(name)).toml"
    save_config_to_toml(cfg, path)
    println("✓ Saved $name configuration to: $path")

    # Validate
    is_valid, errors = validate_config(cfg)
    if is_valid
        println("  ✓ Configuration valid")
    else
        println("  ✗ Configuration errors:")
        for error in errors
            println("    - $error")
        end
    end

    # Clean up
    rm(path, force=true)
end

# ============================================================================
# Example 5: Programmatic Configuration from Environment
# ============================================================================

println("\n\nExample 5: Configuration from Environment Variables")
println("-" ^ 70)

# Simulate reading from environment (in practice, use ENV["VARIABLE"])
# For this example, we'll use hardcoded values

function create_config_from_environment()
    # In practice: tick_file = get(ENV, "TICK_FILE_PATH", "data/raw/YM 06-25.Last.txt")
    tick_file = "data/raw/YM 06-25.Last.txt"
    agc_alpha = Float32(0.0625)
    target_latency = Int32(500)
    delay_ms = 0.0

    println("Creating configuration from environment:")
    println("  TICK_FILE_PATH = $tick_file")
    println("  AGC_ALPHA = $agc_alpha")
    println("  TARGET_LATENCY_US = $target_latency")
    println("  FLOW_DELAY_MS = $delay_ms")

    return PipelineConfig(
        pipeline_name = "env_config",
        description = "Configuration from environment variables",
        tick_file_path = tick_file,
        signal_processing = SignalProcessingConfig(
            agc_alpha = agc_alpha
        ),
        flow_control = FlowControlConfig(delay_ms = delay_ms),
        performance = PerformanceConfig(
            target_latency_us = target_latency
        )
    )
end

env_config = create_config_from_environment()
is_valid, errors = validate_config(env_config)

if is_valid
    println("✓ Environment-based configuration is valid")
else
    println("✗ Environment-based configuration has errors:")
    for error in errors
        println("  - $error")
    end
end

println("\n" * "=" ^ 70)
println("Configuration examples completed successfully!")
println("=" ^ 70)

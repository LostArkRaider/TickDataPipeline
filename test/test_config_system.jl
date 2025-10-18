# test_config_system.jl
# Quick test script for new configuration system

using TickDataPipeline

println("="^70)
println("Configuration System Test")
println("="^70)

println("\n1. Testing get_default_config_path()...")
path = get_default_config_path()
println("   Default config path: $path")

println("\n2. Testing load_default_config()...")
println("   (This will create config file if missing)")
config = load_default_config()

println("\n3. Verifying configuration loaded correctly...")
println("   Pipeline name: $(config.pipeline_name)")
println("   Bar processing enabled: $(config.bar_processing.enabled)")
println("   Ticks per bar: $(config.bar_processing.ticks_per_bar)")
println("   Bar method: $(config.bar_processing.bar_method)")
println("   Encoder type: $(config.signal_processing.encoder_type)")

println("\n4. Checking if config file exists...")
if isfile(path)
    println("   ✓ Config file exists at: $path")
    println("   ✓ You can now edit this file to customize settings")
else
    println("   ✗ Config file not found (this shouldn't happen!)")
end

println("\n5. Testing validation...")
is_valid, errors = validate_config(config)
if is_valid
    println("   ✓ Configuration is valid")
else
    println("   ✗ Configuration has errors:")
    for err in errors
        println("     - $err")
    end
end

println("\n" * "="^70)
println("✓ Configuration system test complete!")
println("="^70)
println("\nNext steps:")
println("1. Edit config file at: $path")
println("2. Customize your settings")
println("3. Reload with: config = load_default_config()")
println("="^70)

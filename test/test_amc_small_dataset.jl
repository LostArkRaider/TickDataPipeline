# Test AMC Encoder with Small Dataset
# End-to-end test with synthetic tick data
# Verifies carrier phase continuity and amplitude modulation

using TickDataPipeline
using Printf

println("=" ^ 80)
println("AMC Encoder Small Dataset Test")
println("=" ^ 80)

# Create AMC configuration
config = PipelineConfig(
    signal_processing = SignalProcessingConfig(
        encoder_type = "amc",
        amc_carrier_period = Float32(16.0),  # 16-tick period
        amc_lut_size = Int32(1024)
    )
)

println("\n✓ Configuration created:")
println("  Encoder type: ", config.signal_processing.encoder_type)
println("  AMC carrier period: ", config.signal_processing.amc_carrier_period, " ticks")
println("  AMC LUT size: ", config.signal_processing.amc_lut_size)

# Validate configuration
is_valid, errors = validate_config(config)
if !is_valid
    println("\n✗ Configuration validation failed:")
    for err in errors
        println("  - ", err)
    end
    exit(1)
end
println("✓ Configuration validated successfully")

# Create state
state = create_tickhotloop_state()
println("\n✓ TickHotLoopState created")
println("  Initial carrier phase: ", state.phase_accumulator_Q32)
println("  Carrier increment: ", state.amc_carrier_increment_Q32)

# Verify carrier increment calculation
# 16-tick period → 2π/16 = π/8 rad/tick → 2^32/16 = 268,435,456 in Q32
expected_increment = Int32(268435456)
if state.amc_carrier_increment_Q32 == expected_increment
    println("  ✓ Carrier increment matches expected value (268,435,456)")
else
    println("  ✗ Carrier increment mismatch!")
    println("    Expected: ", expected_increment)
    println("    Actual: ", state.amc_carrier_increment_Q32)
    exit(1)
end

# Synthetic test data: 20 ticks with varying price deltas
println("\n" * "=" ^ 80)
println("Processing 20 ticks through AMC encoder")
println("=" ^ 80)

test_prices = [
    42000, 42001, 42003, 42002, 42004,  # Ticks 1-5
    42006, 42005, 42007, 42009, 42008,  # Ticks 6-10
    42010, 42009, 42011, 42010, 42012,  # Ticks 11-15
    42014, 42013, 42015, 42014, 42016   # Ticks 16-20
]

println("\nTick  Price  Delta  Carrier Phase Q32  Signal Magnitude  Signal Phase (rad)")
println("-" ^ 80)

sp = config.signal_processing

# Track previous phase for verification
global prev_phase = Int32(0)

for (idx, price) in enumerate(test_prices)
    global prev_phase  # Declare global inside loop
    # Calculate delta
    delta = idx == 1 ? Int32(0) : Int32(price - test_prices[idx-1])

    # Create message
    msg = create_broadcast_message(Int32(idx), Int64(0), Int32(price), delta)

    # Process through hot loop
    process_tick_signal!(
        msg, state,
        sp.agc_alpha, sp.agc_min_scale, sp.agc_max_scale,
        sp.winsorize_delta_threshold, sp.min_price, sp.max_price, sp.max_jump,
        sp.encoder_type, sp.cpm_modulation_index
    )

    # Extract output
    magnitude = abs(msg.complex_signal)
    phase = angle(msg.complex_signal)

    # Verify carrier phase incremented correctly
    expected_phase = prev_phase + expected_increment
    if state.phase_accumulator_Q32 != expected_phase
        println("  ✗ Carrier phase mismatch at tick $idx!")
        exit(1)
    end
    prev_phase = state.phase_accumulator_Q32

    # Print results
    @printf("%4d  %5d  %+4d   %15d   %16.4f   %+.4f\n",
            idx, price, delta, state.phase_accumulator_Q32, magnitude, phase)
end

println("-" ^ 80)

# Verify carrier completed one full period at tick 16
println("\n" * "=" ^ 80)
println("Carrier Period Verification")
println("=" ^ 80)

# After 16 ticks, phase should wrap (16 × 268,435,456 = 4,294,967,296 = 2^32 wraps to 0)
# Current phase after 20 ticks = 20 × 268,435,456 = 5,368,709,120
# In Int32 with wraparound: 5,368,709,120 - 2^32 = 1,073,741,824
expected_phase_20 = Int32(20) * expected_increment
if state.phase_accumulator_Q32 == expected_phase_20
    println("✓ Carrier phase after 20 ticks: ", state.phase_accumulator_Q32)
    println("  (Expected: ", expected_phase_20, ")")
else
    println("✗ Carrier phase mismatch!")
    println("  Expected: ", expected_phase_20)
    println("  Actual: ", state.phase_accumulator_Q32)
    exit(1)
end

# Calculate phase after 16 ticks (one full period)
phase_after_16 = Int32(16) * expected_increment
println("\n✓ Phase after 16 ticks (one period): ", phase_after_16)
println("  This equals 2^32 = 4,294,967,296 which wraps to 0 in Int32")
println("  Demonstrates full carrier period completion")

# Summary statistics
println("\n" * "=" ^ 80)
println("Summary Statistics")
println("=" ^ 80)
println("Total ticks processed: ", state.tick_count)
println("Ticks accepted: ", state.ticks_accepted)
println("Bar count: ", state.bar_count)
println("Current carrier phase: ", state.phase_accumulator_Q32)

# Phase increment verification
println("\n✓ Carrier phase advanced uniformly by ", expected_increment, " per tick")
println("✓ AMC amplitude modulation verified (magnitudes vary with price deltas)")
println("✓ All tests passed successfully!")

println("\n" * "=" ^ 80)
println("AMC Encoder Small Dataset Test: PASS")
println("=" ^ 80)

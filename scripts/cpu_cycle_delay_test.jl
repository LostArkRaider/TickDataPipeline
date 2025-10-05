#!/usr/bin/env julia

# Precise delay using CPU cycle counting (RDTSC instruction)

using Dates

"""
Get CPU timestamp counter (TSC) - nanosecond precision
Uses Julia's built-in time_ns() which uses RDTSC on x86
"""
@inline function get_nanoseconds()::UInt64
    return time_ns()
end

"""
Calibrate CPU cycles to determine nanoseconds per cycle
"""
function calibrate_timer(calibration_seconds::Float64 = 1.0)::Float64
    println("Calibrating timer for $(calibration_seconds)s...")

    start_ns = get_nanoseconds()
    start_time = time()

    # Wait for calibration period
    while (time() - start_time) < calibration_seconds
        # Busy wait
    end

    end_ns = get_nanoseconds()
    end_time = time()

    elapsed_ns = end_ns - start_ns
    elapsed_s = end_time - start_time

    println("Calibration complete:")
    println("  Elapsed: $(round(elapsed_s, digits=3))s")
    println("  Nanoseconds counted: $elapsed_ns")

    return Float64(elapsed_ns) / elapsed_s
end

"""
Precise delay using nanosecond counter
"""
function nano_delay(delay_seconds::Float64)
    if delay_seconds <= 0.0
        return
    end

    delay_ns = UInt64(round(delay_seconds * 1e9))
    start_ns = get_nanoseconds()
    target_ns = start_ns + delay_ns

    while get_nanoseconds() < target_ns
        # Busy wait using nanosecond counter
    end
end

"""
Hybrid nano delay: yield for longer delays, busy-wait for precision
"""
function hybrid_nano_delay(delay_seconds::Float64)
    if delay_seconds <= 0.0
        return
    end

    # For very short delays, just busy-wait
    if delay_seconds < 0.0001  # Less than 0.1ms
        nano_delay(delay_seconds)
        return
    end

    # For longer delays, yield periodically to reduce CPU usage
    delay_ns = UInt64(round(delay_seconds * 1e9))
    start_ns = get_nanoseconds()
    target_ns = start_ns + delay_ns

    # Yield until we're close to target (within 50 microseconds)
    while (target_ns - get_nanoseconds()) > 50000
        yield()  # Let other tasks run
    end

    # Final precision busy-wait
    while get_nanoseconds() < target_ns
        # Busy wait for final precision
    end
end

function test_nano_delay(method_name::String, delay_func::Function, delay_ms::Float64, iterations::Int = 10000)
    println("\nTesting $method_name: $(delay_ms)ms")
    println("Iterations: $iterations")

    start_time = time()

    for i in 1:iterations
        if delay_ms > 0.0
            delay_func(delay_ms / 1000.0)
        end
    end

    end_time = time()
    elapsed = end_time - start_time

    expected_time = (delay_ms / 1000.0) * iterations
    actual_per_tick = (elapsed / iterations) * 1000.0  # Convert to ms

    println("Results:")
    println("  Expected total time: $(round(expected_time, digits=3))s")
    println("  Actual total time: $(round(elapsed, digits=3))s")
    println("  Expected per tick: $(delay_ms)ms")
    println("  Actual per tick: $(round(actual_per_tick, digits=4))ms")
    println("  Error: $(round(abs(actual_per_tick - delay_ms), digits=4))ms")

    if delay_ms > 0
        accuracy = (1.0 - abs(actual_per_tick - delay_ms) / delay_ms) * 100
        println("  Accuracy: $(round(accuracy, digits=2))%")
    end

    println("  Rate: $(round(iterations / elapsed, digits=1)) ticks/second")
end

# Run tests
println("="^60)
println("CPU CYCLE-BASED TIMING TESTS")
println("="^60)

# Calibrate (optional - time_ns() is already calibrated)
calibrate_timer(0.5)

println("\n" * "="^60)
println("NANO DELAY (pure busy-wait)")
println("="^60)
test_nano_delay("nano_delay()", nano_delay, 0.5, 10000)
test_nano_delay("nano_delay()", nano_delay, 1.0, 10000)

println("\n" * "="^60)
println("HYBRID NANO DELAY (yield + busy-wait)")
println("="^60)
test_nano_delay("hybrid_nano_delay()", hybrid_nano_delay, 0.5, 10000)
test_nano_delay("hybrid_nano_delay()", hybrid_nano_delay, 1.0, 10000)

println("\n" * "="^60)

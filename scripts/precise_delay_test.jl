#!/usr/bin/env julia

# Test precise delay using busy-wait for sub-millisecond timing

using Dates

"""
Precise delay using busy-wait (CPU intensive but accurate)
"""
function precise_delay(delay_seconds::Float64)
    if delay_seconds <= 0.0
        return
    end

    target_time = time() + delay_seconds
    while time() < target_time
        # Busy wait - uses CPU but very accurate
    end
end

"""
Hybrid delay: sleep for most of the time, busy-wait for the last bit
"""
function hybrid_delay(delay_seconds::Float64)
    if delay_seconds <= 0.0
        return
    end

    # If delay is long enough, sleep for most of it
    if delay_seconds > 0.002  # 2ms threshold
        sleep_time = delay_seconds - 0.001  # Leave 1ms for busy-wait
        sleep(sleep_time)
        precise_delay(0.001)
    else
        # For short delays, just busy-wait
        precise_delay(delay_seconds)
    end
end

function test_delay_method(method_name::String, delay_func::Function, delay_ms::Float64, iterations::Int = 10000)
    println("Testing $method_name: $(delay_ms)ms")
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

    println("\nResults:")
    println("  Expected total time: $(round(expected_time, digits=3))s")
    println("  Actual total time: $(round(elapsed, digits=3))s")
    println("  Expected per tick: $(delay_ms)ms")
    println("  Actual per tick: $(round(actual_per_tick, digits=3))ms")
    println("  Error: $(round(abs(actual_per_tick - delay_ms), digits=3))ms")
    println("  Accuracy: $(round((1.0 - abs(actual_per_tick - delay_ms) / delay_ms) * 100, digits=1))%")
    println("  Rate: $(round(iterations / elapsed, digits=1)) ticks/second")
end

# Test different methods
println("="^60)
println("STANDARD SLEEP (for comparison)")
println("="^60)
test_delay_method("sleep()", sleep, 0.5, 10000)

println("\n" * "="^60)
println("PRECISE BUSY-WAIT")
println("="^60)
test_delay_method("precise_delay()", precise_delay, 0.5, 10000)

println("\n" * "="^60)
println("HYBRID (sleep + busy-wait)")
println("="^60)
test_delay_method("hybrid_delay()", hybrid_delay, 0.5, 10000)

println("\n" * "="^60)
println("HYBRID 1.0ms test")
println("="^60)
test_delay_method("hybrid_delay()", hybrid_delay, 1.0, 10000)
println("="^60)

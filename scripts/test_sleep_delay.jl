#!/usr/bin/env julia

# Test sleep delay accuracy

using Dates

function test_sleep_delay(delay_ms::Float64, iterations::Int = 10000)
    println("Testing sleep delay: $(delay_ms)ms")
    println("Iterations: $iterations")

    start_time = time()

    for i in 1:iterations
        if delay_ms > 0.0
            sleep(delay_ms / 1000.0)
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
    println("  Slowdown factor: $(round(elapsed / expected_time, digits=2))x")
    println("  Rate: $(round(iterations / elapsed, digits=1)) ticks/second")
end

# Test different delay values
println("="^60)
test_sleep_delay(0.0, 10000)
println("\n" * "="^60)
test_sleep_delay(0.5, 10000)
println("\n" * "="^60)
test_sleep_delay(1.0, 10000)
println("\n" * "="^60)

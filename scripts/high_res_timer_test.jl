#!/usr/bin/env julia

# Test high-resolution sleep using Windows multimedia timer API

using Dates

# Windows API for high-resolution timer
const winmm = "winmm"

# Set timer resolution (in milliseconds)
# timeBeginPeriod(1) sets 1ms resolution
function set_timer_resolution(ms::Int)
    ccall((:timeBeginPeriod, winmm), UInt32, (UInt32,), UInt32(ms))
end

# Restore default timer resolution
function restore_timer_resolution(ms::Int)
    ccall((:timeEndPeriod, winmm), UInt32, (UInt32,), UInt32(ms))
end

function test_sleep_with_high_res(delay_ms::Float64, iterations::Int = 10000)
    println("Testing high-res sleep delay: $(delay_ms)ms")
    println("Iterations: $iterations")

    # Set 1ms timer resolution
    set_timer_resolution(1)

    start_time = time()

    for i in 1:iterations
        if delay_ms > 0.0
            sleep(delay_ms / 1000.0)
        end
    end

    end_time = time()
    elapsed = end_time - start_time

    # Restore default timer resolution
    restore_timer_resolution(1)

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

# Test different delay values with high-resolution timer
println("="^60)
println("HIGH-RESOLUTION TIMER TESTS")
println("="^60)
test_sleep_with_high_res(0.5, 10000)
println("\n" * "="^60)
test_sleep_with_high_res(1.0, 10000)
println("\n" * "="^60)

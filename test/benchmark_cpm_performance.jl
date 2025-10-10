# CPM vs HEXAD16 Performance Benchmark
# Measures per-tick latency and throughput for encoder comparison
# Protocol T-36 compliant: No string literals in @test or @testset

using Test
using TickDataPipeline
using Statistics

# Benchmark configuration
const WARMUP_TICKS = Int32(1000)
const BENCHMARK_TICKS = Int32(100000)
const LATENCY_BUDGET_NS = Float64(10000)  # 10μs budget per tick

function benchmark_encoder(encoder_type::String, modulation_index::Float32)
    # Create state
    state = create_tickhotloop_state()

    # Configuration parameters (from default config)
    agc_alpha = Float32(0.0625)
    agc_min_scale = Int32(4)
    agc_max_scale = Int32(50)
    winsorize_delta_threshold = Int32(10)
    min_price = Int32(40000)
    max_price = Int32(43000)
    max_jump = Int32(50)

    # Warmup phase (JIT compilation)
    for i in 1:WARMUP_TICKS
        msg = create_broadcast_message(
            Int32(i),
            Int64(0),
            Int32(41500 + (i % 20) - 10),
            Int32((i % 20) - 10)
        )
        process_tick_signal!(
            msg, state,
            agc_alpha, agc_min_scale, agc_max_scale, winsorize_delta_threshold,
            min_price, max_price, max_jump,
            encoder_type, modulation_index
        )
    end

    # Reset state for benchmark
    state = create_tickhotloop_state()

    # Collect latency samples for percentile analysis
    latencies_ns = Vector{Float64}(undef, BENCHMARK_TICKS)

    # Benchmark phase with per-tick timing
    for i in 1:BENCHMARK_TICKS
        msg = create_broadcast_message(
            Int32(i),
            Int64(0),
            Int32(41500 + (i % 20) - 10),
            Int32((i % 20) - 10)
        )

        tick_start = time_ns()
        process_tick_signal!(
            msg, state,
            agc_alpha, agc_min_scale, agc_max_scale, winsorize_delta_threshold,
            min_price, max_price, max_jump,
            encoder_type, modulation_index
        )
        tick_end = time_ns()

        latencies_ns[i] = Float64(tick_end - tick_start)
    end

    # Calculate statistics
    total_time_ns = sum(latencies_ns)
    total_time_ms = total_time_ns / 1_000_000
    avg_latency_ns = mean(latencies_ns)
    median_latency_ns = median(latencies_ns)
    p95_latency_ns = quantile(latencies_ns, 0.95)
    p99_latency_ns = quantile(latencies_ns, 0.99)
    p999_latency_ns = quantile(latencies_ns, 0.999)
    min_latency_ns = minimum(latencies_ns)
    max_latency_ns = maximum(latencies_ns)
    throughput_tps = Float64(BENCHMARK_TICKS) / (total_time_ns / 1_000_000_000)

    return (
        encoder = encoder_type,
        total_time_ms = total_time_ms,
        avg_latency_ns = avg_latency_ns,
        median_latency_ns = median_latency_ns,
        p95_latency_ns = p95_latency_ns,
        p99_latency_ns = p99_latency_ns,
        p999_latency_ns = p999_latency_ns,
        min_latency_ns = min_latency_ns,
        max_latency_ns = max_latency_ns,
        throughput_tps = throughput_tps,
        ticks_processed = BENCHMARK_TICKS
    )
end

@testset begin  # CPM Performance Benchmarks

    println("\n" * "="^80)
    println("CPM vs HEXAD16 Performance Benchmark")
    println("="^80)
    println("Warmup ticks: $WARMUP_TICKS")
    println("Benchmark ticks: $BENCHMARK_TICKS")
    println("Latency budget: $(LATENCY_BUDGET_NS)ns (10μs per tick)")
    println("="^80)

    @testset begin  # HEXAD16 Baseline Performance
        results = benchmark_encoder("hexad16", Float32(0.5))

        println("\nHEXAD16 Results:")
        println("  Total time: $(round(results.total_time_ms, digits=2))ms")
        println("  Avg latency: $(round(results.avg_latency_ns, digits=2))ns")
        println("  Median latency: $(round(results.median_latency_ns, digits=2))ns")
        println("  P95 latency: $(round(results.p95_latency_ns, digits=2))ns")
        println("  P99 latency: $(round(results.p99_latency_ns, digits=2))ns")
        println("  P99.9 latency: $(round(results.p999_latency_ns, digits=2))ns")
        println("  Min latency: $(round(results.min_latency_ns, digits=2))ns")
        println("  Max latency: $(round(results.max_latency_ns, digits=2))ns")
        println("  Throughput: $(round(results.throughput_tps, digits=0)) ticks/sec")
        println("  Budget usage: $(round(results.avg_latency_ns / LATENCY_BUDGET_NS * 100, digits=2))%")

        # Verify meets budget at all percentiles
        @test results.avg_latency_ns < LATENCY_BUDGET_NS
        @test results.p95_latency_ns < LATENCY_BUDGET_NS
        @test results.p99_latency_ns < LATENCY_BUDGET_NS
        @test results.p999_latency_ns < LATENCY_BUDGET_NS
    end

    @testset begin  # CPM Performance h=0.5
        results = benchmark_encoder("cpm", Float32(0.5))

        println("\nCPM (h=0.5) Results:")
        println("  Total time: $(round(results.total_time_ms, digits=2))ms")
        println("  Avg latency: $(round(results.avg_latency_ns, digits=2))ns")
        println("  Median latency: $(round(results.median_latency_ns, digits=2))ns")
        println("  P95 latency: $(round(results.p95_latency_ns, digits=2))ns")
        println("  P99 latency: $(round(results.p99_latency_ns, digits=2))ns")
        println("  P99.9 latency: $(round(results.p999_latency_ns, digits=2))ns")
        println("  Min latency: $(round(results.min_latency_ns, digits=2))ns")
        println("  Max latency: $(round(results.max_latency_ns, digits=2))ns")
        println("  Throughput: $(round(results.throughput_tps, digits=0)) ticks/sec")
        println("  Budget usage: $(round(results.avg_latency_ns / LATENCY_BUDGET_NS * 100, digits=2))%")

        # Verify meets budget at all percentiles
        @test results.avg_latency_ns < LATENCY_BUDGET_NS
        @test results.p95_latency_ns < LATENCY_BUDGET_NS
        @test results.p99_latency_ns < LATENCY_BUDGET_NS
        @test results.p999_latency_ns < LATENCY_BUDGET_NS
    end

    @testset begin  # CPM Performance h=0.25
        results = benchmark_encoder("cpm", Float32(0.25))

        println("\nCPM (h=0.25) Results:")
        println("  Total time: $(round(results.total_time_ms, digits=2))ms")
        println("  Avg latency: $(round(results.avg_latency_ns, digits=2))ns")
        println("  Throughput: $(round(results.throughput_tps, digits=0)) ticks/sec")
        println("  Budget usage: $(round(results.avg_latency_ns / LATENCY_BUDGET_NS * 100, digits=2))%")

        # Verify meets budget
        @test results.avg_latency_ns < LATENCY_BUDGET_NS
    end

    @testset begin  # Comparative Analysis
        hexad16_results = benchmark_encoder("hexad16", Float32(0.5))
        cpm_results = benchmark_encoder("cpm", Float32(0.5))

        latency_ratio = cpm_results.avg_latency_ns / hexad16_results.avg_latency_ns
        throughput_ratio = cpm_results.throughput_tps / hexad16_results.throughput_tps
        latency_overhead_ns = cpm_results.avg_latency_ns - hexad16_results.avg_latency_ns

        println("\n" * "="^80)
        println("Comparative Analysis (HEXAD16 vs CPM h=0.5):")
        println("  CPM latency overhead: +$(round(latency_overhead_ns, digits=2))ns ($(round((latency_ratio - 1.0) * 100, digits=2))%)")
        println("  CPM throughput ratio: $(round(throughput_ratio, digits=3))x")
        println("  HEXAD16 avg latency: $(round(hexad16_results.avg_latency_ns, digits=2))ns")
        println("  CPM avg latency: $(round(cpm_results.avg_latency_ns, digits=2))ns")
        println("  Both encoders within budget: $(hexad16_results.avg_latency_ns < LATENCY_BUDGET_NS && cpm_results.avg_latency_ns < LATENCY_BUDGET_NS)")
        println("="^80)

        # CPM should be within 2x of HEXAD16 latency (generous bound)
        @test latency_ratio < Float64(2.0)

        # Both should meet budget comfortably
        @test hexad16_results.avg_latency_ns < LATENCY_BUDGET_NS
        @test cpm_results.avg_latency_ns < LATENCY_BUDGET_NS

        # Throughput should be comparable (>0.5x hexad16)
        @test throughput_ratio > Float64(0.5)
    end

    @testset begin  # Memory Allocation Check
        # Run with allocation tracking
        allocs_hexad16 = @allocated begin
            state = create_tickhotloop_state()
            msg = create_broadcast_message(Int32(1), Int64(0), Int32(41500), Int32(5))
            process_tick_signal!(
                msg, state,
                Float32(0.0625), Int32(4), Int32(50), Int32(10),
                Int32(40000), Int32(43000), Int32(50),
                "hexad16", Float32(0.5)
            )
        end

        allocs_cpm = @allocated begin
            state = create_tickhotloop_state()
            msg = create_broadcast_message(Int32(1), Int64(0), Int32(41500), Int32(5))
            process_tick_signal!(
                msg, state,
                Float32(0.0625), Int32(4), Int32(50), Int32(10),
                Int32(40000), Int32(43000), Int32(50),
                "cpm", Float32(0.5)
            )
        end

        println("\nMemory Allocation Check:")
        println("  HEXAD16 allocations: $(allocs_hexad16) bytes")
        println("  CPM allocations: $(allocs_cpm) bytes")

        # Both should be zero-allocation in hot loop (after JIT)
        # Allow small overhead for first call
        @test allocs_hexad16 < 1000
        @test allocs_cpm < 1000
    end

end  # End CPM Performance Benchmarks

# Julia Test Creation Protocol
## Strict Compliance Framework for Test Script Development
### Version 1.4

---

# PROJECT CONTEXT NOTICE
## When Using This Protocol in Claude Projects

This protocol document is loaded into Claude Project for persistent reference.

### Purpose
This protocol prevents common issues encountered when Julia test scripts are created without development standards. It addresses type errors, module loading issues, configuration problems, test output management, and testing best practices specific to the ComplexBiquadGA project.

### Relationship to Other Protocols
- Complements: Complex Biquad GA Development Protocol v1.7
- Enforces: R15 (Fix implementation, never modify tests to pass)
- Supports: R21 (Session documentation requirements)
- Prevents: Common test-related violations of R20 (Module dependency order)

### Version History
- v1.0: Initial protocol with core requirements (T1-T29)
- v1.1: Added output management requirements (T30-T35) to prevent Claude file size limits
- v1.2: Updated T7 to allow programmatic test configuration creation
- v1.3: Added T36 to prevent invalid @test syntax with string messages
- v1.4: Added T37 prohibiting @test_broken and @testset_broken - no broken tests allowed

---

## 🔴 MANDATORY TEST CREATION RULES

### T1: Test File Location and Naming
```
REQUIREMENT: All test scripts in test/ folder with test_ prefix

NAMING PATTERN:
- test_[module_name].jl for module-specific tests
- test_[feature]_[aspect].jl for feature tests
- diagnostic_[issue].jl for troubleshooting tests (temporary)

EXAMPLES:
✅ test/test_volume_expansion.jl
✅ test/test_pipeline_performance.jl
✅ test/diagnostic_consumer_subscription.jl
❌ src/tests/my_test.jl (wrong location)
❌ test/volumeExpansionTests.jl (wrong naming)

RATIONALE: Consistent naming enables automated test discovery and execution.
```

### T2: Test Runner Integration
```
REQUIREMENT: All tests callable from standard Julia runtests.jl

INTEGRATION PATTERN:
# In runtests.jl:
@testset begin #Feature Name
    include("test_feature.jl")
end

STANDALONE CAPABILITY:
Each test file must also run independently:
julia test/test_feature.jl

RATIONALE: Enables both comprehensive and targeted test execution.
```

### T3: Module Import Requirements
```
REQUIREMENT: Proper using statements for standalone execution

MANDATORY IMPORTS:
using Test
using ComplexBiquadGA
# NO additional using statements except Base Julia modules

FORBIDDEN:
❌ using Main.ComplexBiquadGA (causes module not found errors)
❌ include("../src/SomeModule.jl") (violates module system)
❌ using .SomeModule (incorrect relative import)

CORRECT PATTERN:
using ComplexBiquadGA
# Access via fully qualified names
ComplexBiquadGA.ModuleName.function_name()

RATIONALE: Prevents module loading errors and forward reference violations.
```

### T4: Verbosity Control Requirements
```
REQUIREMENT: Use standard Julia environment variables for verbosity

IMPLEMENTATION:
# Check for test verbosity settings
const TEST_VERBOSE = get(ENV, "JULIA_TEST_VERBOSE", "false") == "true"
const TEST_QUIET = get(ENV, "JULIA_TEST_QUIET", "false") == "true"

# Usage in tests:
if TEST_VERBOSE
    println("Detailed debug information...")
end

if !TEST_QUIET
    println("Standard test progress...")
end

# For performance tests with many iterations:
function process_tick_quietly(pipeline_manager, test_tick, tick_number)
    if TEST_QUIET
        redirect_stdout(devnull) do
            # Process without output
        end
    else
        # Process with normal output
    end
end

RATIONALE: Enables flexible output control without code modification.
```

### T5: No Mocking Policy
```
REQUIREMENT: Use actual methods from the application - NO MOCKS

FORBIDDEN:
❌ Mock objects or stubs
❌ Test doubles or fakes
❌ Simulated interfaces

REQUIRED:
✅ Actual ComplexBiquadGA module components
✅ Real system integration
✅ Genuine data flow validation

EXCEPTION:
- Timing delays may use sleep() for simulation
- Missing future features may use placeholder processing

EXAMPLE:
# WRONG - Mocking
mock_filter = MockFilter()  # ❌

# CORRECT - Actual component
filter = ComplexBiquadGA.ProductionFilterBank.create_filter()  # ✅

RATIONALE: Real component testing reveals actual integration issues.
```

### T6: Real Data Requirements
```
REQUIREMENT: Use actual files from data/ folder - NO FAKE DATA

DATA FILE PATTERNS:
- Production data: data/raw/YM 06-25.Last.txt
- Sample data: data/raw/YM 06-25.Last.sample.txt
- Test configs: config/filters/test_config.toml

TEMPORARY FILES:
- Use tempname() for transient test data
- Clean up temp files after test completion

EXAMPLE:
# WRONG - Hardcoded fake data
test_tick = "fake;data;here"  # ❌

# CORRECT - Real data file
test_file = "data/raw/YM 06-25.Last.txt"  # ✅
ticks = read_ticks_from_file(test_file)

RATIONALE: Testing with real data reveals actual processing issues.
```

### T7: Configuration Management
```
REQUIREMENT: Use ModernConfigSystem.jl constructs OR programmatic test configs

FORBIDDEN:
❌ Hardcoded magic numbers scattered through tests
❌ Manual TOML parsing in tests
❌ Undocumented configuration assumptions

REQUIRED FOR PRODUCTION CONFIGS:
✅ ModernConfigSystem.load_filter_config() for production configs
✅ Configuration from TOML files for persistent configs
✅ Configurable test parameters

ALLOWED FOR TEST-ONLY CONFIGS:
✅ Programmatic creation of test configuration objects
✅ In-memory test configs that don't require TOML files
✅ Named test configuration presets (e.g., "test_config", "minimal_config")

EXAMPLE - THREE VALID APPROACHES:

# APPROACH 1: Load from TOML file (for persistent configs)
config = ComplexBiquadGA.ModernConfigSystem.load_filter_config("production_config")

# APPROACH 2: Create programmatic test config (for test-only configs)
function create_test_config(name::String = "default")
    if name == "minimal"
        return FilterConfig(
            fibonacci_periods = Int32[1, 2, 3],
            population_size = Int32(10),
            production_buffer_size = Int32(512),
            ab_test_buffer_size = Int32(512),
            simulated_live_buffer_size = Int32(512)
        )
    elseif name == "stress_test"
        return FilterConfig(
            fibonacci_periods = Int32[1, 2, 3, 5, 8, 13, 21],
            population_size = Int32(100),
            production_buffer_size = Int32(10000),
            ab_test_buffer_size = Int32(10000),
            simulated_live_buffer_size = Int32(10000)
        )
    else  # default test config
        return FilterConfig(
            fibonacci_periods = Int32[1, 2, 3, 5, 8],
            population_size = Int32(50),
            production_buffer_size = Int32(2048),
            ab_test_buffer_size = Int32(1536),
            simulated_live_buffer_size = Int32(1536)
        )
    end
end

# Usage in tests:
config = create_test_config("minimal")  # For quick unit tests
config = create_test_config("stress_test")  # For load testing
config = create_test_config()  # Default test configuration

# APPROACH 3: Hybrid - Override specific values
config = ComplexBiquadGA.ModernConfigSystem.load_filter_config("base_config")
config.production_buffer_size = Int32(4096)  # Override for specific test

# WRONG - Scattered magic numbers
buffer_size = 1024  # ❌ What is this? Why 1024?
iterations = 5000   # ❌ Undocumented constant

# CORRECT - Named configuration
config = create_test_config("performance")
buffer_size = config.production_buffer_size  # ✅ Clear source

RATIONALE: Enables both persistent configuration management AND
flexible test-specific configurations without requiring TOML files
for every test scenario. Test configs can be created programmatically
for isolated test environments.
```

---

## 🔴 TYPE SYSTEM COMPLIANCE RULES

### T8: Type Precision Requirements
```
REQUIREMENT: Use correct precision types consistently

MANDATORY TYPES:
- Float32 for all floating-point calculations
- Int32 for all integer values (GPU compatibility)
- ComplexF32 for complex numbers

FORBIDDEN:
❌ Float64 (unless explicitly justified)
❌ Int64 (unless system API requires)
❌ Mixed precision in same calculation

CONVERSION PATTERNS:
# WRONG
value = 1.0  # Float64 by default ❌

# CORRECT
value = Float32(1.0)  # Explicit Float32 ✅
count = Int32(100)    # Explicit Int32 ✅

RATIONALE: Prevents type mismatch errors and ensures GPU compatibility.
```

### T9: Array Slice Handling
```
REQUIREMENT: Convert array slices to concrete types when needed

PROBLEM:
matrix[row, :] returns SubArray, not Vector
Many functions expect Vector{T} specifically

SOLUTION PATTERNS:
# WRONG - Passing slice directly
process_vector(matrix[1, :])  # MethodError ❌

# CORRECT - Explicit conversion
process_vector(Vector{Float32}(matrix[1, :]))  # ✅
process_vector(collect(matrix[1, :]))         # ✅

RATIONALE: Prevents MethodError from type mismatches with SubArray.
```

### T10: Channel Type Consistency
```
REQUIREMENT: Maintain consistent channel element types

CHANNEL PATTERNS:
# Correct channel creation
Channel{String}(buffer_size)     # For tick data
Channel{ComplexF32}(buffer_size) # For processed signals
Channel{Tuple{Int32, String}}()  # For indexed data

FORBIDDEN:
❌ Channel{Any}() (loses type safety)
❌ Mismatched put!/take! types

RATIONALE: Prevents runtime type errors in concurrent code.
```

---

## 🔴 TEST STRUCTURE REQUIREMENTS

### T11: Test Set Organization
```
REQUIREMENT: Hierarchical @testset structure with clear descriptions

PATTERN:
@testset begin #Module/Feature Name
    @testset "Specific Functionality" begin
        @testset "Edge Case or Scenario" begin
            # Individual test assertions
        end
    end
end

EXAMPLE:
@testset "" begin
    @testset begin #Pipeline Performance Validation
        @testset "Average Latency Under Load" begin
            @test avg_latency < Float32(250.0)
        end
    end
end

RATIONALE: Provides clear test organization and failure localization.
```

### T12: Setup and Teardown
```
REQUIREMENT: Proper resource management in tests

PATTERN:
@testset begin #Feature Test
    # Setup
    test_file = tempname() * ".txt"
    pipeline = create_test_pipeline()
    
    try
        # Test execution
        @test process(pipeline, test_file)
    finally
        # Teardown - ALWAYS execute
        stop_pipeline!(pipeline)
        rm(test_file, force=true)
    end
end

CRITICAL:
- Always stop running processes
- Always close channels
- Always remove temp files
- Use try/finally for guaranteed cleanup

RATIONALE: Prevents resource leaks and test interference.
```

### T13: Assertion Patterns
```
REQUIREMENT: Use appropriate assertion types with correct types

ASSERTION TYPES:
@test condition                    # Boolean test
@test expr ≈ expected             # Approximate equality
@test expr == expected            # Exact equality
@test_throws ErrorType expr      # Exception testing
@test_skip condition              # Conditional skipping

TYPE-AWARE ASSERTIONS:
# WRONG - Type mismatch
@test result == 1.0  # Comparing Float32 to Float64 ❌

# CORRECT - Same types
@test result == Float32(1.0)  # ✅
@test result ≈ Float32(1.0)   # ✅ (preferred for floats)

RATIONALE: Prevents false test failures from type mismatches.
```

---

## 🔴 PERFORMANCE TEST REQUIREMENTS

### T14: Timing Measurement Standards
```
REQUIREMENT: Accurate timing measurements with JIT warmup

PATTERN:
# JIT Warmup - MANDATORY
function warmup_function()
    # Run function once to compile
    test_function(small_input)
end

# Actual measurement
warmup_function()  # Compile first
start_time = time_ns()
result = test_function(actual_input)
elapsed_ns = time_ns() - start_time
elapsed_ms = elapsed_ns / 1_000_000

FORBIDDEN:
❌ Timing without warmup (includes JIT compilation time)
❌ Using time() for microsecond measurements (insufficient precision)

RATIONALE: Ensures accurate performance measurements.
```

### T15: Realistic Load Testing
```
REQUIREMENT: Use realistic data volumes and rates

GUIDELINES:
- Use actual tick file data, not synthetic
- Test with production data volumes
- Simulate realistic tick rates (10-100 tps)
- Include buffer saturation scenarios

EXAMPLE:
# WRONG - Unrealistic synthetic data
for i in 1:1000000
    test_tick = "synthetic_$i"  # ❌
end

# CORRECT - Real data with realistic rate
ticks = read_ticks_from_file("data/raw/YM 06-25.Last.txt")
for tick in ticks[1:min(5000, length(ticks))]
    process_tick(tick)
    sleep(0.01)  # 100 tps rate
end

RATIONALE: Reveals actual performance characteristics and bottlenecks.
```

### T16: Memory Testing Patterns
```
REQUIREMENT: Monitor memory growth and stability

PATTERN:
# Baseline measurement
GC.gc()  # Force collection
baseline_memory = Base.gc_live_bytes() / 1024^2

# Test execution
for i in 1:iterations
    process_operation()
end

# Growth measurement
GC.gc()  # Force collection
final_memory = Base.gc_live_bytes() / 1024^2
growth_percentage = (final_memory - baseline_memory) / baseline_memory * 100

@test growth_percentage < Float32(5.0)  # Max 5% growth

RATIONALE: Detects memory leaks and allocation issues.
```

---

## 🔴 ERROR HANDLING IN TESTS

### T17: Error Detection and Diagnosis
```
REQUIREMENT: Capture and analyze errors comprehensively

PATTERN:
errors_captured = []
for i in 1:test_iterations
    try
        result = process_operation(i)
        @test result.success
    catch e
        push!(errors_captured, (
            iteration = i,
            error_type = typeof(e),
            message = string(e),
            backtrace = catch_backtrace()
        ))
        if length(errors_captured) == 1
            # Report first error immediately
            println("First error at iteration $i: $e")
        end
    end
end

# Analyze error patterns
if !isempty(errors_captured)
    println("Total errors: $(length(errors_captured))")
    # Analyze patterns...
end

RATIONALE: Enables root cause analysis of test failures.
```

### T18: Channel Saturation Detection
```
REQUIREMENT: Detect and diagnose channel saturation issues

PATTERN:
# Monitor channel fill levels
function check_channel_saturation(channel, buffer_size)
    current_size = Base.n_avail(channel)
    saturation_ratio = Float32(current_size) / Float32(buffer_size)
    
    if saturation_ratio > 0.9
        @warn "Channel near saturation" ratio=saturation_ratio
    end
    
    return saturation_ratio
end

# In test loop
for i in 1:iterations
    if i % 100 == 0
        saturation = check_channel_saturation(channel, buffer_size)
        @test saturation < Float32(0.95)  # Not saturated
    end
end

RATIONALE: Identifies backpressure and flow control issues.
```

---

## 🔴 DIAGNOSTIC TEST PATTERNS

### T19: Incremental Failure Isolation
```
REQUIREMENT: Create diagnostic tests to isolate failure points

FORBIDDEN:
❌ String literals in @testset assertions; put the information in a comment instead

PATTERN:
# diagnostic_[issue_name].jl
@testset begin #Diagnostic: Issue Name
    println("Step 1: Component Creation")
    component = create_component()
    @test component !== nothing
    
    println("Step 2: Configuration")
    configured = configure_component(component)
    @test configured == true
    
    println("Step 3: Operation")
    result = operate_component(component)
    @test result.success
    
    # Report exact failure point
    println("Diagnostic complete: All steps passed")
end

USAGE:
- Create when regular tests fail mysteriously
- Delete after root cause is fixed
- Document findings in session log

RATIONALE: Pinpoints exact failure location in complex systems.
```

### T20: Success Pattern Analysis
```
REQUIREMENT: Analyze patterns in intermittent failures

PATTERN:
successes = Int32[]
failures = Int32[]

for i in 1:test_count
    result = test_operation(i)
    if result.success
        push!(successes, Int32(i))
    else
        push!(failures, Int32(i))
        if length(failures) == 1
            println("First failure at: $i")
        end
    end
end

# Analyze patterns
if !isempty(failures)
    # Check if failures are consecutive
    consecutive = all(diff(failures) .== 1)
    
    # Check if failures start at specific point
    failure_start = failures[1]
    
    println("Failure pattern analysis:")
    println("  Total failures: $(length(failures))")
    println("  First failure: $failure_start")
    println("  Consecutive: $consecutive")
    
    if failure_start ≈ 974  # Known issue point
        @warn "Consistent failure at known problem point"
    end
end

RATIONALE: Identifies systematic vs random failures.
```

---

## 🔴 COMMON ISSUES PREVENTION

### T21: Module Loading Order Issues
```
ISSUE: Forward references causing UndefVarError

PREVENTION:
# In test file - use only ComplexBiquadGA exports
using Test
using ComplexBiquadGA

# Access submodules via parent
ComplexBiquadGA.VolumeExpansion.stream_expanded_ticks()  # ✅

FORBIDDEN:
using ComplexBiquadGA.VolumeExpansion  # ❌ May not be exported
using .VolumeExpansion                  # ❌ Relative import

RATIONALE: Prevents module loading order violations (R20).
```

### T22: Consumer Channel Issues
```
ISSUE: Channels not draining, causing saturation at ~1487 ticks

PREVENTION:
# Ensure consumers are actually processing
@test consumer.is_processing == true

# Monitor drainage
for i in 1:tick_count
    process_tick(tick)
    
    if i % 100 == 0
        # Check all consumer channels
        for consumer in consumers
            available = Base.n_avail(consumer.channel)
            @test available < buffer_size * 0.9
        end
    end
end

RATIONALE: Early detection of consumer processing failures.
```

### T23: File Path Issues
```
ISSUE: Tests failing due to incorrect file paths

PREVENTION:
# Always use project root paths
test_file = "data/raw/YM 06-25.Last.txt"  # ✅

# Verify file exists before use
if !isfile(test_file)
    error("Required test file not found: $test_file")
end

FORBIDDEN:
joinpath(@__DIR__, "../data/raw/file.txt")  # ❌
"../data/raw/file.txt"                       # ❌

RATIONALE: Ensures consistent file access (R22).
```

### T24: Metrics Reset Issues
```
ISSUE: Resetting metrics breaks internal state references

PREVENTION:
# Preserve critical state when resetting metrics
original_start_time = pipeline.metrics.pipeline_start_time
pipeline.metrics = PipelineMetrics()
pipeline.metrics.pipeline_start_time = original_start_time  # Preserve

# Or reset individual fields instead
pipeline.metrics.successful_ticks = Int32(0)
pipeline.metrics.failed_ticks = Int32(0)
# ... reset other fields individually

RATIONALE: Maintains pipeline timing references.
```

---

## 🔴 TEST QUALITY STANDARDS

### T25: Comprehensive Coverage
```
REQUIREMENT: Test normal, edge, and error cases

COVERAGE CHECKLIST:
□ Normal operation paths
□ Edge cases (empty, single, maximum)
□ Error conditions
□ Concurrent operation
□ Resource exhaustion
□ Configuration variations
□ Performance boundaries

EXAMPLE:
@testset begin # Component Tests
    @testset begin # Normal Operation
    ... end
    @testset begin # Edge Cases
        @testset begin # Empty Input
        ... end
        @testset begin # Maximum Load
        ... end
    end
    @testset begin # Error Conditions
        @testset begin # Invalid Input
        ... end
        @testset begin #Resource Exhaustion
        ... end
    end
end

RATIONALE: Ensures robust component behavior.
```

### T26: Test Independence
```
REQUIREMENT: Tests must not depend on execution order

FORBIDDEN:
❌ Shared mutable state between tests
❌ Assuming previous test results
❌ Order-dependent test execution

REQUIRED:
✅ Each test creates its own resources
✅ Complete setup in each test
✅ Full cleanup after each test

RATIONALE: Enables parallel test execution and debugging.
```

### T27: Deterministic Testing
```
REQUIREMENT: Reproducible test results

GUIDELINES:
- Set random seeds explicitly
- Use fixed test data sets
- Control timing explicitly
- Document non-deterministic tests

EXAMPLE:
# Set seed for reproducibility
Random.seed!(12345)

# Document non-deterministic aspects
@testset "Concurrent Operations (non-deterministic timing)" begin
    # Test logic accounting for timing variance
end

RATIONALE: Enables reliable continuous integration.
```

---

## 🔴 TEST DOCUMENTATION

### T28: Test Purpose Documentation
```
REQUIREMENT: Clear documentation of test intent

PATTERN:
# test/test_feature.jl
# Purpose: Validates [specific functionality]
# Coverage: [what aspects are tested]
# Dependencies: [required files/configs]
# Note: [special considerations]

@testset "Feature Name - Purpose" begin
    # Test implementation
end

RATIONALE: Aids maintenance and debugging.
```

### T29: Assertion Context
```
REQUIREMENT: Provide context for test assertions

PATTERN:
# WRONG - No context
@test result == expected  # ❌

# CORRECT - With context
@test result == expected "Processing tick $i: expected $expected, got $result"  # ✅

# For complex assertions
if !(condition)
    println("Debug info: ...")
    println("State: ...")
    @test false "Detailed failure reason"
end

RATIONALE: Accelerates debugging of test failures.
```

---

## 🔴 OUTPUT MANAGEMENT REQUIREMENTS (NEW)

### T30: Test Output Size Limits
```
REQUIREMENT: Keep test output files under Claude's readable limit

CLAUDE FILE SIZE LIMITS:
- Maximum readable file: ~100KB (approximately 25,000 tokens)
- Safe target size: 50KB to leave margin
- Critical for debugging: Output must be readable by Claude

MANDATORY LIMITS PER TEST FILE:
- Maximum iterations in performance tests: 1000
- Maximum verbose output lines: 500
- Maximum error detail entries: 100
- Maximum data samples printed: 50

EXAMPLE ENFORCEMENT:
# WRONG - Unlimited output
for i in 1:10000
    println("Processing tick $i: $(detailed_info)")  # ❌ Too much output
end

# CORRECT - Limited output with sampling
const MAX_VERBOSE_LINES = 100
verbose_count = 0
for i in 1:10000
    if i % 100 == 0 && verbose_count < MAX_VERBOSE_LINES
        println("Progress: $i/10000")
        verbose_count += 1
    end
    # Process silently for most iterations
end

RATIONALE: Ensures test output can be analyzed by Claude for debugging.
```

### T31: Test Segmentation Requirements
```
REQUIREMENT: Split large test suites into manageable files

FILE SIZE GUIDELINES:
- Single test file: Maximum 50 test cases
- Performance tests: Maximum 5 scenarios per file
- Integration tests: Maximum 10 end-to-end scenarios

SEGMENTATION PATTERN:
# Instead of one giant test file:
test_pipeline_all.jl  # ❌ 200+ tests

# Split into focused files:
test_pipeline_setup.jl        # ✅ 30 tests
test_pipeline_processing.jl   # ✅ 40 tests
test_pipeline_performance.jl  # ✅ 5 scenarios
test_pipeline_teardown.jl     # ✅ 20 tests

NAMING CONVENTION FOR SPLITS:
test_[module]_[aspect].jl
test_[module]_[aspect]_part1.jl  # If further splitting needed
test_[module]_[aspect]_part2.jl

RATIONALE: Enables targeted debugging and readable output files.
```

### T32: Progressive Output Verbosity
```
REQUIREMENT: Implement tiered verbosity levels

VERBOSITY LEVELS:
0 - SILENT: No output except failures
1 - SUMMARY: Test set pass/fail only  
2 - PROGRESS: Major milestones (every 100 iterations)
3 - DETAILED: Significant events (every 10 iterations)
4 - DEBUG: Everything (use sparingly)

IMPLEMENTATION:
const VERBOSITY = parse(Int, get(ENV, "TEST_VERBOSITY", "1"))

function log_test(level::Int, message::String)
    if level <= VERBOSITY
        println(message)
    end
end

# Usage:
log_test(1, "Test suite started")  # Always shown except silent
log_test(2, "Processed 100 ticks")  # Progress updates
log_test(3, "Channel saturation: 45%")  # Detailed metrics
log_test(4, "Tick data: $tick")  # Debug only

RATIONALE: Controls output volume while preserving debugging capability.
```

### T33: Smart Error Aggregation
```
REQUIREMENT: Aggregate similar errors to reduce output

PATTERN:
# Track error types and counts
error_counts = Dict{String, Int32}()
error_samples = Dict{String, Vector{Any}}()
const MAX_ERROR_SAMPLES = 5

for i in 1:iterations
    try
        process_operation(i)
    catch e
        error_key = string(typeof(e))
        
        # Count all errors
        error_counts[error_key] = get(error_counts, error_key, Int32(0)) + Int32(1)
        
        # But only keep first few samples
        if !haskey(error_samples, error_key)
            error_samples[error_key] = []
        end
        
        if length(error_samples[error_key]) < MAX_ERROR_SAMPLES
            push!(error_samples[error_key], (iteration=i, message=string(e)))
        end
    end
end

# Report aggregated results
println("\n=== ERROR SUMMARY ===")
for (error_type, count) in error_counts
    println("$error_type: $count occurrences")
    println("  Sample iterations: ", [s.iteration for s in error_samples[error_type]])
    if count > MAX_ERROR_SAMPLES
        println("  (Showing first $MAX_ERROR_SAMPLES of $count errors)")
    end
end

RATIONALE: Provides comprehensive error analysis without overwhelming output.
```

### T34: Output Rotation for Long Tests
```
REQUIREMENT: Rotate output files for extended test runs

PATTERN FOR CONTINUOUS TESTING:
# For tests that must run for extended periods
mutable struct RotatingLogger
    base_path::String
    max_size_kb::Int32
    current_file::Union{IOStream, Nothing}
    current_size::Int32
    file_counter::Int32
end

function log_with_rotation(logger::RotatingLogger, message::String)
    # Check if rotation needed
    if logger.current_size > logger.max_size_kb * 1024
        close(logger.current_file)
        logger.file_counter += 1
        logger.current_file = open("$(logger.base_path)_$(logger.file_counter).log", "w")
        logger.current_size = 0
        
        # Keep only last 3 files
        old_file = "$(logger.base_path)_$(logger.file_counter - 3).log"
        if isfile(old_file)
            rm(old_file)
        end
    end
    
    # Write message
    println(logger.current_file, message)
    logger.current_size += length(message)
end

USAGE:
- Extended stress tests
- Overnight stability tests  
- Continuous integration logs

RATIONALE: Maintains readable log files while preserving recent history.
```

### T35: Summary Statistics Instead of Raw Data
```
REQUIREMENT: Report statistics rather than raw data for large datasets

FORBIDDEN:
# Printing all data points
for value in large_dataset
    println("Value: $value")  # ❌ Too much output
end

REQUIRED:
# Print summary statistics
println("Dataset Statistics:")
println("  Count: $(length(large_dataset))")
println("  Mean: $(mean(large_dataset))")
println("  Std Dev: $(std(large_dataset))")
println("  Min: $(minimum(large_dataset))")
println("  Max: $(maximum(large_dataset))")
println("  Quartiles: $(quantile(large_dataset, [0.25, 0.5, 0.75]))")

# Optionally show a few samples
println("  First 5: $(large_dataset[1:min(5, length(large_dataset))])")
println("  Last 5: $(large_dataset[max(1, end-4):end])")

PATTERN FOR TIME SERIES:
# Instead of printing every tick
println("Tick Processing Summary ($(length(ticks)) total):")
println("  Success rate: $(success_count/length(ticks) * 100)%")
println("  Avg latency: $(mean(latencies))μs")  
println("  P95 latency: $(quantile(latencies, 0.95))μs")
println("  Failures at: $(failure_indices[1:min(10, length(failure_indices))])")

RATIONALE: Provides actionable insights without overwhelming output.
```

### T36: Test Assertion Syntax Requirements
```
REQUIREMENT: Use correct Julia Test.jl assertion syntax - NO STRING MESSAGES AFTER @test

FORBIDDEN SYNTAX:
❌ @test condition "error message"         # INVALID - string literals not supported
❌ @test result == expected "failed test"   # INVALID - @test doesn't accept messages
❌ @test value ≈ target "not close enough"  # INVALID - syntax error

REQUIRED PATTERNS:
✅ @test condition                         # Simple assertion
✅ @test result == expected                # Basic comparison
✅ @test value ≈ Float32(1.0)              # Approximate equality

PROVIDING CONTEXT FOR FAILURES:
When test context is needed, use one of these valid patterns:

# Pattern 1: Let @test handle the error message (PREFERRED)
@test result == expected  # Julia Test.jl auto-generates useful error info

# Pattern 2: Use logical OR with error() for custom messages
@test condition || error("Custom error message explaining failure")

# Pattern 3: Use @test_throws for exception testing
@test_throws ErrorType failing_function()

# Pattern 4: Add context via comments or println BEFORE the test
println("Testing: Processing tick $i with value $value")
@test result == expected

# Pattern 5: For complex assertions, use if-else with explicit @test false
if !(complex_condition)
    println("Debug info: state=$state, expected=$expected, got=$result")
    @test false  # Explicit failure with context printed above
end

RATIONALE: Julia's @test macro does not accept string arguments. The syntax 
@test condition "message" will cause a syntax error. Julia Test.jl automatically 
provides informative error messages showing the failed expression and values.
Custom error messages should use the || error() pattern or precede the test.

ENFORCEMENT: Any use of string literals immediately after @test = TEST FILE REJECTION

EXAMPLES OF PROPER TEST CONTEXT:
# ❌ WRONG - Syntax error
@test avg_latency < Float32(250.0) "Latency requirement not met"

# ✅ CORRECT - Auto-generated message
@test avg_latency < Float32(250.0)
# On failure, Julia reports: "Test Failed at test_performance.jl:45
#   Expression: avg_latency < Float32(250.0)
#   Evaluated: 275.5f0 < 250.0f0"

# ✅ CORRECT - Custom message with || error()
@test avg_latency < Float32(250.0) || error("Latency $(avg_latency)μs exceeds 250μs limit")

# ✅ CORRECT - Context via preceding println
println("Latency test: measured $(avg_latency)μs, limit 250μs")
@test avg_latency < Float32(250.0)

CRITICAL: This is a SYNTAX ERROR, not just a style issue. Tests with string 
messages after @test will not compile and will prevent the test suite from running.
```

### T37: No Broken Tests Policy
```
REQUIREMENT: ALL tests must work 100% - NO BROKEN TESTS ALLOWED

ABSOLUTELY FORBIDDEN:
❌ @test_broken condition                    # NEVER allowed
❌ @testset_broken "Broken Test Set"        # NEVER allowed  
❌ @test_skip unless fixed                  # Only temporarily allowed
❌ Commenting out failing tests             # NEVER allowed
❌ Marking any test as "known to fail"      # NEVER allowed
❌ Accepting any test failures as "normal"  # NEVER allowed

ENFORCEMENT:
✅ Every test must pass 100% of the time
✅ Any failing test must be fixed immediately
✅ No test can be marked as broken, expected to fail, or skipped indefinitely
✅ All test elements must be fully functional

CORRECT APPROACH FOR PROBLEMATIC TESTS:
# WRONG - Marking as broken
@test_broken difficult_function() == expected  # ❌ FORBIDDEN

# CORRECT - Fix the implementation
function difficult_function()
    # Fixed implementation that actually works
    return expected_result
end
@test difficult_function() == expected  # ✅ Working test

RATIONALE FOR @test_skip (TEMPORARY ONLY):
# Only allowed during active debugging/development
@test_skip complex_feature()  # Must be followed by immediate fix

# Must be converted to working test within same session:
@test complex_feature()  # ✅ Fixed and working

ZERO TOLERANCE POLICY:
- Any @test_broken usage = IMMEDIATE TEST FILE REJECTION
- Any @testset_broken usage = IMMEDIATE TEST FILE REJECTION
- Any pattern of accepting test failures = PROTOCOL VIOLATION
- Test suite must achieve 100% pass rate at all times

RATIONALE: Broken tests provide no value and create false confidence.
Tests that don't work are worse than no tests. If a feature can't be 
tested reliably, either the feature is broken (fix the feature) or 
the test is wrong (fix the test). There is no third option.

ACCEPTABLE TEMPORARY STATES (SAME SESSION ONLY):
1. Test fails → identify root cause → fix implementation → test passes
2. Test is too complex → simplify test → test passes
3. Feature incomplete → complete feature → test passes

UNACCEPTABLE PERMANENT STATES:
1. Test marked as broken indefinitely
2. Test commented out instead of fixed
3. Test suite with known failures
4. "Expected" test failures in any form

IMPLEMENTATION FIX MANDATE:
When a test fails, the ONLY acceptable solution is:
1. Fix the implementation code to make the test pass
2. If test is incorrect, fix the test logic (not mark as broken)
3. If feature is missing, implement the feature completely
4. Never work around a test failure by marking it as broken

CRITICAL ENFORCEMENT:
Any use of @test_broken, @testset_broken, or patterns that accept
failing tests = IMMEDIATE REJECTION of entire test file.
```

---

## 🔴 ENFORCEMENT AND COMPLIANCE

### Validation Checklist
Before submitting any test file, verify:

```
□ T1: Located in test/ with test_ prefix
□ T2: Integrated with runtests.jl
□ T3: Proper module imports
□ T4: Verbosity control implemented
□ T5: No mocking - real components only
□ T6: Uses actual data files
□ T7: ModernConfigSystem for configuration
□ T8: Correct type precision (Float32, Int32)
□ T9: Array slice conversions where needed
□ T10: Consistent channel types
□ T11: Hierarchical @testset structure
□ T12: Proper setup/teardown
□ T13: Type-aware assertions
□ T14: JIT warmup for timing tests
□ T15: Realistic load testing
□ T16: Memory monitoring
□ T17: Comprehensive error capture
□ T18: Channel saturation detection
□ T19-T20: Diagnostic patterns when needed
□ T21-T24: Common issues prevented
□ T25-T27: Quality standards met
□ T28-T29: Well documented
□ T30: Output size under 50KB target
□ T31: Large suites properly segmented
□ T32: Progressive verbosity implemented
□ T33: Errors aggregated intelligently
□ T34: Output rotation for long tests
□ T35: Summary statistics over raw data
□ T36: No string literals after @test assertions
□ T37: NO broken tests - 100% pass rate mandatory
```

### Protocol Violations
Any violation of T1-T37 requires:
1. Immediate correction before test execution
2. Documentation of issue in session log
3. Update of this protocol if new pattern discovered

---

## 🔴 CRITICAL REMINDERS

1. **NEVER** modify tests to pass - fix implementation (R15)
2. **ALWAYS** use real components and data (T5, T6)
3. **ALWAYS** warm up JIT before performance measurements (T14)
4. **ALWAYS** clean up resources in finally blocks (T12)
5. **ALWAYS** use Float32 and Int32 consistently (T8)
6. **NEVER** use relative imports or includes (T3, T21)
7. **ALWAYS** verify file existence before use (T23)
8. **ALWAYS** preserve critical state when resetting (T24)
9. **ALWAYS** provide assertion context (T29)
10. **NEVER** leave diagnostic tests in production (T19)
11. **ALWAYS** keep output files under 50KB for Claude (T30)
12. **NEVER** print raw data for large datasets (T35)
13. **ALWAYS** segment test files over 50 test cases (T31)
14. **ALWAYS** aggregate similar errors (T33)
15. **NEVER** put string messages directly after @test - use || error() pattern (T36)
16. **ABSOLUTELY NEVER** use @test_broken or @testset_broken - 100% pass rate mandatory (T37)

---

**Confirmation Required**: Type "TEST PROTOCOL ACKNOWLEDGED - OUTPUT LIMITS ENFORCED - REAL COMPONENTS ONLY - FIX IMPLEMENTATION NOT TESTS - NO BROKEN TESTS ALLOWED" to confirm understanding of this framework.

---

*End of Julia Test Creation Protocol v1.4*
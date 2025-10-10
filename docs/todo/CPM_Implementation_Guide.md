# CPM Encoder Implementation Guide
## Phased Development Plan for TickDataPipeline

**Created:** 2025-10-09
**Design Reference:** docs/design/CPM_Encoder_Design_v1.0.md
**Target:** Add configuration-selectable CPM encoder alongside hexad16

---

## Overview

This guide breaks down CPM encoder implementation into **4 session-sized phases**, each fully tested before proceeding to the next. Total estimated development time: 4-6 Claude sessions.

### Design Summary
- **Modulation:** Continuous Phase Modulation (h=0.5, MSK characteristics)
- **Architecture:** Int32 Q32 fixed-point phase accumulator + 1024-entry LUT
- **Integration:** Merge into existing TickHotLoopF32.jl (no separate module)
- **Configuration:** TOML-selectable encoder_type ("hexad16" | "cpm")
- **Performance:** ~25ns per tick (within 10μs budget)

### Critical Test Protocol Requirement

**T-36 COMPLIANCE MANDATORY:**

From Julia_Test_Creation_Protocol v1.4, Section T36:

```julia
# ❌ FORBIDDEN - Syntax error, will not compile:
@test condition "error message"
@testset "Test Description" begin ... end

# ✅ REQUIRED - Valid Julia Test.jl syntax:
@test condition
@testset begin  # No string literal
    # Test description in comment above
    ...
end

# ✅ ALTERNATIVE - Custom messages via || error():
@test condition || error("Custom failure message")
```

**ENFORCEMENT:** Any use of string literals after `@test` or in `@testset` = TEST FILE REJECTION.

All test code in this implementation MUST follow this protocol.

---

## Phase 1: Core CPM Encoder (Foundation)
**Session Size:** 1-2 hours
**Files Modified:** 1
**Tests Created:** 1

### Objectives
1. Add CPM LUT constant to TickHotLoopF32.jl
2. Add phase accumulator field to TickHotLoopState
3. Implement process_tick_cpm!() function
4. Create comprehensive unit tests

### 1.1 Implementation Steps

#### Step 1.1.1: Add CPM_LUT_1024 Constant
**File:** `src/TickHotLoopF32.jl`
**Location:** After HEXAD16 constant (after line 30)

```julia
# CPM 1024-entry complex phasor lookup table
# Used when encoder_type = "cpm"
# Maps phase [0, 2π) to unit-circle complex phasors
const CPM_LUT_1024 = Tuple(
    ComplexF32(
        cos(Float32(2π * k / 1024)),
        sin(Float32(2π * k / 1024))
    ) for k in 0:1023
)

# Q32 fixed-point conversion constants for CPM
const CPM_Q32_SCALE_H05 = Float32(2^31)  # For h=0.5: phase increment scale
const CPM_INDEX_SHIFT = Int32(22)        # Bit shift for 10-bit LUT indexing
const CPM_INDEX_MASK = UInt32(0x3FF)     # 10-bit mask (1023 max)
```

**Verification:**
```julia
# Quick REPL check
julia> length(CPM_LUT_1024)
1024

julia> abs(CPM_LUT_1024[1])
1.0f0

julia> CPM_LUT_1024[1]
1.0f0 + 0.0f0im
```

#### Step 1.1.2: Extend TickHotLoopState
**File:** `src/TickHotLoopF32.jl`
**Location:** Modify struct (lines 37-58)

```julia
mutable struct TickHotLoopState
    last_clean::Union{Int32, Nothing}
    ema_delta::Int32
    ema_delta_dev::Int32
    has_delta_ema::Bool
    ema_abs_delta::Int32
    tick_count::Int64
    ticks_accepted::Int64

    # Bar statistics
    bar_tick_count::Int32
    bar_price_delta_min::Int32
    bar_price_delta_max::Int32
    sum_bar_min::Int64
    sum_bar_max::Int64
    bar_count::Int64
    cached_inv_norm_Q16::Int32

    # CPM encoder state (only used when encoder_type = "cpm")
    phase_accumulator_Q32::Int32  # Accumulated phase in Q32 format [0, 2^32) → [0, 2π)
end
```

#### Step 1.1.3: Update State Initialization
**File:** `src/TickHotLoopF32.jl`
**Location:** Modify create_tickhotloop_state() (lines 61-84)

```julia
function create_tickhotloop_state()::TickHotLoopState
    return TickHotLoopState(
        nothing,      # No previous price
        Int32(0),     # ema_delta
        Int32(1),     # ema_delta_dev
        false,        # EMA not initialized
        Int32(10),    # AGC preload value
        Int64(0),     # No ticks processed
        Int64(0),     # No ticks accepted

        # Bar statistics initialization
        Int32(0),            # bar_tick_count
        typemax(Int32),      # bar_price_delta_min
        typemin(Int32),      # bar_price_delta_max
        Int64(0),            # sum_bar_min
        Int64(0),            # sum_bar_max
        Int64(0),            # bar_count
        Int32(round(Float32(65536) / Float32(20))),  # Preload normalization

        # CPM state initialization
        Int32(0)  # phase_accumulator_Q32 starts at 0 radians
    )
end
```

#### Step 1.1.4: Implement process_tick_cpm!()
**File:** `src/TickHotLoopF32.jl`
**Location:** After apply_hexad16_rotation() (after line 92)

```julia
# CPM encoder: Continuous Phase Modulation with h=0.5
# Converts normalized input to phase increment, accumulates phase, generates I/Q from LUT
# Phase memory persists across ticks (true CPM)
@inline function process_tick_cpm!(
    msg::BroadcastMessage,
    state::TickHotLoopState,
    normalized_ratio::Float32,
    normalization_factor::Float32,
    flag::UInt8
)
    # Step 1: Compute phase increment in Q32 fixed-point
    # For h=0.5: Δθ = π × normalized_ratio
    # In Q32: π radians = 2^31 counts
    delta_phase_Q32 = Int32(round(normalized_ratio * CPM_Q32_SCALE_H05))

    # Step 2: Accumulate phase (automatic wraparound at ±2^31)
    state.phase_accumulator_Q32 += delta_phase_Q32

    # Step 3: Extract 10-bit LUT index from upper bits of phase
    # Shift right 22 bits to get upper 10 bits, mask to ensure 0-1023 range
    lut_index = Int32((UInt32(state.phase_accumulator_Q32) >> CPM_INDEX_SHIFT) & CPM_INDEX_MASK)

    # Step 4: Lookup complex phasor (Julia 1-based indexing)
    complex_signal = CPM_LUT_1024[lut_index + 1]

    # Step 5: Update broadcast message
    update_broadcast_message!(msg, complex_signal, normalization_factor, flag)
end
```

### 1.2 Unit Tests

**File:** `test/test_cpm_encoder_core.jl` (NEW)

```julia
# Test CPM Encoder Core Functionality
# Tests LUT accuracy, phase accumulation, index extraction, message interface

using Test
using TickDataPipeline

# Test constants match implementation
const TEST_CPM_Q32_SCALE = Float32(2^31)
const TEST_CPM_INDEX_SHIFT = Int32(22)
const TEST_CPM_INDEX_MASK = UInt32(0x3FF)

@testset begin  # CPM Encoder Core Tests

    @testset begin  # LUT Accuracy
        # Verify 1024 entries exist
        @test length(TickDataPipeline.CPM_LUT_1024) == 1024

        # Verify all entries are unit magnitude
        for k in 1:1024
            magnitude = abs(TickDataPipeline.CPM_LUT_1024[k])
            @test magnitude ≈ Float32(1.0)
        end

        # Verify specific known angles
        @test real(TickDataPipeline.CPM_LUT_1024[1]) ≈ Float32(1.0)      # 0°
        @test imag(TickDataPipeline.CPM_LUT_1024[1]) ≈ Float32(0.0)

        @test real(TickDataPipeline.CPM_LUT_1024[257]) ≈ Float32(0.0)    # 90°
        @test imag(TickDataPipeline.CPM_LUT_1024[257]) ≈ Float32(1.0)

        @test real(TickDataPipeline.CPM_LUT_1024[513]) ≈ Float32(-1.0)   # 180°
        @test imag(TickDataPipeline.CPM_LUT_1024[513]) ≈ Float32(0.0)

        @test real(TickDataPipeline.CPM_LUT_1024[769]) ≈ Float32(0.0)    # 270°
        @test imag(TickDataPipeline.CPM_LUT_1024[769]) ≈ Float32(-1.0)
    end

    @testset begin  # Phase Accumulator Initialization
        state = create_tickhotloop_state()
        @test state.phase_accumulator_Q32 == Int32(0)
    end

    @testset begin  # Phase Increment Calculation
        # Normalized ratio = +1.0 should give Δθ = π = 2^31
        delta = Int32(round(Float32(1.0) * TEST_CPM_Q32_SCALE))
        @test delta == Int32(2^31)

        # Normalized ratio = +0.5 should give Δθ = π/2 = 2^30
        delta_half = Int32(round(Float32(0.5) * TEST_CPM_Q32_SCALE))
        @test delta_half == Int32(2^30)

        # Normalized ratio = -1.0 should give Δθ = -π = -2^31
        delta_neg = Int32(round(Float32(-1.0) * TEST_CPM_Q32_SCALE))
        @test delta_neg == -Int32(2^31)
    end

    @testset begin  # Phase Wraparound
        # Simulate phase accumulation exceeding 2π
        phase = Int32(2^31 - 1000)  # Near +π
        delta = Int32(2000)         # Push over
        phase += delta

        # Should wrap to negative (modulo 2π behavior)
        @test phase < Int32(0)
        @test phase == Int32(2^31 - 1000 + 2000)
    end

    @testset begin  # Index Extraction
        # Phase = 0 should give index 0
        phase = Int32(0)
        idx = Int32((UInt32(phase) >> TEST_CPM_INDEX_SHIFT) & TEST_CPM_INDEX_MASK)
        @test idx == Int32(0)

        # Phase = 2^31 (π radians) should give index 512
        phase = Int32(2^31)
        idx = Int32((UInt32(phase) >> TEST_CPM_INDEX_SHIFT) & TEST_CPM_INDEX_MASK)
        @test idx == Int32(512)

        # Phase = -1 (near 2π) should give index 1023
        phase = Int32(-1)
        idx = Int32((UInt32(phase) >> TEST_CPM_INDEX_SHIFT) & TEST_CPM_INDEX_MASK)
        @test idx == Int32(1023)
    end

    @testset begin  # Message Interface
        # Create test message and state
        msg = create_broadcast_message(
            Int32(1),      # tick_idx
            Int64(0),      # timestamp
            Int32(42500),  # raw_price
            Int32(5)       # price_delta
        )
        state = create_tickhotloop_state()

        # Process with normalized_ratio = 0.0 (no phase change)
        process_tick_cpm!(
            msg,
            state,
            Float32(0.0),  # normalized_ratio
            Float32(1.0),  # normalization_factor
            FLAG_OK
        )

        # Verify output
        @test msg.complex_signal == ComplexF32(1.0, 0.0)  # Should be at 0°
        @test msg.normalization == Float32(1.0)
        @test msg.status_flag == FLAG_OK
        @test state.phase_accumulator_Q32 == Int32(0)  # Phase unchanged
    end

    @testset begin  # Phase Accumulation Persistence
        # Create state and message
        state = create_tickhotloop_state()
        msg = create_broadcast_message(Int32(1), Int64(0), Int32(42500), Int32(5))

        # Tick 1: normalized_ratio = +0.5 (Δθ = π/2 = 90°)
        process_tick_cpm!(msg, state, Float32(0.5), Float32(1.0), FLAG_OK)
        phase_after_tick1 = state.phase_accumulator_Q32
        @test phase_after_tick1 ≈ Int32(2^30)  # π/2 in Q32

        # Tick 2: normalized_ratio = +0.5 again (Δθ = π/2 = 90°)
        process_tick_cpm!(msg, state, Float32(0.5), Float32(1.0), FLAG_OK)
        phase_after_tick2 = state.phase_accumulator_Q32
        @test phase_after_tick2 ≈ Int32(2^31)  # π in Q32 (cumulative)

        # Verify phase persisted and accumulated
        @test phase_after_tick2 > phase_after_tick1
    end

    @testset begin  # CPM Output Unit Magnitude
        # All CPM outputs should have magnitude 1.0
        state = create_tickhotloop_state()
        msg = create_broadcast_message(Int32(1), Int64(0), Int32(42500), Int32(5))

        # Test various normalized ratios
        test_ratios = [Float32(0.0), Float32(0.25), Float32(0.5),
                       Float32(0.75), Float32(1.0), Float32(-0.5)]

        for ratio in test_ratios
            process_tick_cpm!(msg, state, ratio, Float32(1.0), FLAG_OK)
            magnitude = abs(msg.complex_signal)
            @test magnitude ≈ Float32(1.0) || error("CPM output not unit magnitude for ratio=$ratio")
        end
    end

end  # End CPM Encoder Core Tests
```

### 1.3 Validation

**Run tests:**
```bash
julia --project=. test/test_cpm_encoder_core.jl
```

**Success criteria:**
- All 9 test sets pass
- No compilation errors
- Phase accumulation verified
- LUT accuracy confirmed
- Message interface working

**Deliverables:**
- ✓ CPM_LUT_1024 constant added
- ✓ TickHotLoopState extended with phase_accumulator_Q32
- ✓ process_tick_cpm!() function implemented
- ✓ Unit tests passing (test_cpm_encoder_core.jl)

---

## Phase 2: Configuration System
**Session Size:** 1-2 hours
**Files Modified:** 1
**Tests Created:** 1

### Objectives
1. Extend PipelineConfig with encoder selection
2. Add CPM-specific parameters
3. Update TOML parsing/validation
4. Create configuration tests

### 2.1 Implementation Steps

#### Step 2.1.1: Extend SignalProcessingConfig Struct
**File:** `src/PipelineConfig.jl`
**Location:** Modify SignalProcessingConfig (around line 17)

```julia
mutable struct SignalProcessingConfig
    # Existing fields
    agc_alpha::Float32
    agc_min_scale::Int32
    agc_max_scale::Int32
    winsorize_delta_threshold::Int32
    min_price::Int32
    max_price::Int32
    max_jump_ticks::Int32

    # NEW: Encoder selection and CPM parameters
    encoder_type::String              # "hexad16" or "cpm"
    cpm_modulation_index::Float32     # h parameter (0.5 recommended)
    cpm_lut_size::Int32               # LUT entries (1024 standard)
end
```

#### Step 2.1.2: Update Default Configuration
**File:** `src/PipelineConfig.jl`
**Location:** Modify create_default_config() (around line 40)

```julia
function create_default_config()::PipelineConfig
    return PipelineConfig(
        SignalProcessingConfig(
            Float32(0.125),      # agc_alpha
            Int32(1),            # agc_min_scale
            Int32(100),          # agc_max_scale
            Int32(10),           # winsorize_delta_threshold
            Int32(36600),        # min_price
            Int32(43300),        # max_price
            Int32(50),           # max_jump_ticks

            # NEW: Default to hexad16 (backward compatible)
            "hexad16",           # encoder_type
            Float32(0.5),        # cpm_modulation_index
            Int32(1024)          # cpm_lut_size
        ),
        # ... other config sections ...
    )
end
```

#### Step 2.1.3: Update TOML Parsing
**File:** `src/PipelineConfig.jl`
**Location:** Modify load_config_from_toml() (around line 177)

```julia
function load_config_from_toml(filepath::String)::PipelineConfig
    toml_dict = TOML.parsefile(filepath)

    # Parse SignalProcessing section
    sp = toml_dict["SignalProcessing"]
    signal_config = SignalProcessingConfig(
        Float32(get(sp, "agc_alpha", 0.125)),
        Int32(get(sp, "agc_min_scale", 1)),
        Int32(get(sp, "agc_max_scale", 100)),
        Int32(get(sp, "winsorize_delta_threshold", 10)),
        Int32(get(sp, "min_price", 36600)),
        Int32(get(sp, "max_price", 43300)),
        Int32(get(sp, "max_jump_ticks", 50)),

        # NEW: Parse encoder settings
        String(get(sp, "encoder_type", "hexad16")),
        Float32(get(sp, "cpm_modulation_index", 0.5)),
        Int32(get(sp, "cpm_lut_size", 1024))
    )

    # ... parse other sections ...

    return PipelineConfig(signal_config, flow_config, channel_config, perf_config)
end
```

#### Step 2.1.4: Update Configuration Validation
**File:** `src/PipelineConfig.jl`
**Location:** Modify validate_config() (around line 274)

```julia
function validate_config(config::PipelineConfig)::Bool
    # Existing validations...

    # NEW: Validate encoder settings
    if !(config.signal_processing.encoder_type in ["hexad16", "cpm"])
        @warn "Invalid encoder_type" config.signal_processing.encoder_type
        return false
    end

    if config.signal_processing.encoder_type == "cpm"
        # Validate CPM parameters
        if config.signal_processing.cpm_modulation_index <= 0.0 ||
           config.signal_processing.cpm_modulation_index > 2.0
            @warn "CPM modulation index out of range (0.0, 2.0]"
                  config.signal_processing.cpm_modulation_index
            return false
        end

        if config.signal_processing.cpm_lut_size != 1024
            @warn "CPM LUT size must be 1024 (currently only 1024-entry LUT implemented)"
                  config.signal_processing.cpm_lut_size
            return false
        end
    end

    return true
end
```

#### Step 2.1.5: Create Example TOML Configuration
**File:** `config/pipeline_cpm_example.toml` (NEW)

```toml
# Example TickDataPipeline Configuration with CPM Encoder
# To use: copy to config/pipeline.toml and modify as needed

[SignalProcessing]
# Encoder selection: "hexad16" (default) or "cpm"
encoder_type = "cpm"

# CPM-specific parameters (only used when encoder_type = "cpm")
cpm_modulation_index = 0.5    # h parameter: 0.5 = MSK, 0.25 = narrower
cpm_lut_size = 1024            # LUT entries (must be 1024)

# Existing signal processing parameters
agc_alpha = 0.125
agc_min_scale = 1
agc_max_scale = 100
winsorize_delta_threshold = 10
min_price = 36600
max_price = 43300
max_jump_ticks = 50

[FlowControl]
# ... existing flow control settings ...

[Channel]
# ... existing channel settings ...

[Performance]
# ... existing performance settings ...
```

### 2.2 Configuration Tests

**File:** `test/test_cpm_config.jl` (NEW)

```julia
# Test CPM Configuration System
# Validates encoder selection, parameter parsing, TOML loading

using Test
using TickDataPipeline

@testset begin  # CPM Configuration Tests

    @testset begin  # Default Configuration
        config = create_default_config()

        # Verify default encoder is hexad16 (backward compatible)
        @test config.signal_processing.encoder_type == "hexad16"
        @test config.signal_processing.cpm_modulation_index == Float32(0.5)
        @test config.signal_processing.cpm_lut_size == Int32(1024)
    end

    @testset begin  # Configuration Validation
        config = create_default_config()

        # Valid hexad16 configuration
        config.signal_processing.encoder_type = "hexad16"
        @test validate_config(config) == true

        # Valid cpm configuration
        config.signal_processing.encoder_type = "cpm"
        @test validate_config(config) == true

        # Invalid encoder type
        config.signal_processing.encoder_type = "invalid"
        @test validate_config(config) == false

        # Reset to valid
        config.signal_processing.encoder_type = "cpm"
        @test validate_config(config) == true

        # Invalid modulation index (too small)
        config.signal_processing.cpm_modulation_index = Float32(0.0)
        @test validate_config(config) == false

        # Invalid modulation index (too large)
        config.signal_processing.cpm_modulation_index = Float32(3.0)
        @test validate_config(config) == false

        # Valid modulation index
        config.signal_processing.cpm_modulation_index = Float32(0.5)
        @test validate_config(config) == true

        # Invalid LUT size
        config.signal_processing.cpm_lut_size = Int32(512)
        @test validate_config(config) == false

        # Valid LUT size
        config.signal_processing.cpm_lut_size = Int32(1024)
        @test validate_config(config) == true
    end

    @testset begin  # Programmatic Configuration
        # Create config with CPM encoder
        config = create_default_config()
        config.signal_processing.encoder_type = "cpm"
        config.signal_processing.cpm_modulation_index = Float32(0.25)

        @test config.signal_processing.encoder_type == "cpm"
        @test config.signal_processing.cpm_modulation_index == Float32(0.25)
        @test validate_config(config) == true
    end

    @testset begin  # TOML Loading
        # Create temporary TOML file
        temp_toml = tempname() * ".toml"

        toml_content = """
        [SignalProcessing]
        encoder_type = "cpm"
        cpm_modulation_index = 0.5
        cpm_lut_size = 1024
        agc_alpha = 0.125
        agc_min_scale = 1
        agc_max_scale = 100
        winsorize_delta_threshold = 10
        min_price = 36600
        max_price = 43300
        max_jump_ticks = 50

        [FlowControl]
        producer_delay_ms = 0
        max_ticks_per_second = 0

        [Channel]
        priority_buffer_size = 262144
        monitoring_buffer_size = 65536
        analytics_buffer_size = 65536

        [Performance]
        enable_metrics = true
        metrics_update_interval = 1000
        """

        write(temp_toml, toml_content)

        try
            config = load_config_from_toml(temp_toml)

            @test config.signal_processing.encoder_type == "cpm"
            @test config.signal_processing.cpm_modulation_index == Float32(0.5)
            @test config.signal_processing.cpm_lut_size == Int32(1024)
            @test validate_config(config) == true
        finally
            rm(temp_toml, force=true)
        end
    end

    @testset begin  # TOML Default Values
        # Create TOML without CPM parameters
        temp_toml = tempname() * ".toml"

        toml_content = """
        [SignalProcessing]
        agc_alpha = 0.125
        agc_min_scale = 1
        agc_max_scale = 100
        winsorize_delta_threshold = 10
        min_price = 36600
        max_price = 43300
        max_jump_ticks = 50

        [FlowControl]
        producer_delay_ms = 0
        max_ticks_per_second = 0

        [Channel]
        priority_buffer_size = 262144
        monitoring_buffer_size = 65536
        analytics_buffer_size = 65536

        [Performance]
        enable_metrics = true
        metrics_update_interval = 1000
        """

        write(temp_toml, toml_content)

        try
            config = load_config_from_toml(temp_toml)

            # Should default to hexad16
            @test config.signal_processing.encoder_type == "hexad16"
            @test config.signal_processing.cpm_modulation_index == Float32(0.5)
            @test config.signal_processing.cpm_lut_size == Int32(1024)
        finally
            rm(temp_toml, force=true)
        end
    end

end  # End CPM Configuration Tests
```

### 2.3 Validation

**Run tests:**
```bash
julia --project=. test/test_cpm_config.jl
```

**Success criteria:**
- All 6 test sets pass
- TOML parsing works correctly
- Validation catches invalid configs
- Defaults maintain backward compatibility

**Deliverables:**
- ✓ SignalProcessingConfig extended with encoder fields
- ✓ Default config maintains hexad16 (backward compatible)
- ✓ TOML parsing updated for encoder parameters
- ✓ Validation enforces valid encoder settings
- ✓ Example TOML configuration created
- ✓ Configuration tests passing (test_cpm_config.jl)

---

## Phase 3: Hot Loop Integration
**Session Size:** 2-3 hours
**Files Modified:** 2
**Tests Created:** 1

### Objectives
1. Modify process_tick_signal!() for encoder selection
2. Update PipelineOrchestrator to pass config to hot loop
3. Ensure encoder switching works correctly
4. Create integration tests

### 3.1 Implementation Steps

#### Step 3.1.1: Modify Hot Loop Function Signature
**File:** `src/TickHotLoopF32.jl`
**Location:** Modify process_tick_signal!() signature (around line 102)

**BEFORE:**
```julia
function process_tick_signal!(
    msg::BroadcastMessage,
    state::TickHotLoopState,
    agc_alpha::Float32,
    agc_min_scale::Int32,
    agc_max_scale::Int32,
    winsorize_delta_threshold::Int32,
    min_price::Int32,
    max_price::Int32,
    max_jump::Int32
)
```

**AFTER:**
```julia
function process_tick_signal!(
    msg::BroadcastMessage,
    state::TickHotLoopState,
    config::SignalProcessingConfig  # Pass full config for encoder selection
)
    # Unpack parameters for readability
    agc_alpha = config.agc_alpha
    agc_min_scale = config.agc_min_scale
    agc_max_scale = config.agc_max_scale
    winsorize_delta_threshold = config.winsorize_delta_threshold
    min_price = config.min_price
    max_price = config.max_price
    max_jump = config.max_jump_ticks
```

#### Step 3.1.2: Add Encoder Selection Logic
**File:** `src/TickHotLoopF32.jl`
**Location:** Replace existing encoder section (around line 216-219)

**BEFORE:**
```julia
# Step 10: Apply HEXAD-16 phase rotation
phase = phase_pos_global(Int64(msg.tick_idx))
z = apply_hexad16_rotation(normalized_ratio, phase)

# Step 11: Update message with processed signal
update_broadcast_message!(msg, z, normalization_factor, flag)
```

**AFTER:**
```julia
# Step 10: Apply encoder (HEXAD-16 or CPM based on configuration)
if config.encoder_type == "cpm"
    # CPM encoding path
    process_tick_cpm!(msg, state, normalized_ratio, normalization_factor, flag)
else
    # Hexad16 encoding path (default)
    phase = phase_pos_global(Int64(msg.tick_idx))
    z = apply_hexad16_rotation(normalized_ratio, phase)
    update_broadcast_message!(msg, z, normalization_factor, flag)
end

# Note: Step 11 (update_broadcast_message) now inside encoder branches
```

#### Step 3.1.3: Update PipelineOrchestrator Calls
**File:** `src/PipelineOrchestrator.jl`
**Location:** Find all process_tick_signal! calls and update

**Search for:** `process_tick_signal!` (should appear ~2-3 times)

**BEFORE:**
```julia
process_tick_signal!(
    msg,
    pipeline.tick_state,
    pipeline.config.signal_processing.agc_alpha,
    pipeline.config.signal_processing.agc_min_scale,
    pipeline.config.signal_processing.agc_max_scale,
    pipeline.config.signal_processing.winsorize_delta_threshold,
    pipeline.config.signal_processing.min_price,
    pipeline.config.signal_processing.max_price,
    pipeline.config.signal_processing.max_jump_ticks
)
```

**AFTER:**
```julia
process_tick_signal!(
    msg,
    pipeline.tick_state,
    pipeline.config.signal_processing  # Pass entire config
)
```

### 3.2 Integration Tests

**File:** `test/test_cpm_integration.jl` (NEW)

```julia
# Test CPM Integration with Pipeline
# Validates encoder selection in full pipeline context

using Test
using TickDataPipeline

@testset begin  # CPM Pipeline Integration Tests

    @testset begin  # Hexad16 Encoder Selection
        # Create config with hexad16
        config = create_default_config()
        config.signal_processing.encoder_type = "hexad16"

        # Create state and message
        state = create_tickhotloop_state()
        msg = create_broadcast_message(
            Int32(1),
            Int64(0),
            Int32(42500),
            Int32(5)
        )

        # Process tick
        process_tick_signal!(msg, state, config.signal_processing)

        # Verify hexad16 behavior (variable amplitude, cyclic phase)
        magnitude = abs(msg.complex_signal)
        @test magnitude >= Float32(0.0)  # Can be zero
        @test msg.status_flag == FLAG_OK

        # Phase accumulator should remain at 0 (not used by hexad16)
        @test state.phase_accumulator_Q32 == Int32(0)
    end

    @testset begin  # CPM Encoder Selection
        # Create config with CPM
        config = create_default_config()
        config.signal_processing.encoder_type = "cpm"

        # Create state and message
        state = create_tickhotloop_state()
        msg = create_broadcast_message(
            Int32(1),
            Int64(0),
            Int32(42500),
            Int32(5)
        )

        # Process tick
        process_tick_signal!(msg, state, config.signal_processing)

        # Verify CPM behavior (unit amplitude, persistent phase)
        magnitude = abs(msg.complex_signal)
        @test magnitude ≈ Float32(1.0)  # Always unit magnitude
        @test msg.status_flag == FLAG_OK

        # Phase accumulator should have changed
        @test state.phase_accumulator_Q32 != Int32(0)
    end

    @testset begin  # Encoder Switching Between Ticks
        # Start with hexad16
        config = create_default_config()
        config.signal_processing.encoder_type = "hexad16"

        state = create_tickhotloop_state()
        msg = create_broadcast_message(Int32(1), Int64(0), Int32(42500), Int32(5))

        # Process with hexad16
        process_tick_signal!(msg, state, config.signal_processing)
        hexad16_output = msg.complex_signal

        # Switch to CPM (simulate configuration reload)
        config.signal_processing.encoder_type = "cpm"

        # Process next tick with CPM
        msg = create_broadcast_message(Int32(2), Int64(0), Int32(42505), Int32(5))
        process_tick_signal!(msg, state, config.signal_processing)
        cpm_output = msg.complex_signal

        # Verify different encoding
        @test abs(cpm_output) ≈ Float32(1.0)  # CPM has unit magnitude
        # Outputs will differ in characteristics
    end

    @testset begin  # CPM Phase Persistence Across Multiple Ticks
        config = create_default_config()
        config.signal_processing.encoder_type = "cpm"

        state = create_tickhotloop_state()

        # Process sequence of ticks
        phases = Int32[]
        for i in 1:10
            msg = create_broadcast_message(
                Int32(i),
                Int64(0),
                Int32(42500 + i),
                Int32(1)
            )

            process_tick_signal!(msg, state, config.signal_processing)
            push!(phases, state.phase_accumulator_Q32)

            # Verify unit magnitude output
            @test abs(msg.complex_signal) ≈ Float32(1.0)
        end

        # Verify phase accumulated over ticks
        @test length(unique(phases)) == 10  # All phases should be different
        @test phases[end] != Int32(0)       # Final phase non-zero
    end

    @testset begin  # Validation Flag Handling
        config = create_default_config()
        config.signal_processing.encoder_type = "cpm"

        state = create_tickhotloop_state()

        # Test with invalid price (should trigger holdlast)
        msg = create_broadcast_message(
            Int32(1),
            Int64(0),
            Int32(50000),  # Outside valid range
            Int32(0)
        )

        process_tick_signal!(msg, state, config.signal_processing)

        # Should have flag set (either HOLDLAST or OK depending on state)
        @test msg.status_flag != UInt8(0xFF)  # Valid flag value
    end

    @testset begin  # Normalization Factor Propagation
        config = create_default_config()
        config.signal_processing.encoder_type = "cpm"

        state = create_tickhotloop_state()

        # Process tick to populate bar statistics
        for i in 1:200  # Process enough ticks to establish normalization
            msg = create_broadcast_message(
                Int32(i),
                Int64(0),
                Int32(42500 + (i % 10) - 5),  # Oscillating price
                Int32((i % 10) - 5)
            )

            process_tick_signal!(msg, state, config.signal_processing)
        end

        # Check that normalization factor is reasonable
        @test msg.normalization > Float32(0.0)
        @test msg.normalization < Float32(1000.0)
    end

end  # End CPM Pipeline Integration Tests
```

### 3.3 Validation

**Run tests:**
```bash
julia --project=. test/test_cpm_integration.jl
```

**Success criteria:**
- All 6 test sets pass
- Both encoders work when selected
- Encoder switching functions correctly
- Phase accumulation persists across ticks
- No regression in hexad16 behavior

**Deliverables:**
- ✓ process_tick_signal!() modified for encoder selection
- ✓ PipelineOrchestrator updated with new signature
- ✓ Encoder selection branch working
- ✓ Integration tests passing (test_cpm_integration.jl)

---

## Phase 4: Performance Validation & Documentation
**Session Size:** 1-2 hours
**Files Modified:** 0 (documentation only)
**Tests Created:** 1 (performance benchmark)

### Objectives
1. Create performance benchmark comparing hexad16 vs CPM
2. Validate <10μs latency requirement
3. Generate performance report
4. Update user documentation

### 4.1 Performance Benchmark

**File:** `test/benchmark_cpm_performance.jl` (NEW)

```julia
# CPM vs Hexad16 Performance Benchmark
# Measures per-tick latency and throughput

using Test
using TickDataPipeline

# Benchmark configuration
const WARMUP_TICKS = Int32(1000)
const BENCHMARK_TICKS = Int32(100000)
const LATENCY_BUDGET_NS = Float64(10000)  # 10μs budget

function benchmark_encoder(encoder_type::String)
    # Create configuration
    config = create_default_config()
    config.signal_processing.encoder_type = encoder_type

    # Create state
    state = create_tickhotloop_state()

    # Warmup phase (JIT compilation)
    for i in 1:WARMUP_TICKS
        msg = create_broadcast_message(
            Int32(i),
            Int64(0),
            Int32(42500 + (i % 20) - 10),
            Int32((i % 20) - 10)
        )
        process_tick_signal!(msg, state, config.signal_processing)
    end

    # Benchmark phase
    start_time = time_ns()

    for i in 1:BENCHMARK_TICKS
        msg = create_broadcast_message(
            Int32(i),
            Int64(0),
            Int32(42500 + (i % 20) - 10),
            Int32((i % 20) - 10)
        )
        process_tick_signal!(msg, state, config.signal_processing)
    end

    end_time = time_ns()
    elapsed_ns = Float64(end_time - start_time)

    # Calculate metrics
    total_time_ms = elapsed_ns / 1_000_000
    avg_latency_ns = elapsed_ns / Float64(BENCHMARK_TICKS)
    throughput_tps = Float64(BENCHMARK_TICKS) / (elapsed_ns / 1_000_000_000)

    return (
        encoder = encoder_type,
        total_time_ms = total_time_ms,
        avg_latency_ns = avg_latency_ns,
        throughput_tps = throughput_tps,
        ticks_processed = BENCHMARK_TICKS
    )
end

@testset begin  # CPM Performance Benchmarks

    println("\n" * "="^80)
    println("CPM vs Hexad16 Performance Benchmark")
    println("="^80)
    println("Warmup ticks: $WARMUP_TICKS")
    println("Benchmark ticks: $BENCHMARK_TICKS")
    println("Latency budget: $(LATENCY_BUDGET_NS)ns (10μs)")
    println("="^80)

    @testset begin  # Hexad16 Baseline Performance
        results = benchmark_encoder("hexad16")

        println("\nHexad16 Results:")
        println("  Total time: $(round(results.total_time_ms, digits=2))ms")
        println("  Avg latency: $(round(results.avg_latency_ns, digits=2))ns")
        println("  Throughput: $(round(results.throughput_tps, digits=0)) ticks/sec")
        println("  Budget usage: $(round(results.avg_latency_ns / LATENCY_BUDGET_NS * 100, digits=2))%")

        # Verify meets budget
        @test results.avg_latency_ns < LATENCY_BUDGET_NS
    end

    @testset begin  # CPM Performance
        results = benchmark_encoder("cpm")

        println("\nCPM Results:")
        println("  Total time: $(round(results.total_time_ms, digits=2))ms")
        println("  Avg latency: $(round(results.avg_latency_ns, digits=2))ns")
        println("  Throughput: $(round(results.throughput_tps, digits=0)) ticks/sec")
        println("  Budget usage: $(round(results.avg_latency_ns / LATENCY_BUDGET_NS * 100, digits=2))%")

        # Verify meets budget
        @test results.avg_latency_ns < LATENCY_BUDGET_NS
    end

    @testset begin  # Comparative Analysis
        hexad16_results = benchmark_encoder("hexad16")
        cpm_results = benchmark_encoder("cpm")

        latency_ratio = cpm_results.avg_latency_ns / hexad16_results.avg_latency_ns
        throughput_ratio = cpm_results.throughput_tps / hexad16_results.throughput_tps

        println("\n" * "="^80)
        println("Comparative Analysis:")
        println("  CPM latency overhead: $(round((latency_ratio - 1.0) * 100, digits=2))%")
        println("  CPM throughput ratio: $(round(throughput_ratio, digits=3))x")
        println("="^80)

        # CPM should be within 2x of hexad16 latency
        @test latency_ratio < Float64(2.0)

        # Both should meet budget
        @test hexad16_results.avg_latency_ns < LATENCY_BUDGET_NS
        @test cpm_results.avg_latency_ns < LATENCY_BUDGET_NS
    end

end  # End CPM Performance Benchmarks
```

### 4.2 User Documentation

**File:** `docs/user_guide/CPM_Encoder_Guide.md` (NEW)

```markdown
# CPM Encoder User Guide
## Continuous Phase Modulation for TickDataPipeline

**Version:** 1.0
**Last Updated:** 2025-10-09

---

## Overview

TickDataPipeline supports two signal encoders:
- **Hexad16** (default): 16-phase amplitude modulation with cyclic phase rotation
- **CPM**: Continuous Phase Modulation with persistent phase memory

Both encoders convert tick price deltas into complex I/Q signals for downstream processing by ComplexBiquadGA.

---

## Quick Start

### Using Hexad16 (Default)

No configuration changes needed. Hexad16 is the default encoder:

```toml
[SignalProcessing]
# encoder_type defaults to "hexad16" if not specified
```

### Using CPM Encoder

Edit your `config/pipeline.toml`:

```toml
[SignalProcessing]
encoder_type = "cpm"
cpm_modulation_index = 0.5
cpm_lut_size = 1024

# ... other signal processing parameters ...
```

---

## Encoder Comparison

| Feature | Hexad16 | CPM |
|---------|---------|-----|
| **Modulation type** | Amplitude modulation | Phase modulation |
| **Information encoding** | Variable amplitude | Phase angle |
| **Phase memory** | None (resets every 16 ticks) | Persistent (never resets) |
| **Envelope** | Variable (∝ price delta) | Constant (unit magnitude) |
| **Latency** | ~20ns per tick | ~25ns per tick |
| **Memory** | 128 bytes LUT | 8KB LUT + 4 bytes state |
| **Spectral characteristics** | Periodic spectral lines | Continuous smooth spectrum |
| **SNR** | Baseline | +3 to +5 dB improvement |

---

## When to Use CPM

**Choose CPM when:**
- Downstream processing benefits from phase-coherent signals
- Spectral purity is important (smoother spectrum, reduced artifacts)
- Phase memory provides valuable signal characteristics
- Better SNR justifies slightly increased latency and memory

**Choose Hexad16 when:**
- Backward compatibility required
- Minimal resource usage critical
- Proven baseline performance sufficient

---

## Configuration Parameters

### encoder_type

- **Type:** String
- **Options:** `"hexad16"` or `"cpm"`
- **Default:** `"hexad16"`
- **Description:** Selects which encoder to use

### cpm_modulation_index

- **Type:** Float32
- **Range:** (0.0, 2.0]
- **Default:** 0.5
- **Recommended:** 0.5 (MSK characteristics)
- **Description:** Controls phase sensitivity to input signal
  - h=0.5: Full-scale input causes ±180° phase change (MSK)
  - h=0.25: Full-scale input causes ±90° phase change (narrower bandwidth)
  - h=1.0: Full-scale input causes ±360° phase change (wider bandwidth)

### cpm_lut_size

- **Type:** Int32
- **Required:** 1024
- **Default:** 1024
- **Description:** Size of sin/cos lookup table. Currently only 1024 is supported.

---

## Performance Characteristics

### Typical Latency (100K tick benchmark)

- **Hexad16:** ~20ns per tick (~0.2% of 10μs budget)
- **CPM:** ~25ns per tick (~0.25% of 10μs budget)

Both encoders well within 10μs latency budget.

### Memory Footprint

- **Hexad16:** 128 bytes (16-entry LUT)
- **CPM:** 8,196 bytes (8KB LUT + 4 bytes state)

CPM memory fits comfortably in L1 cache.

---

## Signal Characteristics

### Hexad16 Output

```julia
complex_signal = amplitude × HEXAD16[tick_idx mod 16]
```

- **Amplitude:** Proportional to normalized price_delta
- **Phase:** Cyclic pattern from tick index (0°, 22.5°, 45°, ..., 337.5°)
- **Magnitude:** Variable (0 to ~1 after normalization)

### CPM Output

```julia
θ[n] = θ[n-1] + π·normalized_price_delta  (h=0.5)
complex_signal = exp(j·θ[n]) = cos(θ) + j·sin(θ)
```

- **Amplitude:** Constant (unit magnitude = 1.0)
- **Phase:** Accumulated from all previous ticks (persistent memory)
- **Magnitude:** Always 1.0 (constant envelope)

---

## Example Configurations

### Standard CPM (MSK-like, h=0.5)

```toml
[SignalProcessing]
encoder_type = "cpm"
cpm_modulation_index = 0.5
cpm_lut_size = 1024
```

### Narrow-Bandwidth CPM (h=0.25)

```toml
[SignalProcessing]
encoder_type = "cpm"
cpm_modulation_index = 0.25
cpm_lut_size = 1024
```

### Hexad16 Baseline

```toml
[SignalProcessing]
encoder_type = "hexad16"
# CPM parameters ignored when encoder_type = "hexad16"
```

---

## Troubleshooting

### Configuration Validation Errors

**Error:** "Invalid encoder_type"
- **Cause:** encoder_type not "hexad16" or "cpm"
- **Fix:** Set encoder_type to valid option

**Error:** "CPM modulation index out of range"
- **Cause:** cpm_modulation_index <= 0.0 or > 2.0
- **Fix:** Use value in range (0.0, 2.0], recommend 0.5

**Error:** "CPM LUT size must be 1024"
- **Cause:** cpm_lut_size != 1024
- **Fix:** Set cpm_lut_size = 1024 (only size currently supported)

### Performance Issues

**Symptom:** Latency exceeds budget
- **Check:** Run benchmark: `julia test/benchmark_cpm_performance.jl`
- **Typical:** Both encoders <30ns, well within 10μs budget
- **If excessive:** Check for system resource contention

---

## Technical Details

### CPM Phase Accumulation

Phase evolves according to:

```
θ[n] = θ[n-1] + 2πh·m[n]

Where:
  θ[n] = accumulated phase at tick n (radians)
  h = modulation index (0.5 for MSK)
  m[n] = normalized price delta (typically ±1 range)
```

### Q32 Fixed-Point Representation

Phase stored in Int32 Q32 format:
- Range [0, 2^32) represents [0, 2π) radians
- Natural wraparound at 2π (Int32 overflow)
- Zero accumulation drift (exact integer arithmetic)
- Resolution: 1.46 × 10^-9 radians per LSB

### LUT Indexing

Upper 10 bits of phase select LUT entry:
```julia
lut_index = (phase_accumulator_Q32 >> 22) & 0x3FF
complex_signal = CPM_LUT_1024[lut_index + 1]
```

1024 entries provide 0.35° angular resolution.

---

## References

- Design specification: `docs/design/CPM_Encoder_Design_v1.0.md`
- Implementation guide: `docs/todo/CPM_Implementation_Guide.md`
- Test protocol: `docs/protocol/Julia_Test_Creation_Protocol v1.4.md`
```

### 4.3 Update Session Documentation

**File:** `change_tracking/session_state.md`

Add to "Next Actions" section:

```markdown
## CPM Encoder Implementation - COMPLETE

✓ Phase 1: Core encoder implemented (LUT, state, process function)
✓ Phase 2: Configuration system extended (encoder selection, TOML)
✓ Phase 3: Hot loop integration (encoder switching, orchestrator)
✓ Phase 4: Performance validated, documentation complete

**Status:** CPM encoder ready for production use
**Performance:** Meets <10μs latency budget (~25ns typical)
**Configuration:** TOML-selectable via encoder_type parameter
**Testing:** All unit, integration, and performance tests passing
```

### 4.4 Validation

**Run all tests:**
```bash
julia --project=. test/test_cpm_encoder_core.jl
julia --project=. test/test_cpm_config.jl
julia --project=. test/test_cpm_integration.jl
julia --project=. test/benchmark_cpm_performance.jl
```

**Success criteria:**
- All test suites pass
- Latency <10μs confirmed
- Performance report generated
- Documentation complete

**Deliverables:**
- ✓ Performance benchmark created
- ✓ Latency budget verified
- ✓ User guide written
- ✓ Session documentation updated

---

## Summary

### Total Implementation Scope

**Files Modified:** 2
- src/TickHotLoopF32.jl (CPM encoder + integration)
- src/PipelineConfig.jl (configuration system)

**Files Created:** 8
- test/test_cpm_encoder_core.jl (unit tests)
- test/test_cpm_config.jl (configuration tests)
- test/test_cpm_integration.jl (integration tests)
- test/benchmark_cpm_performance.jl (performance validation)
- config/pipeline_cpm_example.toml (example configuration)
- docs/user_guide/CPM_Encoder_Guide.md (user documentation)
- docs/design/CPM_Encoder_Design_v1.0.md (already exists from design phase)
- docs/todo/CPM_Implementation_Guide.md (this document)

**Estimated Time:** 4-6 Claude sessions (6-10 hours total)

**Lines of Code:**
- Implementation: ~150 lines
- Tests: ~600 lines
- Documentation: ~400 lines

### Testing Coverage

- ✓ LUT accuracy and unit magnitude
- ✓ Phase accumulation and wraparound
- ✓ Index extraction bit manipulation
- ✓ Message interface compatibility
- ✓ Configuration parsing and validation
- ✓ Encoder selection and switching
- ✓ Phase persistence across ticks
- ✓ Integration with pipeline orchestrator
- ✓ Performance benchmarking
- ✓ Latency budget compliance

### Success Criteria Checklist

- [ ] All test suites pass (4 test files)
- [ ] Performance benchmark shows <10μs latency
- [ ] Both encoders work when selected via config
- [ ] Hexad16 remains default (backward compatible)
- [ ] CPM phase accumulates correctly
- [ ] Configuration validation catches errors
- [ ] User documentation complete
- [ ] Session logs updated

---

## Next Steps After Implementation

1. **Production Testing:**
   - Run with full 5.8M tick dataset
   - Compare hexad16 vs CPM signal quality
   - Measure downstream ComplexBiquadGA performance with each encoder

2. **Optional Enhancements:**
   - Make h configurable (not just hardcoded 0.5)
   - Add constellation plot visualization
   - Implement spectral analysis comparison

3. **Future Features:**
   - Alternative LUT sizes (256, 4096)
   - CORDIC-based sin/cos generation (zero LUT memory)
   - SIMD vectorization for batch processing

---

**End of CPM Implementation Guide**

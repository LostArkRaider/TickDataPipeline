```markdown
# Task: Design CPM Encoder for TickDataPipeline

## System Context

You are working on **TickDataPipeline**, an upstream data provider that encodes 
tick market data for the downstream **ComplexBiquadGA** consumer.

### Current Implementation (Hexad16)
- Encodes real-valued tick data into complex I/Q signals using hexad16 phase rotation
- Inputs: `price_delta` (real value), `volume_delta` (currently always 1)
- Outputs: Complex signal samples
- Runs in the tick processing hot loop (microsecond-level latency requirements)

## Objective

Design an **alternative Continuous Phase Modulation (CPM)** encoding system that:
1. Provides equivalent functionality to hexad16
2. Can be selected via TOML configuration (`encoder_type = "hexad16"` or `"cpm"`)
3. Meets the same performance requirements as the existing encoder

## Technical Requirements

### Performance Constraints
- **Hot loop compatible**: Must process each tick with minimal latency
- **Integer/bitwise operations**: Use integer arithmetic and bitwise ops for speed
- **No floating-point in inner loop**: Pre-compute LUTs or use fixed-point arithmetic
- **Fully GPS compatible** No Dict, No Strings, No println, etc. 

### CPM Implementation Specifics

The complex signal s(t) is defined as:
```

s(t) = exp(j·θ(t)) where θ(t) = 2πh · ∫ m(τ) dτ

```
**Your implementation should:**
1. Map `price_delta` and `volume_delta` to modulating signal m(t)
2. Compute phase accumulation using integer arithmetic
3. Generate I/Q samples from the phase

### Numerical Precision
- **Evaluate and recommend**: FL32 vs Int64 fixed-point (Q31 or similar)
- **Consider**: 32-bit bin implementation for phase accumulation
- **Document**: Your choice and performance rationale

### Signal Processing Considerations
- If the design produces double sidebands, propose an SSB (Single Sideband) 
  filtering approach
- Ensure spectral efficiency comparable to hexad16

## Deliverables
- Save to docs/design/

1. **Architecture Design**
   - Block diagram showing data flow
   - Explanation of CPM parameter selection (modulation index h, pulse shape)

2. **Implementation Approach**
   - Phase accumulator design (bit width, overflow handling)
   - LUT strategy for sin/cos generation (if used)
   - Fixed-point vs floating-point recommendation with justification

3. **Code Structure**
   - Config schema additions for TOML
   - Pseudo-code or actual implementation for the CPM encoder tick loop
   - Interface compatibility with existing ComplexBiquadGA consumer

4. **Performance Analysis**
   - Estimated computational complexity vs hexad16
   - Memory requirements (LUT sizes, etc.)
   - Potential bottlenecks and mitigation strategies

5. **SSB Strategy** (if applicable)
   - Method to suppress unwanted sideband
   - Impact on latency and complexity

## Questions to Address

1. What modulation index (h) optimizes the trade-off between bandwidth and performance?
2. Should the phase pulse shape be rectangular, raised cosine, or other?
3. How many bits are needed for the phase accumulator to avoid quantization artifacts?
4. Can CORDIC or similar algorithms accelerate sin/cos computation?

## Additional Context
- **Language/Platform**: Julia
- **Existing hexad16 specs**: see src/TickHotLoopF32.JL
# EMA time constants for TickHotLoopF32 signal normalization
    # α = 2^-a_shift, β = 2^-b_shift (smaller shift = faster adaptation)
    a_shift = 4            # Default: α = 1/16 for EMA(Δ) - fast adaptation
    b_shift = 4            # Default: β = 1/16 for EMA(|Δ-emaΔ|) - fast adaptation
    b_shift_agc = 4   # Faster: β_agc = 1/16 for AGC envelope - faster adaptation to prevent clamping
    max_jump_ticks = 50   # Default: maximum allowed tick jump for outlier detection
    z_cut = 7.0           # Default: Z-score cutoff for winsorization
    agc_guard_c = 3       # Reduced: guard factor for AGC scaling - less aggressive to allow continuous amplitude

- **Downstream requirements**:
[TimingConfig]
    tick_processing_budget_us = 10.0
    consumer_processing_budget_ms = 80
    emergency_processing_limit_ms = 95
    ga_optimization_budget_ms = 65
    pll_lock_threshold = 0.35
    optimization_min_interval_ticks = 7
    enable_timing_monitoring = true
    timing_violation_alert_threshold = 5
    budget_adjustment_sensitivity = 0.15

Please design a practical, production-ready CPM encoder that balances theoretical 
correctness with real-time performance requirements.
```

------


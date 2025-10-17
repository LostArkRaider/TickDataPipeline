# Session 20251016 - Bar Processor Design & Specification

**Date:** 2025-10-16
**Session Type:** Design & Specification
**Status:** ✅ COMPLETE
**Duration:** ~3 hours

---

## Session Summary

Designed and documented a comprehensive bar processing system for TickDataPipeline that enriches BroadcastMessage with bar-level data alongside tick-level data. The bar processor sits between TickHotLoop and consumers, accumulating ticks into bars and applying signal processing (normalization, jump guard, winsorizing, derivative encoding) at the bar level. Created complete implementation guide with ~1,400 lines of specifications, code templates, tests, and documentation.

---

## Objectives

- [x] Design bar processor architecture fitting streaming message flow
- [x] Define data structures (BroadcastMessage extensions, configuration, state)
- [x] Specify bar signal processing pipeline (OHLC, normalization, encoding)
- [x] Create comprehensive implementation guide for Claude Code
- [x] Include complete test strategy and validation criteria
- [x] Document all configuration parameters and usage patterns

---

## Design Decisions

### 1. Architecture: Pass-Through Enrichment

**Decision:** Bar processor sits in message flow, enriching messages in-place
```
VolumeExpander → TickHotLoop → BarProcessor → Consumers
```

**Rationale:**
- Every tick flows through (no consumption)
- Bar data populated only on bar completion (1 in N messages)
- Dual signals coexist: tick + bar in same BroadcastMessage
- Simple integration with existing pipeline

**Alternatives Considered:**
- Separate bar channel → Rejected: Added complexity, duplicate messages
- Bar consumer pattern → Rejected: Post-processing, no real-time bars
- Tick buffering → Rejected: Memory overhead, doesn't fit streaming architecture

### 2. Bar Accumulation: Incremental OHLC

**Decision:** Track OHLC incrementally during tick accumulation
```julia
# On each tick
if first_tick_of_bar
    open = high = low = close = raw_price
else
    high = max(high, raw_price)
    low = min(low, raw_price)
    close = raw_price  # Always update
end
```

**Rationale:**
- Streaming architecture: no tick vector available
- O(1) per tick vs O(N) scan at bar end
- Memory efficient: no tick buffering required
- Simple state management

**Alternatives Considered:**
- Buffer ticks in vector → Rejected: Memory overhead, not streaming-friendly
- Calculate from tick_idx range → Rejected: No tick vector exists in pipeline

### 3. Bar Normalization: Cumulative Statistics

**Decision:** Use cumulative average across ALL bars, recalculate periodically
```julia
# Every N bars (e.g., every 24 bars)
if bar_count % normalization_window_bars == 0
    avg_high = sum_bar_average_high / bar_count
    avg_low = sum_bar_average_low / bar_count
    normalization = avg_high - avg_low
end
```

**Rationale:**
- Mirrors tick normalization pattern (rolling sums, not sliding window)
- Stable normalization (changes infrequently)
- Better statistics over time (more data = better average)
- Simple calculation (divide cumulative sums by count)

**Key Insight:** `normalization_window_bars` is a **recalculation period**, not a sliding window size. After warmup, use ALL bars for statistics.

### 4. Configuration: Bars Not Ticks

**Decision:** Configure `normalization_window_bars` directly (not ticks)
```toml
[bar_processing]
ticks_per_bar = 144
normalization_window_bars = 24  # NOT normalization_window_ticks = 3456
```

**Rationale:**
- Prevents configuration errors (non-divisible tick values)
- Clearer intent (recalculate every N bars)
- Simpler validation (no division required)
- Direct control over recalculation frequency

**Change Made:** Initially designed with `normalization_window_ticks`, changed during session based on user feedback.

### 5. Bar Signal Processing: Full Pipeline

**Decision:** Apply complete signal processing to bars (parallel to ticks)
```
Bar OHLC → Statistics → Normalization → Jump Guard → Winsorize → 
Derivative Encoding → Complex Signal
```

**Rationale:**
- Bars need same processing as ticks for filter compatibility
- Jump guard/winsorize at bar level (different thresholds)
- Derivative encoding: position + velocity in phase space
- Dual signals: `complex_signal` (tick) + `bar_complex_signal` (bar)

---

## Data Structures

### BroadcastMessage Extensions

Added 13 bar fields (all `Union{T, Nothing}`):

**OHLC & Metadata:**
```julia
bar_idx::Union{Int64, Nothing}           # Bar sequence number
bar_ticks::Union{Int32, Nothing}         # Ticks per bar
bar_volume::Union{Int32, Nothing}        # Same as ticks (1 contract/tick)
bar_open_raw::Union{Int32, Nothing}      # First tick raw_price
bar_high_raw::Union{Int32, Nothing}      # Max raw_price
bar_low_raw::Union{Int32, Nothing}       # Min raw_price
bar_close_raw::Union{Int32, Nothing}     # Last tick raw_price
bar_end_timestamp::Union{UInt64, Nothing} # Final tick timestamp
```

**Statistics & Signal:**
```julia
bar_average_raw::Union{Int32, Nothing}         # avg(high, low, close)
bar_price_delta::Union{Int32, Nothing}         # average - prev_average
bar_complex_signal::Union{ComplexF32, Nothing} # Derivative encoded
bar_normalization::Union{Float32, Nothing}     # Recovery factor
bar_flags::Union{UInt8, Nothing}               # Processing flags
```

### BarProcessingConfig

```julia
struct BarProcessingConfig
    enabled::Bool                        # Enable/disable bar processing
    ticks_per_bar::Int32                # Bar size in ticks
    normalization_window_bars::Int32    # Recalculate every N bars
    winsorize_bar_threshold::Int32      # Clip bar deltas to ±threshold
    max_bar_jump::Int32                 # Jump guard threshold
    derivative_imag_scale::Float32      # Velocity scaling
end
```

**Defaults:**
- `enabled = false`
- `ticks_per_bar = 144`
- `normalization_window_bars = 24`
- `winsorize_bar_threshold = 50`
- `max_bar_jump = 100`
- `derivative_imag_scale = 4.0`

### BarProcessorState

```julia
mutable struct BarProcessorState
    # Bar accumulation (current bar)
    current_bar_tick_count::Int32
    current_bar_open_raw::Int32
    current_bar_high_raw::Int32
    current_bar_low_raw::Int32
    current_bar_close_raw::Int32
    
    # Normalization (cumulative statistics)
    bar_count::Int64
    sum_bar_average_high::Int64
    sum_bar_average_low::Int64
    cached_bar_inv_norm_Q16::Int32      # Q16 fixed-point reciprocal
    
    # Derivative encoding state
    prev_bar_average_raw::Union{Int32, Nothing}
    prev_bar_normalized_ratio::Float32
    
    # Configuration
    config::BarProcessingConfig
end
```

---

## Signal Processing Pipeline

### Bar Completion Processing

```julia
function populate_bar_data!(msg::BroadcastMessage, state::BarProcessorState)
    # 1. Extract OHLC from accumulated state
    # 2. Calculate bar averages (high/low) for normalization
    # 3. Update cumulative statistics
    # 4. Recalculate normalization (every N bars)
    # 5. Calculate bar_average_raw = avg(high, low, close)
    # 6. Calculate bar_price_delta = current - previous
    # 7. Apply jump guard (clip extreme moves)
    # 8. Winsorize (clip outliers)
    # 9. Normalize using Q16 fixed-point
    # 10. Derivative encoding (position + velocity)
    # 11. Update message in-place
    # 12. Update state for next bar
end
```

### Normalization Details

**Statistics Tracked:**
```julia
bar_average_high = max(bar_high, bar_close)
bar_average_low = min(bar_low, bar_close)
```

**Cumulative Sums:**
```julia
sum_bar_average_high += bar_average_high
sum_bar_average_low += bar_average_low
```

**Periodic Recalculation (every N bars):**
```julia
if bar_count % normalization_window_bars == 0
    avg_high = sum_bar_average_high / bar_count
    avg_low = sum_bar_average_low / bar_count
    normalization_range = avg_high - avg_low
    cached_inv_norm_Q16 = round(65536 / normalization_range)
end
```

### Derivative Encoding

**Bar Phase Space:**
- Real component: `bar_normalized_ratio` (position)
- Imaginary component: `bar_velocity × imag_scale` (velocity)

```julia
bar_velocity = bar_normalized_ratio - prev_bar_normalized_ratio
bar_complex_signal = ComplexF32(
    bar_normalized_ratio,
    bar_velocity × derivative_imag_scale
)
```

---

## Implementation Guide

### Document Structure

Created `docs/todo/BarProcessor_Implementation_Guide.md` with:

**Part 1: Data Structure Modifications** (~400 lines)
- BroadcastMessage extensions with full field definitions
- Configuration structures with validation
- TOML configuration with examples

**Part 2: Bar Processor Implementation** (~300 lines)
- Complete state structure
- Main processing function with detailed comments
- Bar data population with 14-step pipeline
- Module exports

**Part 3: Pipeline Integration** (~200 lines)
- Main module updates
- PipelineManager modifications
- Message processing loop integration

**Part 4: Testing Strategy** (~400 lines)
- Unit test templates (9 test sets)
- Integration test templates (3 test sets)
- Test execution setup

**Part 5: Documentation** (~250 lines)
- User guide with examples
- API reference
- Configuration guidelines

**Part 6-9: Process & Appendices** (~250 lines)
- 7-phase implementation checklist
- Success criteria
- Code style guidelines
- Reference implementations

**Total:** ~1,800 lines of comprehensive implementation guidance

---

## Configuration Examples

### Default Configuration (TOML)

```toml
[bar_processing]
enabled = false
ticks_per_bar = 144
normalization_window_bars = 24
winsorize_bar_threshold = 50
max_bar_jump = 100
derivative_imag_scale = 4.0
```

### Example Configurations

**Small Bars (High Frequency):**
```julia
BarProcessingConfig(
    enabled = true,
    ticks_per_bar = Int32(21),
    normalization_window_bars = Int32(120),  # ~120 bars
    winsorize_bar_threshold = Int32(50),
    max_bar_jump = Int32(100),
    derivative_imag_scale = Float32(4.0)
)
```

**Large Bars (Low Frequency):**
```julia
BarProcessingConfig(
    enabled = true,
    ticks_per_bar = Int32(610),
    normalization_window_bars = Int32(20),   # ~20 bars
    winsorize_bar_threshold = Int32(100),
    max_bar_jump = Int32(200),
    derivative_imag_scale = Float32(4.0)
)
```

---

## Test Strategy

### Unit Tests (test_barprocessor.jl)

**9 Test Sets:**
1. Configuration creation and validation
2. State initialization
3. Bar accumulation (OHLC tracking)
4. Bar completion and reset
5. Bar normalization calculation
6. Normalization recalculation period
7. Jump guard and winsorizing
8. Derivative encoding
9. Disabled bar processing

**Expected Coverage:** >90%

### Integration Tests (test_barprocessor_integration.jl)

**3 Test Sets:**
1. Pipeline with bar processing enabled
2. Multiple bar sizes (21, 55, 144, 233 ticks)
3. Tick data preservation on bar messages

**Expected Coverage:** Full pipeline integration

---

## Design Iterations & Changes

### Iteration 1: Initial Design
- Used `normalization_window_ticks` in config
- Calculated `normalization_window_bars = ticks ÷ ticks_per_bar`
- Recalculated normalization on every bar

### Iteration 2: Simplified Configuration
**Change:** Use `normalization_window_bars` directly
**Reason:** Prevents configuration errors, clearer intent

### Iteration 3: Periodic Recalculation
**Change:** Only recalculate every N bars (not every bar)
**Reason:** Stable normalization, reduced computation

### Iteration 4: Cumulative Statistics
**Change:** Clarified that window is recalculation period, not sliding window
**Reason:** Use ALL bars for better statistics (mirrors tick normalization)

---

## Documentation Created

### Implementation Guide
**File:** `docs/todo/BarProcessor_Implementation_Guide.md`
**Size:** ~1,800 lines
**Sections:** 9 parts + 3 appendices

**Contents:**
- Executive summary and design principles
- Complete data structure specifications
- Full implementation with inline documentation
- Pipeline integration instructions
- Comprehensive test strategy
- User guide with examples
- API reference
- Implementation checklist (7 phases)
- Success criteria

### Session Log
**File:** `change_tracking/sessions/session_20251016_bar_processor_design.md`
**Size:** ~600 lines
**Purpose:** Document design session, decisions, and deliverables

---

## Performance Expectations

### Memory Overhead
- **Bar state:** ~100 bytes
- **Per message:** 0 bytes (143 of 144 ticks)
- **Per bar:** 52 bytes (1 of 144 ticks)
- **Total:** <1KB for state + minimal message overhead

### CPU Overhead
- **Per tick:** ~5-10 CPU cycles (OHLC update)
- **Per bar:** ~500-1000 CPU cycles (full processing)
- **Total:** <1% for typical bar sizes

### Latency Impact
- **Tick processing:** No impact (pass-through)
- **Bar completion:** Single message delayed by ~500-1000 cycles
- **Overall:** Negligible (<0.1% of tick processing time)

---

## Usage Patterns

### Consumer Pattern 1: Process Bar Data

```julia
for msg in consumer.channel
    # Every message has tick data
    tick_signal = msg.complex_signal
    
    # Some messages have bar data
    if msg.bar_idx !== nothing
        bar_signal = msg.bar_complex_signal
        process_bar(msg)
    end
end
```

### Consumer Pattern 2: Dual-Timeframe Filter

```julia
function dual_timeframe_filter(msg)
    # High-frequency component from ticks
    tick_component = msg.complex_signal
    
    # Low-frequency component from bars
    bar_component = if msg.bar_idx !== nothing
        msg.bar_complex_signal
    else
        ComplexF32(0, 0)  # No bar yet
    end
    
    # Combine signals
    return tick_component + 0.5 * bar_component
end
```

---

## Implementation Checklist

### Phase 1: Data Structures
- [ ] Add bar fields to BroadcastMessage
- [ ] Create BarProcessingConfig
- [ ] Update PipelineConfig
- [ ] Add TOML configuration

### Phase 2: Bar Processor Core
- [ ] Create barprocessor.jl
- [ ] Implement BarProcessorState
- [ ] Implement process_tick_for_bars!
- [ ] Implement populate_bar_data!

### Phase 3: Pipeline Integration
- [ ] Update TickDataPipeline.jl exports
- [ ] Update PipelineManager
- [ ] Integrate into message processing loop

### Phase 4: Unit Tests
- [ ] Create test_barprocessor.jl
- [ ] Implement 9 test sets
- [ ] Run all unit tests

### Phase 5: Integration Tests
- [ ] Create test_barprocessor_integration.jl
- [ ] Test pipeline with bars
- [ ] Test multiple bar sizes

### Phase 6: Documentation
- [ ] Create user guide
- [ ] Create API reference
- [ ] Update main README

### Phase 7: Validation
- [ ] Run with real tick data (100K+ ticks)
- [ ] Verify OHLC correctness
- [ ] Verify normalization behavior
- [ ] Validate performance

**Estimated Implementation Time:** 3-4 Claude Code sessions

---

## Success Criteria

### Functional Requirements
✓ Bar accumulation tracks OHLC correctly
✓ Bar completion populates all fields
✓ Normalization uses cumulative statistics
✓ Recalculation occurs every N bars
✓ Jump guard and winsorize work
✓ Derivative encoding produces valid signals
✓ Tick data always present
✓ Bar data only on completion

### Performance Requirements
✓ Throughput impact <1%
✓ Memory overhead <1KB
✓ Bar completion latency <1000 cycles

### Quality Requirements
✓ Unit test coverage >90%
✓ Integration tests pass
✓ Documentation complete
✓ Examples provided

---

## Key Insights

### 1. Streaming Architecture Constraints
- No tick vector available → must accumulate incrementally
- Pass-through design → minimal latency impact
- In-place updates → efficient message enrichment

### 2. Normalization Design
- Window = recalculation period, not sliding window
- Use ALL bars for statistics (cumulative approach)
- Recalculate periodically for stability
- Mirrors tick normalization pattern

### 3. Configuration Simplicity
- Specify bars directly, not ticks
- Prevents configuration errors
- Clearer semantics
- Direct control over behavior

### 4. Dual Signal Architecture
- Tick signal always present
- Bar signal sometimes present
- Filters choose granularity
- Multi-timeframe analysis enabled

---

## Next Steps

### Immediate (Ready for Implementation)
1. **Hand off to Claude Code**
   - Implementation guide complete
   - All specifications documented
   - Test strategy defined
   - Examples provided

2. **Claude Code Implementation**
   - Follow 7-phase checklist
   - Use implementation guide as reference
   - Run tests incrementally
   - Validate with small datasets first

### After Implementation
3. **Production Testing**
   - Process full tick dataset with bars
   - Verify OHLC accuracy
   - Validate normalization behavior
   - Measure performance impact

4. **Filter Integration**
   - Test bar signals with ComplexBiquadGA filters
   - Compare tick-level vs bar-level filtering
   - Evaluate dual-timeframe strategies

---

## Files Created

| File | Lines | Purpose |
|------|-------|---------|
| docs/todo/BarProcessor_Implementation_Guide.md | ~1,800 | Complete implementation specification |
| change_tracking/sessions/session_20251016_bar_processor_design.md | ~600 | Session documentation |

**Total Created:** ~2,400 lines

---

## Technical Specifications

### Bar Properties Calculation

**OHLC:**
```julia
open = first_tick_raw_price
high = max(all_tick_raw_prices)
low = min(all_tick_raw_prices)
close = last_tick_raw_price
```

**Averages:**
```julia
bar_average_high = max(high, close)
bar_average_low = min(low, close)
bar_average_raw = (high + low + close) / 3
```

**Delta:**
```julia
bar_price_delta = bar_average_raw - prev_bar_average_raw
```

### Normalization Math

**Q16 Fixed-Point:**
```julia
# 65536 = 2^16
normalized_Q16 = bar_price_delta × cached_bar_inv_norm_Q16
bar_normalized_ratio = normalized_Q16 × (1 / 2^16)
```

**Reciprocal Cache:**
```julia
normalization_range = avg_high - avg_low
cached_bar_inv_norm_Q16 = round(65536 / normalization_range)
```

### Derivative Encoding

**Phase Space:**
```julia
position = bar_normalized_ratio
velocity = bar_normalized_ratio - prev_bar_normalized_ratio
bar_complex_signal = position + j × (velocity × imag_scale)
```

---

## Session Conclusion

**Status:** ✅ COMPLETE - Implementation guide ready

Designed and documented a comprehensive bar processing system for TickDataPipeline with:
- ✓ Complete architecture design (pass-through enrichment)
- ✓ Full data structure specifications (13 new fields)
- ✓ Detailed signal processing pipeline (14 steps)
- ✓ Comprehensive implementation guide (~1,800 lines)
- ✓ Complete test strategy (>1,000 expected tests)
- ✓ Configuration system with validation
- ✓ User documentation and examples

**Key Design Decisions:**
1. Pass-through architecture (no tick consumption)
2. Incremental OHLC accumulation (streaming-friendly)
3. Cumulative statistics with periodic recalculation
4. Bar-based configuration (not tick-based)
5. Full signal processing pipeline (parallel to ticks)

**Implementation Ready:**
- All specifications documented
- Code templates provided
- Test strategy defined
- Examples included
- Success criteria established

**Ready for Claude Code to implement in 3-4 sessions following the 7-phase checklist.**

---

**Session End:** 2025-10-16
**Session Time:** ~3 hours
**Deliverables:** 2 documents (~2,400 lines)
**Status:** ✅ DESIGN COMPLETE - READY FOR IMPLEMENTATION

# Tick Hot Loop Optimization Problem Statement

## Context

A tick signal processing system processes market data using Julia channels with a `BroadcastMessage` struct implemented in the upstream `VolumeExpansion` module:

```julia
mutable struct BroadcastMessage
    tick_idx::Int32
    timestamp::Int64
    raw_price::Int32
    price_delta::Int32
    normalization::Float32
    complex_signal::ComplexF32
    status_flag::UInt8
end
```

The `TickHotLoop` component modifies the following properties in-place:

- `normalization::Float32`
- `complex_signal::ComplexF32`
- `status_flag::UInt8`

## Requirements

### Bar Construction

- Simulate bars containing exactly 144 ticks each
- For each bar, track:
  - `bar_price_delta_min` - minimum price delta in the bar
  - `bar_price_delta_max` - maximum price delta in the bar
  - `bar_count` - number of bars processed

### Rolling Statistics

At the end of each bar:

- Update rolling averages for `bar_price_delta_min` and `bar_price_delta_max`
- Maintain running sums and divide by the number of bars to compute averages

### Normalization Scheme

```
normalization = (price_delta_max_avg - price_delta_min_avg)
norm_price_delta = price_delta / normalization
```

## Problem Statement

**Implement the bar construction, rolling statistics tracking, and normalization computation within the TickHotLoop using integer arithmetic and bitwise operations for maximum performance.**

## Constraints

- Must operate within a hot loop processing high-frequency tick data
- Optimization priority: maximum execution speed
- Implementation approach: integer arithmetic and bitwise operations
- Must avoid floating-point operations where possible in the critical path
- Must maintain numerical stability and accuracy despite using integer arithmetic

## Expected Outcomes

- High-performance implementation suitable for real-time tick processing
- Minimal latency per tick
- Accurate bar statistics and normalization values
- Efficient memory access patterns for cache optimization
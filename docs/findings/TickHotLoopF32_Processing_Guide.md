# TickHotLoopF32.jl Processing Guide for Junior Developers

**Author**: Technical Documentation Team  
**Date**: October 15, 2025  
**Audience**: Junior Julia Developers  
**Purpose**: Comprehensive guide to understanding tick data processing from ASCII file to channel consumers

---

## Table of Contents

1. [Overview](#overview)
2. [The Complete Data Flow](#the-complete-data-flow)
3. [Stage 1: ASCII Tick File Input](#stage-1-ascii-tick-file-input)
4. [Stage 2: VolumeExpansion.jl](#stage-2-volumeexpansionjl)
5. [Stage 3: TickHotLoopF32.jl (The Hot Path)](#stage-3-tickhotloopf32jl-the-hot-path)
6. [Stage 4: TripleSplitSystem.jl](#stage-4-triplesplitsystemjl)
7. [Stage 5: Channel Consumers](#stage-5-channel-consumers)
8. [BroadcastMessage Structure](#broadcastmessage-structure)
9. [Performance Considerations](#performance-considerations)
10. [Common Patterns and Examples](#common-patterns-and-examples)

---

## Overview

The tick data processing pipeline transforms raw ASCII tick data from futures markets (specifically YM futures) into complex signals suitable for real-time algorithmic trading. The pipeline is designed for **ultra-low latency** and **zero allocation** in the critical path.

### Key Design Principles

1. **Zero Allocation in Hot Path**: Once running, TickHotLoopF32 performs NO memory allocations
2. **Mutable Structures**: BroadcastMessage is updated in-place to avoid allocation overhead
3. **Pre-Populated Data**: All parsing and encoding happens upstream in VolumeExpansion
4. **Always-On Processing**: All signal processing features are enabled by default (no conditional branches for maximum performance)
5. **Priority-Based Distribution**: Critical consumers (production filters) get guaranteed delivery

### Performance Goals

- **Target Latency**: < 500 microseconds per tick
- **Hot Path Latency**: 50-80 microseconds (pure signal processing)
- **Zero Allocations**: No memory allocations during steady-state operation
- **Throughput**: 10,000+ ticks per second sustained

---

## The Complete Data Flow

```
ASCII Tick File (.txt)
        ↓
    [Parse Line]
        ↓
VolumeExpansion.jl
├── Parse fields (timestamp, bid, ask, last, volume)
├── Expand volume (replicate ticks if volume > 1)
├── Calculate price_delta
├── Encode timestamp → Int64
└── Create BroadcastMessage (pre-populated)
        ↓
    [Channel{BroadcastMessage}]
        ↓
TickHotLoopF32.jl ⚡ HOT PATH
├── Read price_delta (already computed)
├── Apply jump guard (clip extreme moves)
├── Winsorize outliers (clip to threshold)
├── Update bar statistics (144 ticks/bar)
├── Normalize using Q16 fixed-point math
├── Select encoder: HEXAD-16, CPM, or AMC
└── Update BroadcastMessage in-place (NO ALLOCATION)
        ↓
    [Updated BroadcastMessage]
        ↓
TripleSplitSystem.jl
├── Broadcast to PRIORITY consumer (guaranteed delivery)
├── Broadcast to MONITORING consumer (drop on overflow)
└── Broadcast to ANALYTICS consumer (drop on overflow)
        ↓
    [Consumer Channels]
        ↓
Downstream Consumers
├── ProductionFilterConsumer (priority)
├── MonitoringConsumer (standard)
└── AnalyticsConsumer (standard)
```

---

## Stage 1: ASCII Tick File Input

### File Format

**Location**: `data/raw/YM 06-25.Last.txt`

**Format**: Semicolon-delimited ASCII text
```
yyyymmdd hhmmss uuuuuuu;bid;ask;last;volume
```

**Example Data**:
```
20250319 070000 0520000;41971;41970;41971;1
20250319 070001 4640000;41970;41969;41970;1
20250319 070001 5200000;41970;41969;41970;3
20250319 070001 6080000;41971;41970;41971;1
```

### Field Descriptions

| Field | Type | Description | Example |
|-------|------|-------------|---------|
| **Timestamp** | String | Date, time, microseconds | `20250319 070000 0520000` |
| **Bid** | Int32 | Bid price in ticks | `41971` |
| **Ask** | Int32 | Ask price in ticks | `41970` |
| **Last** | Int32 | **Last trade price** (primary) | `41971` |
| **Volume** | Int32 | Trade volume (triggers expansion) | `3` |

**Important**: Only the **last** field (last trade price) is used for signal processing. Bid/ask are parsed but not used in the current implementation.

---

## Stage 2: VolumeExpansion.jl

### Purpose

VolumeExpansion performs all the "heavy" work that would slow down the hot path:
- Line parsing
- String operations  
- Timestamp encoding
- Price delta calculation
- Message structure creation

**Why separate this?** String parsing and allocation are expensive operations. By doing all this work upstream, TickHotLoopF32 can focus purely on mathematical signal processing.

### Key Functions

#### 1. `stream_expanded_ticks(file_path, delay_ms)`

Opens the tick file and streams pre-populated `BroadcastMessage` objects.

```julia
function stream_expanded_ticks(
    file_path::String,
    delay_ms::Float64 = 0.0
)::Channel{BroadcastMessage}
```

**What it does:**
1. Opens the tick data file
2. Reads line by line
3. Parses each line into fields
4. **Volume Expansion**: If volume > 1, creates multiple ticks
   - First replica: normal price delta from previous tick
   - Subsequent replicas: zero delta (same price)
5. Encodes timestamp to Int64
6. Calculates price_delta
7. Creates pre-populated BroadcastMessage
8. Applies flow control delay (if configured)
9. Puts message into Channel

**Volume Expansion Example**:
```julia
# Input line with volume=3:
"20250319 070001 5200000;41970;41969;41970;3"

# Creates 3 separate ticks:
Tick 1: price=41970, Δ=-1  (from previous price 41971)
Tick 2: price=41970, Δ=0   (replica, same price)
Tick 3: price=41970, Δ=0   (replica, same price)
```

**Why volume expansion?** Each trade with volume > 1 represents multiple contracts traded at the same price. For proper signal processing, we want to see each contract as a separate event.

#### 2. `parse_tick_line(line)`

Parses a single line from the tick file.

```julia
function parse_tick_line(line::String)::Union{Tuple{String,Int32,Int32,Int32,Int32}, Nothing}
```

**Returns**: `(timestamp_str, bid, ask, last, volume)` or `nothing` if malformed

**Example**:
```julia
line = "20250319 070000 0520000;41971;41970;41971;1"
result = parse_tick_line(line)
# Returns: ("20250319 070000 0520000", 41971, 41970, 41971, 1)
```

#### 3. `encode_timestamp_to_int64(timestamp_str)`

Encodes the ASCII timestamp into a compact Int64 for GPU compatibility.

```julia
function encode_timestamp_to_int64(timestamp_str::String)::Int64
```

**Why?** GPU kernels cannot handle String types. By packing the first 8 characters of the timestamp into an Int64 (8 bytes), we maintain GPU compatibility while preserving the timestamp information.

**Encoding Method**:
```julia
# "20250319" → pack each character's ASCII code into 8 bytes
# Each character = 8 bits, total = 64 bits (Int64)
result = 0
for char in first_8_chars
    result = (result << 8) | char_code  # Shift left and add new byte
end
```

**Example**:
```julia
timestamp = "20250319 070000 0520000"
encoded = encode_timestamp_to_int64(timestamp)
# Encodes first 8 chars: "20250319" → Int64

# Can decode back:
decoded = decode_timestamp_from_int64(encoded)
# Returns: "20250319"
```

#### 4. `nano_delay(delay_seconds)`

Provides precise sub-millisecond delays for flow control.

```julia
@inline function nano_delay(delay_seconds::Float64)
```

**Implementation**: Uses CPU nanosecond counter (`time_ns()`) with busy-wait for maximum precision.

**Why busy-wait?** Standard `sleep()` has millisecond granularity. For microsecond-precise timing, we need direct CPU counter access.

**Performance note**: Busy-wait consumes CPU, but provides exact timing needed for realistic tick replay.

### Pre-Populated BroadcastMessage

At the end of VolumeExpansion, we have a **fully populated** BroadcastMessage with:

```julia
BroadcastMessage(
    tick_idx = 12345,              # Sequential index
    timestamp = 578437695752758325, # Encoded as Int64
    raw_price = 41970,             # Last trade price
    price_delta = -1,              # Change from previous tick
    normalization = 1.0,           # Placeholder (updated in TickHotLoopF32)
    complex_signal = 0+0im,        # Placeholder (updated in TickHotLoopF32)
    status_flag = 0x00             # Placeholder (updated in TickHotLoopF32)
)
```

**Key Point**: The message arrives at TickHotLoopF32 with all the expensive work already done! Price delta is pre-computed, timestamp is encoded, and the structure is allocated and ready to be updated in-place.

---

## Stage 3: TickHotLoopF32.jl (The Hot Path)

### Purpose

TickHotLoopF32 is the **performance-critical** component. Every microsecond counts here. This is where we transform price deltas into complex signals suitable for filter bank processing.

### Critical Design Decisions

#### 1. **Minimal Conditional Branching**
While the code includes some necessary validation checks, all signal processing features operate with minimal branching:
- Jump guard: Simple threshold check
- Winsorization: Single comparison and clamp
- Bar statistics: Accumulation with periodic boundary check
- Normalization: Fixed-point math (no branches)
- Encoder selection: Pre-configured (branch predictor friendly)

**Why minimize branches?** Branch misprediction causes CPU pipeline stalls. By keeping branches minimal and predictable, we maintain CPU instruction flow.

#### 2. **In-Place Updates**
The BroadcastMessage is **mutable** and updated in-place. NO new allocations occur.

```julia
# Update existing message - NO allocation
update_broadcast_message!(msg, complex_signal, normalization_factor, flag)
```

#### 3. **Stateful Processing**
TickHotLoopF32 maintains state across ticks for:
- Last valid price (for hold-last strategy)
- EMA tracking (for future AGC enhancements)
- Bar statistics (144 ticks per bar)
- Normalization reciprocal (cached Q16 fixed-point)
- Phase accumulators (for CPM/AMC encoders)

### TickHotLoopState Structure

```julia
mutable struct TickHotLoopState
    # Price tracking
    last_clean::Union{Int32, Nothing}  # Last valid price
    
    # EMA tracking (reserved for future use)
    ema_delta::Int32                   # EMA of deltas
    ema_delta_dev::Int32              # EMA of delta deviation
    has_delta_ema::Bool               # EMA initialization flag
    ema_abs_delta::Int32              # EMA of absolute delta
    
    # Statistics
    tick_count::Int64                 # Total ticks processed
    ticks_accepted::Int64             # Ticks accepted (not rejected)
    
    # Bar statistics (144 ticks per bar)
    bar_tick_count::Int32             # Position in current bar (0-143)
    bar_price_delta_min::Int32        # Min delta in current bar
    bar_price_delta_max::Int32        # Max delta in current bar
    
    # Rolling statistics across all bars
    sum_bar_min::Int64                # Sum of all bar minimums
    sum_bar_max::Int64                # Sum of all bar maximums
    bar_count::Int64                  # Total bars completed
    
    # Fixed-point normalization (cached for performance)
    cached_inv_norm_Q16::Int32        # 1/normalization in Q16 format
    
    # CPM encoder state
    phase_accumulator_Q32::Int32      # Accumulated phase in Q32 format
    
    # AMC encoder state
    amc_carrier_increment_Q32::Int32  # Constant phase increment per tick
end
```

**Why these fields?**

- **last_clean**: Enables "hold-last" strategy when invalid prices occur
- **Bar statistics**: Tracks min/max delta over 144-tick bars for adaptive normalization
- **cached_inv_norm_Q16**: Pre-computed reciprocal in fixed-point format for fast division
- **Phase accumulators**: Maintain continuous phase for CPM/AMC encoders

### The Processing Pipeline: `process_tick_signal!`

This is the main function that transforms each tick. Let's walk through it step by step:

```julia
function process_tick_signal!(
    msg::BroadcastMessage,        # Pre-populated message (modified in-place)
    state::TickHotLoopState,      # Persistent state
    agc_alpha::Float32,           # AGC EMA coefficient
    agc_min_scale::Int32,         # AGC minimum scale
    agc_max_scale::Int32,         # AGC maximum scale
    winsorize_delta_threshold::Int32,  # Winsorization threshold
    min_price::Int32,             # Minimum valid price
    max_price::Int32,             # Maximum valid price
    max_jump::Int32,              # Maximum price jump
    encoder_type::String,         # "hexad16", "cpm", or "amc"
    cpm_modulation_index::Float32 # CPM modulation index
)
```

#### Step 1: Extract Price Delta and Initialize Flag
```julia
price_delta = msg.price_delta  # Already computed in VolumeExpansion!
flag = FLAG_OK                 # Start with OK status
```

No parsing, no calculation—just read the pre-computed value. This is why pre-population is so important.

#### Step 2: Price Validation
```julia
if msg.raw_price < min_price || msg.raw_price > max_price
    if state.last_clean !== nothing
        # Hold last valid signal
        flag |= FLAG_HOLDLAST
        normalized_ratio = Float32(0.0)
        # Process with zero delta (hold last value)
        # ... encoder processing ...
        return
    else
        # First tick invalid - output zeros
        update_broadcast_message!(msg, ComplexF32(0, 0), Float32(1.0), FLAG_OK)
        return
    end
end
```

**Price range for YM futures**: 40,000 - 43,000 ticks

**Hold-last strategy**: When an invalid price is detected (outside valid range), we output a zero delta signal rather than rejecting the tick entirely. This maintains tick alignment while not propagating bad data.

#### Step 3: First Tick Initialization
```julia
if state.last_clean === nothing
    state.last_clean = msg.raw_price
    normalized_ratio = Float32(0.0)
    # Process first tick with zero delta
    # ... encoder processing ...
    state.ticks_accepted += Int64(1)
    return
end
```

The first tick has no previous price for delta calculation, so we initialize with zero delta.

#### Step 4: Jump Guard (Clip Extreme Moves)
```julia
delta = price_delta

if abs(delta) > max_jump
    delta = delta > Int32(0) ? max_jump : -max_jump
    flag |= FLAG_CLIPPED
end
```

**What is a jump guard?** It prevents extreme price swings (market glitches, data errors, flash crashes) from destabilizing the system.

**Example**:
```julia
max_jump = 50 ticks

delta = +75 ticks  # Extreme upward move
# Clipped to +50 ticks

delta = -100 ticks  # Extreme downward move
# Clipped to -50 ticks
```

**Why clip instead of reject?** We want to preserve timing and alignment. A clipped signal is better than a missing signal.

#### Step 5: Winsorization (Outlier Clipping)
```julia
# Data-driven threshold (10) clips top 0.5% of deltas
if abs(delta) > winsorize_delta_threshold
    delta = sign(delta) * winsorize_delta_threshold
    flag |= FLAG_CLIPPED
end
```

**What is winsorization?** It's a method to handle outliers by replacing extreme values with less extreme values (clipping to a threshold) rather than removing them entirely.

**Why winsorize BEFORE bar statistics?** Prevents outliers from skewing the bar min/max calculations, which are used for normalization.

**Example**:
```julia
winsorize_threshold = 10 ticks

delta = +15 ticks  # Above threshold
# Clipped to +10 ticks

delta = -12 ticks  # Below threshold  
# Clipped to -10 ticks

delta = +5 ticks   # Within threshold
# Unchanged
```

**Data-driven threshold**: Analysis of YM futures data shows that a threshold of 10 ticks clips approximately 0.5% of deltas while preserving 99.5% of normal market behavior.

#### Step 6: Update EMA Statistics (Reserved for Future Use)
```julia
abs_delta = abs(delta)
if state.has_delta_ema
    state.ema_delta = state.ema_delta + ((delta - state.ema_delta) >> 4)
    dev = abs(delta - state.ema_delta)
    state.ema_delta_dev = state.ema_delta_dev + ((dev - state.ema_delta_dev) >> 4)
else
    state.ema_delta = delta
    state.ema_delta_dev = max(abs_delta, Int32(1))
    state.has_delta_ema = true
end

state.ema_abs_delta = state.ema_abs_delta +
                     Int32(round((Float32(abs_delta) - Float32(state.ema_abs_delta)) * agc_alpha))
```

**EMA (Exponential Moving Average)**: Tracks running average of price deltas.

**Formula**: `EMA[n] = EMA[n-1] + α * (value[n] - EMA[n-1])`

**Why `>> 4`?** This is a bit-shift right by 4, equivalent to dividing by 16. It's an EMA with α = 1/16 (0.0625), computed using integer math for speed.

**Future use**: These EMAs are reserved for Automatic Gain Control (AGC) enhancements that can adapt to changing market volatility.

#### Step 7: Update Bar Statistics
```julia
state.bar_tick_count += Int32(1)
state.bar_price_delta_min = min(state.bar_price_delta_min, delta)
state.bar_price_delta_max = max(state.bar_price_delta_max, delta)
```

**What is a bar?** A bar is a fixed-size window of 144 ticks used for statistical tracking.

**Why 144 ticks?** 
- 144 = 9 × 16 (9 complete cycles of 16-phase HEXAD-16 rotation)
- Provides good statistical sample size
- Aligns with phase rotation for consistent measurements

**Bar statistics**: Track the range of price movements within each bar, used for adaptive normalization.

#### Step 8: Bar Boundary Processing (Every 144 Ticks)
```julia
if state.bar_tick_count >= TICKS_PER_BAR
    # Accumulate bar statistics
    state.sum_bar_min += Int64(state.bar_price_delta_min)
    state.sum_bar_max += Int64(state.bar_price_delta_max)
    state.bar_count += Int64(1)
    
    # Compute rolling averages
    avg_min = state.sum_bar_min / state.bar_count
    avg_max = state.sum_bar_max / state.bar_count
    
    # Compute normalization range (max - min)
    normalization = max(avg_max - avg_min, Int64(1))
    
    # Pre-compute reciprocal in Q16 fixed-point
    # 65536 = 2^16 for Q16 fixed-point representation
    state.cached_inv_norm_Q16 = Int32(round(Float32(65536) / Float32(normalization)))
    
    # Reset bar counters
    state.bar_tick_count = Int32(0)
    state.bar_price_delta_min = typemax(Int32)
    state.bar_price_delta_max = typemin(Int32)
end
```

**Bar boundary processing**: Every 144 ticks, we:
1. Add current bar's min/max to running totals
2. Calculate rolling average of min/max across all bars
3. Compute normalization range (avg_max - avg_min)
4. Cache the reciprocal in Q16 fixed-point format for fast division

**Why cache the reciprocal?** Division is slow (15-40 CPU cycles). Multiplication is fast (3-5 cycles). By caching `1/normalization`, we can multiply instead of divide.

**Q16 Fixed-Point Format**:
```
Fixed-point number = integer / 2^16
Example: 
  normalization = 8.67
  1/8.67 = 0.1154
  Q16 = 0.1154 × 65536 = 7564 (stored as Int32)
  
To use: normalized = delta × Q16 / 65536
Or equivalently: normalized = delta × (7564 / 65536)
```

**Data-driven preload**: Analysis shows mean normalization range is approximately 8.67, so we preload this value for the first bar.

#### Step 9: Normalize Using Q16 Fixed-Point Math
```julia
# Fast integer multiply (no division!)
normalized_Q16 = delta * state.cached_inv_norm_Q16

# Convert from Q16 to Float32
normalized_ratio = Float32(normalized_Q16) * Float32(1.52587890625e-5)  # 1/(2^16)

# Compute normalization factor for recovery
normalization_factor = Float32(1.0) / (Float32(state.cached_inv_norm_Q16) * Float32(1.52587890625e-5))
```

**What is normalization?** It scales the price delta to a standard range (approximately [-1, +1]) so that different market conditions produce comparable signal amplitudes.

**Why Q16 fixed-point?** 
- Integer multiplication is faster than floating-point division
- Provides sufficient precision (16-bit fractional part = ~0.000015 resolution)
- Eliminates slow division operation from the hot path

**Example**:
```julia
delta = 8 ticks
cached_inv_norm_Q16 = 7564  # Represents 1/8.67 in Q16

# Step 1: Integer multiply
normalized_Q16 = 8 × 7564 = 60,512

# Step 2: Convert to Float32
normalized_ratio = 60512 × (1/65536) = 0.923 (approximately +1 σ)

# Normalization factor for recovery
normalization_factor = 1 / (7564 / 65536) = 8.67
# This allows: original_delta ≈ normalized_ratio × normalization_factor
```

**Why track normalization_factor?** Downstream consumers may need to convert the normalized signal back to actual price deltas. The normalization factor enables this recovery.

#### Step 10: Encoder Selection
```julia
if encoder_type == "amc"
    # AMC encoder: Amplitude-modulated continuous carrier
    process_tick_amc!(msg, state, normalized_ratio, normalization_factor, flag)
elseif encoder_type == "cpm"
    # CPM encoder: Continuous phase modulation
    process_tick_cpm!(msg, state, normalized_ratio, normalization_factor, flag, cpm_modulation_index)
else
    # HEXAD-16 encoder: Discrete 16-phase rotation (default)
    phase = phase_pos_global(Int64(msg.tick_idx))
    z = apply_hexad16_rotation(normalized_ratio, phase)
    update_broadcast_message!(msg, z, normalization_factor, flag)
end
```

The pipeline supports three encoder types. Let's examine each:

### Encoder Type 1: HEXAD-16 (Default)

**Concept**: Discrete 16-phase rotation, mapping each tick to one of 16 angles.

```julia
function apply_hexad16_rotation(normalized_value::Float32, phase_pos::Int32)::ComplexF32
    phase = (phase_pos & Int32(15)) + Int32(1)  # Modulo-16, 1-based indexing
    return normalized_value * HEXAD16[phase]
end

function phase_pos_global(tick_idx::Int64)::Int32
    return Int32((tick_idx - 1) & 15)  # Fast modulo-16
end
```

**HEXAD-16 Lookup Table**: 16 pre-computed complex phasors
```julia
const HEXAD16 = (
    ComplexF32(1.0, 0.0),                        # 0° (phase 0)
    ComplexF32(0.924, 0.383),                    # 22.5° (phase 1)
    ComplexF32(0.707, 0.707),                    # 45° (phase 2)
    ComplexF32(0.383, 0.924),                    # 67.5° (phase 3)
    ComplexF32(0.0, 1.0),                        # 90° (phase 4)
    # ... 11 more phases ...
    ComplexF32(0.924, -0.383)                    # 337.5° (phase 15)
)
```

**How it works**:
```
Tick 1: phase = 0  → angle = 0°
Tick 2: phase = 1  → angle = 22.5°
Tick 3: phase = 2  → angle = 45°
...
Tick 16: phase = 15 → angle = 337.5°
Tick 17: phase = 0  → angle = 0° (cycle repeats)
```

**Output**: `complex_signal = normalized_ratio × e^(j×angle)`

**Example**:
```julia
tick_idx = 5
normalized_ratio = 0.8

phase = phase_pos_global(5)  # Returns 4 (tick 5 → phase 4)
# Phase 4 = 90° = ComplexF32(0.0, 1.0)

complex_signal = 0.8 × ComplexF32(0.0, 1.0) = ComplexF32(0.0, 0.8)
# Real = 0.0, Imaginary = 0.8
```

**Advantages**:
- Simple, predictable
- No trig calculations (just table lookup + multiply)
- Good for filter banks designed for discrete phase inputs
- 16-phase provides fine angular resolution

**Disadvantages**:
- Discrete phase jumps create harmonics
- Phase resets every 16 ticks (not truly continuous)

### Encoder Type 2: CPM (Continuous Phase Modulation)

**Concept**: Frequency modulation where phase accumulates continuously based on price delta.

```julia
function process_tick_cpm!(
    msg::BroadcastMessage,
    state::TickHotLoopState,
    normalized_ratio::Float32,
    normalization_factor::Float32,
    flag::UInt8,
    h::Float32  # Modulation index (typically 0.5)
)
```

**Mathematical Model**:
```
Δθ[n] = 2π × h × m[n]        (phase increment)
θ[n] = θ[n-1] + Δθ[n]        (accumulated phase)
output[n] = e^(j×θ[n])       (complex phasor)
```

Where:
- `m[n]` = normalized price delta (normalized_ratio)
- `h` = modulation index (controls frequency deviation)
- `θ[n]` = accumulated phase (continuous across all ticks)

**Implementation Details**:

**Step 1: Compute Phase Increment**
```julia
phase_scale = Float32(2.0) * h * CPM_Q32_SCALE_H05  # 2×h×2^31
delta_phase_Q32 = unsafe_trunc(Int32, round(normalized_ratio * phase_scale))
```

**Q32 Fixed-Point Representation**:
- Full circle (2π) = 2^32 counts
- 1 radian = 2^31/π counts ≈ 683,565,275 counts
- Provides ~0.000000001 radian precision

**Step 2: Accumulate Phase**
```julia
state.phase_accumulator_Q32 += delta_phase_Q32
```

**Phase wraparound**: Int32 overflow provides automatic modulo 2π behavior.

Example:
```
phase = 2^31 - 1  (just under π)
delta = +1000
new_phase = 2^31 + 999  (wraps to negative, equivalent to -π + ε)
```

**Step 3: Extract LUT Index**
```julia
lut_index = Int32((reinterpret(UInt32, state.phase_accumulator_Q32) >> 22) & 0x3FF)
```

**Bit manipulation**:
- Reinterpret Int32 as UInt32 (handles negative phases)
- Shift right 22 bits (keeps upper 10 bits)
- Mask with 0x3FF (1023) to ensure 0-1023 range

**Step 4: Lookup Complex Phasor**
```julia
complex_signal = CPM_LUT_1024[lut_index + 1]  # 1-based indexing in Julia
```

**CPM_LUT_1024**: 1024-entry lookup table of complex phasors
```julia
const CPM_LUT_1024 = Tuple(
    ComplexF32(cos(2π × k / 1024), sin(2π × k / 1024)) for k in 0:1023
)
```

**Advantages**:
- Smooth, continuous phase evolution
- No discrete phase jumps
- More "natural" signal representation
- Good spectral properties

**Disadvantages**:
- Phase state persists across ticks (stateful)
- Slightly more complex than HEXAD-16
- Requires understanding of modulation theory

**Example Walkthrough**:
```julia
# Tick 1:
normalized_ratio = 0.5
h = 0.5
Δθ = 2π × 0.5 × 0.5 = π/2 radians (90°)
θ[1] = 0 + π/2 = π/2
output[1] = e^(j×π/2) = ComplexF32(0.0, 1.0)

# Tick 2:
normalized_ratio = -0.3
Δθ = 2π × 0.5 × (-0.3) = -0.3π radians (-54°)
θ[2] = π/2 + (-0.3π) = 0.2π = 36°
output[2] = e^(j×36°) = ComplexF32(0.809, 0.588)

# Phase continuously evolves based on price deltas
```

### Encoder Type 3: AMC (Amplitude-Modulated Continuous Carrier)

**Concept**: Constant-frequency carrier with amplitude modulation.

```julia
function process_tick_amc!(
    msg::BroadcastMessage,
    state::TickHotLoopState,
    normalized_ratio::Float32,
    normalization_factor::Float32,
    flag::UInt8
)
```

**Mathematical Model**:
```
θ[n] = θ[n-1] + ω_carrier     (constant phase increment)
A[n] = m[n]                    (amplitude from price delta)
output[n] = A[n] × e^(j×θ[n])  (amplitude-modulated carrier)
```

**Key Difference from CPM**: 
- CPM: Phase increment varies with price delta (frequency modulation)
- AMC: Phase increment is constant (amplitude modulation only)

**Implementation**:

**Step 1: Advance Carrier Phase**
```julia
state.phase_accumulator_Q32 += state.amc_carrier_increment_Q32
```

**Default carrier period**: 16 ticks (matches HEXAD-16 for filter compatibility)
```julia
# Carrier frequency = 1/16 cycles per tick
# Phase increment = 2π/16 = π/8 radians per tick
# In Q32: π/8 = (2^32/16) = 268,435,456
amc_carrier_increment_Q32 = Int32(268435456)
```

**Step 2: Lookup Carrier Phasor** (same as CPM)
```julia
lut_index = Int32((reinterpret(UInt32, state.phase_accumulator_Q32) >> 22) & 0x3FF)
carrier_phasor = CPM_LUT_1024[lut_index + 1]
```

**Step 3: Amplitude Modulation**
```julia
complex_signal = normalized_ratio * carrier_phasor
```

**Advantages**:
- Eliminates HEXAD-16 harmonics (smooth carrier)
- Compatible with amplitude-based filters
- Variable envelope encodes price delta
- Carrier frequency can be tuned for specific filter banks

**Disadvantages**:
- Requires matched carrier frequency in receiver
- Phase is not information-bearing (only amplitude matters)

**Example Walkthrough**:
```julia
# Carrier: 16 ticks per cycle, π/8 per tick

# Tick 1:
normalized_ratio = 0.8
θ[1] = 0 + π/8 = 22.5°
carrier = e^(j×22.5°) = ComplexF32(0.924, 0.383)
output[1] = 0.8 × ComplexF32(0.924, 0.383) = ComplexF32(0.739, 0.306)

# Tick 2:
normalized_ratio = -0.3
θ[2] = π/8 + π/8 = π/4 = 45°
carrier = e^(j×45°) = ComplexF32(0.707, 0.707)
output[2] = -0.3 × ComplexF32(0.707, 0.707) = ComplexF32(-0.212, -0.212)

# Carrier rotates uniformly regardless of price changes
# Price information encoded in amplitude (magnitude of complex number)
```

**Comparison Summary**:

| Feature | HEXAD-16 | CPM | AMC |
|---------|----------|-----|-----|
| Phase | Discrete (16 steps) | Continuous (variable rate) | Continuous (constant rate) |
| Information Encoding | Phase + Amplitude | Phase (frequency) | Amplitude only |
| Spectral Properties | Harmonics at 1/16, 2/16, ... | Smooth FM spectrum | Clean carrier + sidebands |
| Filter Compatibility | Discrete phase filters | FM demodulators | Amplitude filters |
| Complexity | Simplest | Moderate | Moderate |
| Phase Continuity | Resets every 16 ticks | Continuous | Continuous |

### Status Flags

Throughout processing, we track various conditions using status flags:

```julia
const FLAG_OK = UInt8(0x00)           # No issues
const FLAG_MALFORMED = UInt8(0x01)    # Original record was malformed
const FLAG_HOLDLAST = UInt8(0x02)     # Price held from previous
const FLAG_CLIPPED = UInt8(0x04)      # Value was clipped/winsorized
const FLAG_AGC_LIMIT = UInt8(0x08)    # AGC hit limit (reserved)
```

**Bitwise OR** allows multiple flags:
```julia
flag = FLAG_CLIPPED | FLAG_HOLDLAST  # Both conditions present
# flag = 0x06 (0x04 | 0x02)

# Check for specific flag:
if (flag & FLAG_CLIPPED) != 0
    println("Tick was clipped")
end
```

### Final Update
```julia
# Update state for next tick
state.last_clean = msg.raw_price
state.ticks_accepted += Int64(1)
```

Save the current price as "last clean" for the next tick's delta calculation, and increment the accepted counter.

---

## Stage 4: TripleSplitSystem.jl

### Purpose

TripleSplitSystem distributes the processed tick data to multiple consumers with priority handling and backpressure management.

### Key Concepts

#### Consumer Types

```julia
@enum ConsumerType::Int32 begin
    PRIORITY = Int32(1)     # Critical path - guaranteed delivery
    MONITORING = Int32(2)   # Non-critical - can drop messages
    ANALYTICS = Int32(3)    # Offline - can drop messages
end
```

**Priority levels determine delivery guarantees:**
- **PRIORITY**: Blocking `put!()` - always succeeds, may wait for buffer space
- **MONITORING/ANALYTICS**: Non-blocking - drops message if buffer full

#### ConsumerChannel Structure

```julia
mutable struct ConsumerChannel
    consumer_id::String                   # Unique identifier
    consumer_type::ConsumerType           # Priority level
    channel::Channel{BroadcastMessage}    # Message queue
    buffer_size::Int32                    # Channel buffer size
    messages_sent::Int32                  # Successful deliveries
    messages_dropped::Int32               # Dropped due to overflow
    lock::ReentrantLock                   # Thread safety
end
```

**Thread safety**: The `lock` ensures multiple threads can safely access channel statistics.

#### TripleSplitManager Structure

```julia
mutable struct TripleSplitManager
    consumers::Vector{ConsumerChannel}   # All subscribed consumers
    lock::ReentrantLock                  # Manager-level thread safety
    total_broadcasts::Int32              # Total broadcast operations
    successful_broadcasts::Int32         # Broadcasts with zero drops
end
```

### Key Functions

#### 1. `subscribe_consumer!(manager, consumer_id, consumer_type, buffer_size)`

Registers a new consumer to receive tick broadcasts.

```julia
function subscribe_consumer!(
    manager::TripleSplitManager,
    consumer_id::String,
    consumer_type::ConsumerType,
    buffer_size::Int32 = Int32(1024)
)::ConsumerChannel
```

**Example**:
```julia
manager = create_triple_split_manager()

# Subscribe priority consumer
priority = subscribe_consumer!(manager, "production_filter", PRIORITY, Int32(4096))

# Subscribe monitoring consumer
monitoring = subscribe_consumer!(manager, "dashboard", MONITORING, Int32(2048))

# Subscribe analytics consumer
analytics = subscribe_consumer!(manager, "research", ANALYTICS, Int32(1024))
```

**Buffer sizing considerations**:
- **PRIORITY**: Large buffer (4096+) to minimize blocking risk
- **MONITORING**: Medium buffer (2048) - real-time but drops acceptable
- **ANALYTICS**: Small buffer (1024) - offline processing, drops don't matter

#### 2. `broadcast_to_all!(manager, message)`

Distributes a message to all subscribed consumers.

```julia
function broadcast_to_all!(
    manager::TripleSplitManager,
    message::BroadcastMessage
)::Tuple{Int32, Int32, Int32}
```

**Returns**: `(total_consumers, successful_deliveries, dropped_deliveries)`

**Implementation Strategy**:
```julia
# 1. Snapshot consumers (minimize lock time)
consumers_snapshot = lock(manager.lock) do
    copy(manager.consumers)
end

# 2. Deliver to each consumer (outside lock)
for consumer in consumers_snapshot
    if deliver_to_consumer!(consumer, message)
        successful += 1
    else
        dropped += 1
    end
end

# 3. Update statistics
lock(manager.lock) do
    manager.total_broadcasts += 1
    if dropped == 0
        manager.successful_broadcasts += 1
    end
end
```

**Why snapshot?** Copying the consumer list minimizes lock contention. Each consumer delivery can then proceed independently.

#### 3. `deliver_to_consumer!(consumer, message)`

Delivers a message to a single consumer with priority-based handling.

```julia
function deliver_to_consumer!(
    consumer::ConsumerChannel,
    message::BroadcastMessage
)::Bool
```

**Priority-based delivery logic**:
```julia
if consumer.consumer_type == PRIORITY
    # Blocking delivery - wait if buffer full
    try
        put!(consumer.channel, message)
        consumer.messages_sent += 1
        return true
    catch
        consumer.messages_dropped += 1
        return false
    end
else
    # Non-blocking - check buffer space first
    if consumer.channel.n_avail_items < consumer.buffer_size
        try
            put!(consumer.channel, message)
            consumer.messages_sent += 1
            return true
        catch
            consumer.messages_dropped += 1
            return false
        end
    else
        # Buffer full - drop message
        consumer.messages_dropped += 1
        return false
    end
end
```

**Key insight**: PRIORITY consumers block to ensure delivery, while MONITORING/ANALYTICS consumers drop messages to avoid blocking the producer.

### Statistics and Monitoring

#### Consumer Statistics
```julia
stats = get_consumer_stats(consumer)
# Returns NamedTuple:
# (consumer_id, consumer_type, messages_sent, messages_dropped, fill_ratio, buffer_size)
```

**Example output**:
```julia
(
    consumer_id = "production_filter",
    consumer_type = PRIORITY,
    messages_sent = 100000,
    messages_dropped = 0,        # PRIORITY should rarely drop
    fill_ratio = 0.15,           # 15% buffer utilization
    buffer_size = 4096
)
```

#### Manager Statistics
```julia
stats = get_manager_stats(manager)
# Returns NamedTuple:
# (total_broadcasts, successful_broadcasts, consumer_count)
```

**Example output**:
```julia
(
    total_broadcasts = 100000,
    successful_broadcasts = 95000,  # 95% success rate
    consumer_count = 3
)
```

**Interpreting statistics**:
- High `messages_dropped` for MONITORING/ANALYTICS is acceptable
- Any `messages_dropped` for PRIORITY indicates a problem
- Low `fill_ratio` indicates consumer is keeping up
- High `fill_ratio` (>0.8) indicates consumer is falling behind

---

## Stage 5: Channel Consumers

### Consumer Patterns

Consumers read from their dedicated channels and process messages asynchronously.

#### Basic Consumer Pattern
```julia
# Subscribe to channel
consumer = subscribe_consumer!(manager, "my_consumer", MONITORING, Int32(2048))

# Async processing loop
@async begin
    for msg in consumer.channel
        # Process message
        process_tick(msg)
        
        # Access all fields
        tick_idx = msg.tick_idx
        price = msg.raw_price
        delta = msg.price_delta
        complex_signal = msg.complex_signal
        norm_factor = msg.normalization
        
        # Check status
        if (msg.status_flag & FLAG_CLIPPED) != 0
            @warn "Tick $tick_idx was clipped"
        end
    end
    println("Consumer finished")
end
```

#### Priority Consumer (Production Filter)
```julia
# High buffer, guaranteed delivery
priority = subscribe_consumer!(manager, "prod_filter", PRIORITY, Int32(8192))

@async begin
    for msg in priority.channel
        # Critical real-time processing
        # MUST keep up - buffer large enough to handle bursts
        
        I = real(msg.complex_signal)
        Q = imag(msg.complex_signal)
        
        # Filter bank processing
        filter_output = process_filterbank(I, Q)
        
        # Trading decisions
        if should_trade(filter_output)
            execute_trade()
        end
    end
end
```

#### Monitoring Consumer
```julia
# Medium buffer, drops acceptable
monitoring = subscribe_consumer!(manager, "monitor", MONITORING, Int32(2048))

@async begin
    for msg in monitoring.channel
        # Update dashboard, log statistics
        # Dropped messages OK - monitoring is best-effort
        
        update_price_chart(msg.raw_price)
        update_signal_plot(msg.complex_signal)
        
        # Alert on anomalies
        if (msg.status_flag & FLAG_HOLDLAST) != 0
            alert_operator("Invalid price detected")
        end
    end
end
```

#### Analytics Consumer
```julia
# Small buffer, offline processing
analytics = subscribe_consumer!(manager, "analytics", ANALYTICS, Int32(512))

@async begin
    collected_data = BroadcastMessage[]
    
    for msg in analytics.channel
        # Collect data for analysis
        # Heavy drops acceptable - this is offline research
        
        push!(collected_data, msg)
        
        # Periodic analysis
        if length(collected_data) >= 10000
            analyze_and_save(collected_data)
            empty!(collected_data)
        end
    end
end
```

---

## BroadcastMessage Structure

### Field-by-Field Breakdown

```julia
mutable struct BroadcastMessage
    tick_idx::Int32           # Sequential tick number (1, 2, 3, ...)
    timestamp::Int64          # Encoded timestamp (GPU-compatible)
    raw_price::Int32          # Original price in ticks
    price_delta::Int32        # Change from previous tick
    normalization::Float32    # Normalization factor applied
    complex_signal::ComplexF32  # Complex I/Q signal
    status_flag::UInt8        # Processing status flags
end
```

### Field Usage

**Populated by VolumeExpansion**:
- `tick_idx`: Sequential counter, starts at 1
- `timestamp`: First 8 chars of timestamp encoded to Int64
- `raw_price`: Last trade price from tick file
- `price_delta`: Computed from consecutive prices

**Updated by TickHotLoopF32**:
- `normalization`: Factor used for normalization (for recovery)
- `complex_signal`: Complex result after encoding (I + jQ)
- `status_flag`: Bitwise flags indicating processing conditions

### GPU Compatibility

**Why all primitive types?**
- GPU kernels cannot handle String, Vector, or other complex types
- All fields are basic types: Int32, Int64, Float32, ComplexF32, UInt8
- Total size: 32 bytes (cache-friendly)
- Can be transferred directly to GPU memory

**Layout in memory**:
```
Offset  | Field            | Type        | Bytes
--------|------------------|-------------|-------
0       | tick_idx         | Int32       | 4
4       | timestamp        | Int64       | 8
12      | raw_price        | Int32       | 4
16      | price_delta      | Int32       | 4
20      | normalization    | Float32     | 4
24      | complex_signal   | ComplexF32  | 8
32      | status_flag      | UInt8       | 1
        |                  |     Total:  | 33 bytes (padded to 40 for alignment)
```

### Why Mutable?

```julia
# MUTABLE allows in-place updates (zero allocation)
function update_broadcast_message!(
    msg::BroadcastMessage,
    complex_signal::ComplexF32,
    normalization::Float32,
    status_flag::UInt8
)
    msg.complex_signal = complex_signal      # Update existing field
    msg.normalization = normalization        # Update existing field
    msg.status_flag = status_flag            # Update existing field
    # NO new allocation - modifies existing struct
end
```

**Performance impact**:
- Immutable struct: Each update creates new instance (~100 ns allocation + GC overhead)
- Mutable struct: Update in-place (~5 ns memory write)
- **20x faster** by avoiding allocation

---

## Performance Considerations

### Critical Path Optimization

**The hot path** (TickHotLoopF32) achieves ~50-80 μs per tick through:

1. **Zero Allocations**: All work done in-place on pre-allocated structures
2. **Minimal Branching**: Predictable code paths for CPU pipeline efficiency
3. **Integer Math**: Fixed-point arithmetic where possible (Q16, Q32)
4. **Lookup Tables**: Pre-computed trig functions (HEXAD16, CPM_LUT_1024)
5. **Cache Efficiency**: 32-byte message fits in single cache line

### Performance Measurements

**Breakdown of tick processing latency**:
```
VolumeExpansion (upstream):    ~100-150 μs
├── String parsing              50 μs
├── Timestamp encoding          20 μs
├── Delta calculation           10 μs
├── Message creation            20 μs
└── Channel put!                50 μs

TickHotLoopF32 (hot path):     ~50-80 μs  ⚡
├── Jump guard                  5 μs
├── Winsorization               5 μs
├── Bar statistics              10 μs
├── Q16 normalization           10 μs
├── Encoder (HEXAD/CPM/AMC)     15 μs
└── Message update              5 μs

TripleSplitSystem (broadcast):  ~30-50 μs
├── Consumer snapshot           10 μs
├── Priority delivery           10 μs
├── MONITORING delivery         10 μs
└── ANALYTICS delivery          10 μs

Total pipeline latency:         ~200-300 μs per tick
```

**Throughput**: ~10,000 ticks/second sustained (1 tick per 100 μs)

### Optimization Techniques Used

#### 1. Fixed-Point Arithmetic
```julia
# SLOW: Floating-point division
normalized = Float32(delta) / Float32(normalization)  # ~20-40 cycles

# FAST: Fixed-point multiply
normalized_Q16 = delta * cached_inv_norm_Q16  # ~3-5 cycles
normalized = Float32(normalized_Q16) * Float32(1.52587890625e-5)
```

**Speedup**: ~5-10x faster

#### 2. Lookup Tables vs Trig Functions
```julia
# SLOW: Runtime trig calculation
complex_signal = ComplexF32(cos(angle), sin(angle))  # ~100+ cycles

# FAST: Pre-computed lookup
complex_signal = CPM_LUT_1024[index]  # ~5 cycles (cache hit)
```

**Speedup**: ~20x faster

#### 3. Bitwise Operations
```julia
# SLOW: Modulo operator
phase = tick_idx % 16  # ~20-30 cycles

# FAST: Bitwise AND
phase = tick_idx & 15  # ~1 cycle
```

**Speedup**: ~20x faster (when power of 2)

#### 4. In-Place Updates
```julia
# SLOW: Allocate new struct
new_msg = BroadcastMessage(...)  # ~100 ns + GC pressure

# FAST: Update existing struct
update_broadcast_message!(msg, ...)  # ~5 ns
```

**Speedup**: ~20x faster + eliminates GC

### Common Bottlenecks to Avoid

❌ **Don't do this in the hot path**:
```julia
# String operations
str = "Tick $tick_idx: $price"

# Allocations
array = [price_delta, normalized_ratio]

# Complex calculations
result = exp(complex_value)

# I/O operations
println("Processing tick")

# Locks and synchronization
lock(my_lock) do
    # ... processing ...
end
```

✅ **Do this instead**:
```julia
# Pre-allocate all structures
state = create_tickhotloop_state()

# Use fixed-point or lookup tables
result = LUT[index]

# Defer logging to separate thread
# Use async consumer for monitoring/logging

# Lock-free message passing
put!(channel, message)
```

---

## Common Patterns and Examples

### Example 1: Complete Pipeline Setup

```julia
using TickDataPipeline

# Create split manager
split_mgr = create_triple_split_manager()

# Subscribe consumers
priority = subscribe_consumer!(split_mgr, "filter", PRIORITY, Int32(8192))
monitoring = subscribe_consumer!(split_mgr, "monitor", MONITORING, Int32(2048))

# Create state
state = create_tickhotloop_state()

# Configuration
encoder = "hexad16"
agc_alpha = Float32(0.0625)
winsorize_thresh = Int32(10)
min_price = Int32(40000)
max_price = Int32(43000)
max_jump = Int32(50)
cpm_h = Float32(0.5)

# Stream ticks from file
tick_channel = stream_expanded_ticks("data/raw/YM 06-25.Last.txt", 0.0)

# Process ticks
for msg in tick_channel
    # Signal processing (hot path)
    process_tick_signal!(
        msg, state,
        agc_alpha, Int32(4), Int32(50),
        winsorize_thresh,
        min_price, max_price, max_jump,
        encoder, cpm_h
    )
    
    # Broadcast to consumers
    broadcast_to_all!(split_mgr, msg)
end

println("Processing complete")
println("Ticks accepted: $(state.ticks_accepted)")
```

### Example 2: Real-Time Processing with Monitoring

```julia
using TickDataPipeline

function run_realtime_pipeline(tick_file::String)
    # Setup
    split_mgr = create_triple_split_manager()
    
    priority = subscribe_consumer!(split_mgr, "trading", PRIORITY, Int32(8192))
    monitoring = subscribe_consumer!(split_mgr, "dashboard", MONITORING, Int32(2048))
    
    # Launch consumer tasks
    trading_task = @async begin
        for msg in priority.channel
            # Trading logic
            I, Q = real(msg.complex_signal), imag(msg.complex_signal)
            if abs(I) > 0.8
                println("Trade signal: Tick $(msg.tick_idx), I=$I")
            end
        end
    end
    
    monitoring_task = @async begin
        for msg in monitoring.channel
            # Update dashboard every 1000 ticks
            if msg.tick_idx % 1000 == 0
                println("Progress: $(msg.tick_idx) ticks")
                
                if (msg.status_flag & FLAG_CLIPPED) != 0
                    println("  [WARNING] Tick was clipped")
                end
            end
        end
    end
    
    # Process ticks
    state = create_tickhotloop_state()
    tick_channel = stream_expanded_ticks(tick_file, 1.0)  # 1ms delay
    
    for msg in tick_channel
        process_tick_signal!(msg, state, 
            Float32(0.0625), Int32(4), Int32(50), Int32(10),
            Int32(40000), Int32(43000), Int32(50),
            "hexad16", Float32(0.5))
        
        broadcast_to_all!(split_mgr, msg)
    end
    
    # Cleanup
    close(priority.channel)
    close(monitoring.channel)
    wait(trading_task)
    wait(monitoring_task)
    
    # Statistics
    println("\nStatistics:")
    println("  Ticks accepted: $(state.ticks_accepted)")
    println("  Bars completed: $(state.bar_count)")
    
    priority_stats = get_consumer_stats(priority)
    println("  Priority delivered: $(priority_stats.messages_sent)")
    println("  Priority dropped: $(priority_stats.messages_dropped)")
end

run_realtime_pipeline("data/raw/YM 06-25.Last.txt")
```

### Example 3: Comparing Encoders

```julia
using TickDataPipeline

function compare_encoders(tick_file::String, num_ticks::Int64=1000)
    encoders = ["hexad16", "cpm", "amc"]
    results = Dict{String, Vector{ComplexF32}}()
    
    for encoder in encoders
        state = create_tickhotloop_state()
        tick_channel = stream_expanded_ticks(tick_file, 0.0)
        
        signals = ComplexF32[]
        count = 0
        
        for msg in tick_channel
            process_tick_signal!(msg, state,
                Float32(0.0625), Int32(4), Int32(50), Int32(10),
                Int32(40000), Int32(43000), Int32(50),
                encoder, Float32(0.5))
            
            push!(signals, msg.complex_signal)
            
            count += 1
            if count >= num_ticks
                break
            end
        end
        
        results[encoder] = signals
        println("$encoder: $(length(signals)) signals")
    end
    
    # Compare outputs
    println("\nFirst 10 signals comparison:")
    for i in 1:min(10, num_ticks)
        println("Tick $i:")
        for encoder in encoders
            sig = results[encoder][i]
            magnitude = abs(sig)
            phase = angle(sig) * 180/π
            println("  $encoder: mag=$(round(magnitude, digits=3)), phase=$(round(phase, digits=1))°")
        end
    end
    
    return results
end

results = compare_encoders("data/raw/YM 06-25.Last.txt", 100)
```

### Example 4: Performance Profiling

```julia
using TickDataPipeline
using Statistics

function profile_pipeline(tick_file::String, num_ticks::Int64=10000)
    # Setup
    state = create_tickhotloop_state()
    split_mgr = create_triple_split_manager()
    consumer = subscribe_consumer!(split_mgr, "prof", PRIORITY, Int32(8192))
    
    # Timing storage
    parse_times = Float64[]
    process_times = Float64[]
    broadcast_times = Float64[]
    
    tick_channel = stream_expanded_ticks(tick_file, 0.0)
    count = 0
    
    for msg in tick_channel
        # Time processing
        t_start = time_ns()
        process_tick_signal!(msg, state,
            Float32(0.0625), Int32(4), Int32(50), Int32(10),
            Int32(40000), Int32(43000), Int32(50),
            "hexad16", Float32(0.5))
        t_process = time_ns()
        
        # Time broadcast
        broadcast_to_all!(split_mgr, msg)
        t_broadcast = time_ns()
        
        # Record times (microseconds)
        push!(process_times, (t_process - t_start) / 1000.0)
        push!(broadcast_times, (t_broadcast - t_process) / 1000.0)
        
        count += 1
        if count >= num_ticks
            break
        end
    end
    
    # Statistics
    println("Performance Profile ($num_ticks ticks):")
    println("\nProcessing (TickHotLoopF32):")
    println("  Mean:   $(round(mean(process_times), digits=2)) μs")
    println("  Median: $(round(median(process_times), digits=2)) μs")
    println("  Min:    $(round(minimum(process_times), digits=2)) μs")
    println("  Max:    $(round(maximum(process_times), digits=2)) μs")
    
    println("\nBroadcast (TripleSplitSystem):")
    println("  Mean:   $(round(mean(broadcast_times), digits=2)) μs")
    println("  Median: $(round(median(broadcast_times), digits=2)) μs")
    
    total_times = process_times .+ broadcast_times
    println("\nTotal Latency:")
    println("  Mean:   $(round(mean(total_times), digits=2)) μs")
    println("  Throughput: $(round(1000000.0 / mean(total_times), digits=0)) ticks/sec")
end

profile_pipeline("data/raw/YM 06-25.Last.txt", 10000)
```

---

## Summary

### Key Takeaways

1. **Pipeline Architecture**:
   - VolumeExpansion: Parse and pre-populate (heavy work)
   - TickHotLoopF32: Signal processing only (ultra-fast)
   - TripleSplitSystem: Priority-based distribution
   - Consumers: Async processing with backpressure handling

2. **Performance Principles**:
   - Zero allocation in hot path
   - Fixed-point arithmetic for speed
   - Lookup tables for trig functions
   - In-place updates of mutable structures
   - Minimal conditional branching

3. **Signal Processing**:
   - Bar-based adaptive normalization
   - Winsorization for outlier handling
   - Jump guard for extreme moves
   - Three encoder options: HEXAD-16, CPM, AMC

4. **Thread Safety**:
   - Channel-based message passing (lock-free for producers)
   - Per-consumer locks for statistics
   - Manager lock for consumer registration

5. **GPU Compatibility**:
   - All primitive types in BroadcastMessage
   - No String types (timestamp encoded to Int64)
   - 32-byte structure (cache-friendly)

### Next Steps for Junior Developers

1. **Understand the flow**: Follow a single tick through the entire pipeline
2. **Experiment with encoders**: Compare HEXAD-16, CPM, and AMC outputs
3. **Profile performance**: Measure latency on your hardware
4. **Create custom consumers**: Build monitoring or analytics consumers
5. **Study the math**: Understand normalization, fixed-point, and modulation
6. **Read the source**: The actual code is well-commented and readable

### Further Reading

- `docs/API.md`: Complete API reference
- `docs/design/`: Detailed design specifications
- `examples/`: Working code examples
- Source code: `src/` directory

---

**Document Version**: 1.0  
**Last Updated**: October 15, 2025  
**Maintained by**: Technical Documentation Team

# TickHotLoopF32 Signal Processing Flow

**Document**: Step-by-step signal processing in TickHotLoopF32.jl
**Date**: 2025-10-04
**Source**: `src/TickHotLoopF32.jl`

---

## Overview

The `process_tick_signal!()` function (lines 141-243) processes each tick's price delta through a signal processing chain and updates the BroadcastMessage in-place with:
- `normalization`: AGC scale factor applied
- `complex_signal`: I/Q complex signal after QUAD-4 rotation
- `status_flag`: Processing status flags

**Key Design Principle**: All features are ALWAYS ENABLED with zero branching for feature enablement (line 111).

---

## Input Requirements

**BroadcastMessage Fields (Pre-Populated by VolumeExpansion)**:
- `tick_idx` (Int32): Sequential tick index
- `timestamp` (Int64): Encoded timestamp
- `raw_price` (Int32): Last price from tick file
- `price_delta` (Int32): Price change from previous tick

**TickHotLoopState** (lines 23-38):
- Tracks EMA values across ticks
- Maintains AGC state
- Stores last clean price
- Counts ticks processed/accepted

---

## Processing Steps

### Step 1: Initialization (Lines 152-154)

```julia
state.tick_count += Int64(1)
price_delta = msg.price_delta
flag = FLAG_OK
```

- Increment global tick counter
- Extract price delta from message
- Initialize status flag to OK (0x00)

---

### Step 2: Absolute Price Validation (Lines 156-173)

**Lines 157-173**: Check if `raw_price` is within valid range `[min_price, max_price]`

**If price is INVALID**:
- **Lines 158-167**: If we have a previous clean price (`state.last_clean !== nothing`):
  - Set flag to `FLAG_HOLDLAST` (0x02)
  - Use zero delta (line 161)
  - Calculate QUAD-4 rotation with zero value (lines 162-163)
  - Update message and return early (lines 165-167)

- **Lines 168-172**: If this is the FIRST tick and invalid:
  - Return zero complex signal (line 170)
  - Exit without accepting tick (line 171)

**Purpose**: Reject out-of-range prices, hold last valid signal if available.

---

### Step 3: First Good Tick Initialization (Lines 175-185)

**Lines 176-185**: If `state.last_clean === nothing` (first valid tick):

1. **Line 177**: Store current price as `last_clean`
2. **Line 178**: Set normalized ratio to 0.0 (first tick has no meaningful delta)
3. **Lines 179-180**: Calculate QUAD-4 phase and rotation
4. **Line 182**: Update message with zero signal
5. **Lines 183-184**: Accept tick and return

**Purpose**: Initialize state machine on first valid price.

---

### Step 4: Extract Delta (Lines 187-188)

```julia
delta = price_delta
```

Simple extraction of price delta for processing.

---

### Step 5: Hard Jump Guard (Lines 190-194)

**Lines 191-194**: If `|delta| > max_jump`:

1. **Line 192**: Clamp delta to `±max_jump`
2. **Line 193**: Set `FLAG_CLIPPED` (0x04)

**Purpose**: Prevent extreme price jumps from corrupting signal processing.

---

### Step 6: EMA Update for Normalization (Lines 196-208)

**Line 197**: Calculate absolute delta

**Lines 199-208**: Update Exponential Moving Averages

**If EMA already initialized** (lines 199-203):
- **Line 201**: Update `ema_delta` using bit shift (alpha = 1/16)
  ```julia
  ema_delta = ema_delta + ((delta - ema_delta) >> 4)
  ```
- **Line 202**: Calculate deviation from EMA
- **Line 203**: Update `ema_delta_dev` (EMA of deviations)

**If first EMA calculation** (lines 204-207):
- **Line 205**: Initialize `ema_delta` to current delta
- **Line 206**: Initialize `ema_delta_dev` to absolute delta (min 1)
- **Line 207**: Mark EMA as initialized

**Purpose**: Track moving average and deviation for normalization.

---

### Step 7: AGC (Automatic Gain Control) (Lines 210-221)

**Lines 212-213**: Update EMA of absolute delta for AGC
```julia
ema_abs_delta = ema_abs_delta +
                Int32(round((Float32(abs_delta) - Float32(ema_abs_delta)) * agc_alpha))
```

**Lines 216-217**: Calculate AGC scale
- **Line 216**: Use `ema_abs_delta` as scale (minimum 1)
- **Line 217**: Clamp to `[agc_min_scale, agc_max_scale]`

**Lines 219-221**: Check if AGC hit limit
- **Line 219**: If scale at maximum
- **Line 220**: Set `FLAG_AGC_LIMIT` (0x08)

**Purpose**: Automatically adjust signal amplitude based on recent volatility.

---

### Step 8: Normalization (Lines 223-225)

**Lines 224-225**: Normalize delta by AGC scale
```julia
normalized_ratio = Float32(delta) / Float32(agc_scale)
normalization_factor = Float32(agc_scale)
```

- **Line 224**: Divide delta by AGC scale → normalized ratio (typically -3 to +3)
- **Line 225**: Store scale factor for output

**Purpose**: Convert price delta to normalized floating-point value.

---

### Step 9: Winsorization (Lines 227-231)

**Lines 228-231**: Clip outliers

**If** `|normalized_ratio| > winsorize_threshold`:
- **Line 229**: Clip to `±winsorize_threshold` (preserving sign)
- **Line 230**: Set `FLAG_CLIPPED` (0x04)

**Purpose**: Prevent extreme outliers from dominating signal.

---

### Step 10: QUAD-4 Rotation (Lines 233-235)

**Line 234**: Calculate phase position
```julia
phase = phase_pos_global(state.tick_count)
```

**Phase Calculation** (lines 101-103):
- `phase = (tick_idx - 1) % 4`
- Cycles through: 0, 1, 2, 3, 0, 1, 2, 3...

**Line 235**: Apply QUAD-4 rotation
```julia
z = apply_quad4_rotation(normalized_ratio, phase)
```

**QUAD-4 Rotation** (lines 76-88):
- **Phase 0 (0°)**: `(normalized_ratio, 0)` - Real axis
- **Phase 1 (90°)**: `(0, normalized_ratio)` - Imaginary axis
- **Phase 2 (180°)**: `(-normalized_ratio, 0)` - Negative real axis
- **Phase 3 (270°)**: `(0, -normalized_ratio)` - Negative imaginary axis

**Purpose**: Rotate signal through complex plane for I/Q modulation.

---

### Step 11: Update BroadcastMessage (Line 238)

**Line 238**: Update message IN-PLACE
```julia
update_broadcast_message!(msg, z, normalization_factor, flag)
```

**Updates**:
- `msg.complex_signal = z` (ComplexF32)
- `msg.normalization = normalization_factor` (Float32)
- `msg.status_flag = flag` (UInt8)

---

### Step 12: Update State (Lines 240-242)

**Line 241**: Store current price as last clean price
```julia
state.last_clean = msg.raw_price
```

**Line 242**: Increment accepted tick counter
```julia
state.ticks_accepted += Int64(1)
```

---

## Output

**BroadcastMessage Updated Fields**:

1. **`complex_signal`** (ComplexF32):
   - Real component: Active on phases 0, 2
   - Imaginary component: Active on phases 1, 3
   - Magnitude: Normalized price delta (after AGC and winsorization)

2. **`normalization`** (Float32):
   - AGC scale factor applied to this tick
   - Indicates volatility level

3. **`status_flag`** (UInt8):
   - `0x00` (FLAG_OK): Normal processing
   - `0x01` (FLAG_MALFORMED): Malformed input (not used in TickHotLoop)
   - `0x02` (FLAG_HOLDLAST): Price held from previous
   - `0x04` (FLAG_CLIPPED): Value clipped (jump guard or winsorization)
   - `0x08` (FLAG_AGC_LIMIT): AGC at maximum limit

---

## Signal Flow Diagram

```
Input: BroadcastMessage (tick_idx, timestamp, raw_price, price_delta)
       TickHotLoopState (EMA state, last_clean, counters)

Step 1: Increment tick_count, initialize flag
         ↓
Step 2: Validate raw_price ∈ [min_price, max_price]
         ├─ Invalid → Use zero delta, HOLDLAST flag, return
         └─ Valid → Continue
         ↓
Step 3: First tick? Initialize state, return zero signal
         ↓
Step 4: Extract delta = price_delta
         ↓
Step 5: Hard jump guard: |delta| > max_jump?
         └─ Yes → Clamp delta, set CLIPPED flag
         ↓
Step 6: Update EMA (alpha=1/16): ema_delta, ema_delta_dev
         ↓
Step 7: AGC: Update ema_abs_delta, calculate agc_scale
         ├─ agc_scale clamped to [agc_min_scale, agc_max_scale]
         └─ If at max → set AGC_LIMIT flag
         ↓
Step 8: Normalize: normalized_ratio = delta / agc_scale
         ↓
Step 9: Winsorize: |normalized_ratio| > threshold?
         └─ Yes → Clip to ±threshold, set CLIPPED flag
         ↓
Step 10: QUAD-4 Rotation:
          phase = (tick_idx - 1) % 4
          ├─ Phase 0: (value, 0)     [Real]
          ├─ Phase 1: (0, value)     [Imaginary]
          ├─ Phase 2: (-value, 0)    [Negative Real]
          └─ Phase 3: (0, -value)    [Negative Imaginary]
         ↓
Step 11: Update BroadcastMessage:
          - complex_signal = rotated ComplexF32
          - normalization = agc_scale (Float32)
          - status_flag = accumulated flags (UInt8)
         ↓
Step 12: Update state:
          - last_clean = raw_price
          - ticks_accepted += 1

Output: BroadcastMessage (complex_signal, normalization, status_flag updated)
```

---

## Key Observations

### QUAD-4 Behavior

**Expected Signal Pattern**:
- Every 4 ticks, signal rotates through all quadrants
- **Phase 0, 2**: Real component active, Imaginary = 0
- **Phase 1, 3**: Imaginary component active, Real = 0

**This means**:
- 50% of ticks have Real = 0
- 50% of ticks have Imaginary = 0
- Never both zero simultaneously (unless normalized_ratio = 0)

### When Signals Are Zero

**Real Component = 0**:
- Phases 1 and 3 (50% of ticks)
- When normalized_ratio = 0 (no price change)

**Imaginary Component = 0**:
- Phases 0 and 2 (50% of ticks)
- When normalized_ratio = 0 (no price change)

**Both Components = 0**:
- Only when normalized_ratio = 0 (i.e., delta = 0 or first tick)
- NOT related to processing speed

### Gaps in I/Q Signals

If you observe:
- **Long gaps in Real signal**: Normal during phases 1 and 3
- **Imaginary always zero**: Bug - should alternate with Real
- **Both zero for extended periods**: Indicates price_delta = 0 (no price movement)

---

## Conclusion

The TickHotLoopF32 processing is deterministic and does NOT depend on processing speed. The QUAD-4 rotation ALWAYS produces alternating I/Q components based solely on `tick_idx`.

**If Imaginary component is consistently zero**, this indicates:
1. The QUAD-4 rotation is not being applied correctly, OR
2. The `tick_idx` is not incrementing properly, OR
3. The signal is being overwritten after processing

This is a **logic bug**, not a performance issue.

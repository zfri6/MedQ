# audio_tone_gen Behavior Specification

## Requirement Summary

Generate a real-time audio sine wave at the 48 kHz sample rate, controlled by `freq_inc` and `amplitude`. Uses a 256-entry quarter-cycle sine lookup table with phase accumulation to synthesize arbitrary frequencies. Covers the test-tone requirement for basic requirement 3.

## Public Interface

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | in | 1 | Pixel clock, 25.000 MHz |
| `rst_n` | in | 1 | Async reset, low-active |
| `stb` | in | 1 | 48 kHz sample gate from `audio_sample_clk` |
| `enable` | in | 1 | 1 = generate tone; 0 = output zero |
| `freq_inc` | in | 24 | Phase increment per 48 kHz step |
| `amplitude` | in | 8 | Output scale factor 0..255 |
| `sample` | out | 16 | Signed 16-bit PCM sample |

## Parameters and Defaults

No module-level parameters (all are run-time port-driven). The sine table is a 256×16 bit ROM.

## Clocking and Reset

- Clock: `clk_pix` @ 25.000 MHz
- Reset: async assert / sync release, `rst_n` low-active
- Phase advances only on `stb` (48 kHz), one sample per gate pulse

## Functional Behavior

### 1. Phase Accumulator
- 24-bit phase register `phase` increments by `freq_inc` on every `stb` rising edge.
- `freq_inc = round(2^24 × f / 48000)` where `f` is the desired frequency in Hz.

### 2. Frequency Table
| Frequency | `freq_inc` (dec) |
|-----------|-------------------|
| 440 Hz (A4) | 349525 |
| 880 Hz (A5) | 699050 |
| 1000 Hz (test) | 3495250 |
| 2000 Hz (test) | 6990500 |

### 3. 1/4-Cycle Sine Table (Q15)
- 256 entries covering 0° to 90° (0 to π/2 radians).
- Values are Q15: range 0 to +32767.
- Quadrant mapping by `phase[23:22]`:
  - `00` → Q1: +sin → `table[idx]`
  - `01` → Q2: +sin → `table[255-idx]`
  - `10` → Q3: -sin → `-table[idx]`
  - `11` → Q4: -sin → `-table[255-idx]`

### 4. Amplitude Scaling
- `sample = amplitude × sine_value / 32768`
- Implemented as: `product = amplitude × sine_Q15`, then shift right 7 bits.
- When `enable = 0`, output is forced to 16'h0000 (mute).

### 5. Output Format
- 16-bit signed two's complement.
- Range: ±32767 × (amplitude/256) at full scale.

## Latency and Throughput

- Latency: 2 cycles (phase register update → table read → multiply → register)
- Throughput: one sample per `stb` cycle (48 kS/s)

## Assumptions and Chosen Defaults

- `freq_inc` is stable while `enable = 1`. Changing it mid-tone produces a phase discontinuity (acceptable for alert tones).
- The sine table values are computed at compile time via Python/scipy and embedded as a constant array.
- `amplitude = 128` is a neutral default (0 dBFS with 6 dB headroom).

## Edge Cases and Error Handling

- `amplitude = 0`: output is zero regardless of phase.
- `freq_inc = 0`: output DC (first table entry × amplitude).
- `rst_n` drops during `stb`: phase is cleared to zero; next sample starts at zero.
- Table index is always within 0..255 (guaranteed by `tbl_idx = phase[21:14]`).

## Synthesis Notes

- **Sine table**: 256 × 16 bit ROM → inferred as distributed LUT ROM (LUT4 × 128 = 512 LUT4), or BRAM if TD prefers.
- **Multiplier**: one 8×16 → 24-bit multiplier. TD maps to 1 DSP/ALU block.
- **Resources**: ~600 LUT4 + 1 multiplier ≈ well within E-group budget.

## Verification Plan

1. **Frequency**: sweep `freq_inc` across known tones; measure zero-crossing intervals; assert frequency matches ±0.5 Hz.
2. **Amplitude linearity**: sweep `amplitude` 0..255; assert output range is linear.
3. **Disable**: assert `sample == 0` whenever `enable == 0`.
4. **Reset**: assert `sample == 0` and `phase == 0` within 2 cycles of `rst_n` assertion.
5. **THD check** (optional): run 2048-sample FFT in TB; assert THD < -40 dB for a pure 1 kHz tone.

## Acceptance Criteria

- [ ] 440 Hz tone plays at correct frequency (±0.5 Hz).
- [ ] Output is zero when `enable = 0`.
- [ ] Reset clears phase and output.
- [ ] RTL compiles with iverilog and ModelSim with zero errors.
- [ ] No inferred latches.

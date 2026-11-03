> 2026-10-26：旧文档与旧RTL在并行乘法/复位/系数/功率上有冲突，以下旧周期表已被覆盖。
> 当前实现为一个注册32x32共享运算，TD实际4DSP，signed32递推；默认160拍内完成块末处理。
> 正确数值公式、参数范围、归一化和包络规则见behavior_spec.md“资源优化增补”；12块/192bin独立参考测试已通过。

# goertzel_spectrum Behavior Specification

## Requirement Summary

Compute a 16-bin Goertzel spectrum on the audio stream at 48 kHz. For each 256-sample block (≈5.33 ms), output the 16 bin magnitudes with logarithmic compression. One hardware multiplier is shared across all 16 bins via time-multiplexing (TDM).

## Public Interface

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | in | 1 | Pixel clock, 25.000 MHz |
| `rst_n` | in | 1 | Async reset, low-active |
| `stb` | in | 1 | 48 kHz sample gate |
| `sample` | in | 16 | Signed 16-bit PCM audio sample |
| `bin_valid` | out | 1 | One pulse per bin result |
| `bin_idx` | out | 4 | Bin index 0..15 |
| `bin_mag` | out | 8 | Log-scale magnitude 0..255 |
| `level` | out | 8 | Peak envelope across all bins |

## Parameters

| Name | Default | Description |
|------|---------|-------------|
| `BINS` | 16 | Number of frequency bins |
| `BLOCK_N` | 256 | Samples per block |

## Clocking and Reset

- Clock: `clk_pix` @ 25.000 MHz
- Reset: async assert / sync release, `rst_n` low-active
- All state transitions synchronous to `clk_pix`

## Functional Behavior

### 1. Goertzel Recurrence (every stb)

For each of the 16 bins, maintain two state variables `s1[i]` and `s2[i]`:
```
s2 <= s1
s1 <= sample + coef[i] * s1 - s2
```
where `coef[i] = 2*cos(2π*(i+1)/256)` in Q2.14 signed format.

This recurrence runs in parallel for all 16 bins on every `stb`.

### 2. Frequency Bins

| Bin | Frequency (Hz) |
|-----|---------------|
| 0 | 187.5 |
| 1 | 375.0 |
| 2 | 562.5 |
| ... | ... |
| 15 | 3000.0 |

### 3. Magnitude Computation (TDM, 1 multiplier)

After the last sample of a block, compute magnitudes TDM using one multiplier in 4 cycles per bin:

| Phase | Multiplier A | Multiplier B | Purpose | Latched |
|-------|-------------|-------------|---------|---------|
| A | `coef` | `s2` | `coef * s2` | `prod_coef_s2` |
| B | `s1` | `s1` | `s1^2` | `prod_s1_sq` |
| C | `s1` | `s2` | `s1 * s2` | `prod_s1_s2` |
| D | — | — | finalize | `mult_out = s2^2` |

Magnitude: `mag2 = prod_s1_sq + mult_out - prod_s1_s2`

Output: `bin_valid = 1`, `bin_idx = i`, `bin_mag = log_mag(mag2)`.

### 4. Log-Magnitude

`bin_mag = floor(log2(max(mag2, 1))) * 8`, range 0..248.

The leading-one detector scans the 32-bit `mag2` result and returns the position of the MSB, scaled by 8 to fill the 8-bit output.

### 5. Level (Peak Envelope)

`level` tracks the peak of `bin_mag` across all bins:
- **Attack**: when `bin_mag > level`, rise at ~0.875× per update
- **Decay**: when `bin_mag <= level`, fall at ~0.984× per update (slow decay)

## Latency and Throughput

- **Recurrence**: 1 cycle per `stb` (continuous during audio)
- **TDM output**: 16 bins × 4 cycles = 64 `clk_pix` cycles = ~2.56 µs
- **Block interval**: 256 samples × 20.83 µs/sample = 5.33 ms
- **Total overhead**: 64 cycles / 5.33 ms = 0.12% of time, negligible

## Assumptions and Chosen Defaults

- The multiplier is inferred as a DSP block by TD (1 DSP for 16-bit signed multiplication).
- `sample` is signed 16-bit PCM from `audio_mixer` output.
- `coef[i]` values are pre-computed as Q2.14 constants; no runtime division.

## Edge Cases and Error Handling

- **Zero input**: all `s1/s2` stay at zero; `bin_mag = 0`.
- **`mag2 < 0`**: handled by treating as 0 before log conversion.
- **Reset during block**: `s1/s2` cleared; block restarts from zero.
- **`stb` during TDM output**: TDM output continues (sample is ignored during `ST_OUT`).

## Synthesis Notes

- **Resources**:
  - 16×(s1 + s2) registers: 32 × 16 bits = 512 DFFs
  - 1 × 16-bit signed multiplier: 1 DSP
  - Combinational `get_coef()` function: 16 × 4 LUT4
  - Level envelope: 8 DFFs
- **Total**: ~600 LUT4 + 1 DSP ≈ within E-group budget
- **No BRAM**

## Verification Plan

1. **DC input**: inject `sample = 0` for entire block; assert all `bin_mag = 0`.
2. **Single tone**: inject a 440 Hz sine; assert `bin_mag[1]` (375 Hz bin) ≈ `bin_mag[2]` (562.5 Hz bin) are non-zero and higher than other bins.
3. **TDM correctness**: verify `bin_idx` cycles 0→1→...→15→0 for each block.
4. **Level envelope**: inject step input; assert `level` rises then decays.
5. **Reset**: assert all `s1/s2` clear to zero within 2 cycles.

## Acceptance Criteria

- [ ] `bin_valid` fires exactly 16 times per block.
- [ ] `bin_idx` cycles 0..15 per block.
- [ ] A 440 Hz tone produces peaks in bins 1 and 2.
- [ ] `level` rises on signal, decays when silent.
- [ ] RTL compiles with iverilog and ModelSim with zero errors.

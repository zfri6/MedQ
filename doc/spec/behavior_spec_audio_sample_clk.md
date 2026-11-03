> 2026-10-26：本模块已在仿真闭环修复中更新；以下为历史初版。当前行为与接口以 [闭环行为说明](behavior_spec.md) 和实际 RTL 为准。

# audio_sample_clk Behavior Specification

## Requirement Summary

Generate a precise 48 kHz sample strobe from the 25.000 MHz pixel clock using a fractional phase accumulator. The strobe is used as the common timing gate for all audio modules, and must stay frequency-locked with the HDMI ACR N/CTS construction (N=6144, CTS=25000).

## Public Interface

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk`   | in | 1 | Pixel clock, 25.000 MHz |
| `rst_n` | in | 1 | Async reset, low-active |
| `stb`   | out| 1 | 48 kHz single-cycle gate pulse |

## Parameters and Defaults

| Name | Default | Description |
|------|---------|-------------|
| `ACC_W`   | 24 | Accumulator bit width |
| `ACC_INC` | 32212 | Phase increment = floor(48000 × 2^24 / 25e6) |

**Derivation:**
```
ACC_INC = round(48000 × 2^24 / 25000000)
        = round(32212.53)
        = 32212

error = (32212 - 32212.53) / 32212.53 × 1e6 ppm
      = -16.7 ppb  (< 0.03 ppm requirement)
```

The value 32212 keeps the accumulator in 24 bits (vs 32 bits used in the yaml — that is for the ACR counter, not this unit). The two constructions are consistent because both derive from the same N=6144 / CTS=25000 ratio.

## Clocking and Reset

- Clock: `clk_pix` @ 25.000 MHz (from `clk_wize` PLL C1)
- Reset: async assert, sync release; `rst_n` low-active; drives `acc` to zero

## Functional Behavior

1. **Accumulation**: every rising edge of `clk`, `acc <= acc + ACC_INC`.
2. **Overflow detection**: the MSB (`acc[ACC_W-1]`) becomes `1` when the 24-bit accumulator wraps from `0x80_0000` → `0x00_0000`.
3. **Strobe**: `stb` is set to the overflow flag in the same cycle; therefore `stb` is a single-cycle pulse at 48 kHz.
4. **Reset**: `acc` is cleared to zero asynchronously; `stb` is also forced low.

### Timing diagram

```
clk      __|‾|__|‾|__|‾|__|‾|__|‾|__|‾|__|‾|__
acc[23]  ___________________________________|‾|___
stb      ___________________________________|‾|___
          ^ overflow every 2^24/32212 ≈ 520.8k cycles
          = 25e6/520830 ≈ 48000.0 Hz
```

## Latency and Throughput

- Latency: 1 cycle (accumulator register)
- Throughput: one `stb` pulse every ~520,830 `clk` cycles (48 kHz)
- This module is purely sequential; no combinational paths.

## Assumptions and Chosen Defaults

- `clk_pix` frequency is exactly 25.000 MHz (PLL C1). If it is not, `ACC_INC` must be recalculated.
- The parameter `ACC_W=24` keeps the accumulator compact. It is NOT the same as the 32-bit ACC_INC mentioned in the yaml (which applies to the HDMI ACR packet counter).

## Edge Cases and Error Handling

- **Reset during overflow**: if `rst_n` drops exactly when overflow would fire, the stb is suppressed and `acc` is cleared. No error flag needed.
- **Consecutive overflows**: impossible — `ACC_INC < 2^(ACC_W-1)`, so at most one overflow per cycle.

## Synthesis Notes

- **Resources**: 1 LUT4 (adder) + 1 FF (accumulator) + 1 FF (stb) ≈ negligible.
- **No BRAM, no multipliers.**
- Fully synchronous to `clk_pix`; no clock domain crossing inside.
- TD will infer a simple adder chain; no special constraints needed.

## Verification Plan

1. **Frequency measurement**: in TB, count `stb` pulses over a long window (≥ 1 ms) and assert the count is 48 ± 1.
2. **Phase coherence**: assert that `stb` does not drift relative to a reference 48 kHz counter over 10,000 cycles.
3. **Reset**: assert `acc` and `stb` go to zero within 2 cycles of `rst_n` assertion.
4. **No spurious stb**: assert no two `stb` pulses are less than 500 `clk` cycles apart.

## Acceptance Criteria

- [ ] `stb` frequency measured by TB is 48000 Hz ± 0.1 Hz (within simulation resolution).
- [ ] `stb` is a single-cycle pulse (never high for more than one `clk` cycle).
- [ ] Reset clears `acc` and `stb` to zero.
- [ ] RTL compiles with iverilog and ModelSim with zero errors.

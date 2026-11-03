> 2026-10-26：本模块已在仿真闭环修复中更新；以下为历史初版。当前行为与接口以 [闭环行为说明](behavior_spec.md) 和实际 RTL 为准。

# osd_compositor Behavior Specification

## 1. Requirement Summary

Final composition stage. Processes in order: brightness/contrast → OSD text
alpha-blend → spectrum layer alpha-blend → output. All signals registered.
`de`/`hs`/`vs` are delayed to match the rgb pipeline.

## 2. Public Interface

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| clk | in | 1 | Pixel clock 25 MHz |
| rst_n | in | 1 | Async reset, active low |
| de_in | in | 1 | Display enable |
| hs_in | in | 1 | Horizontal sync (negative polarity) |
| vs_in | in | 1 | Vertical sync (negative polarity) |
| rgb_base | in | 24 | Base frame from transition_engine |
| osd_rgb | in | 24 | OSD text layer RGB |
| osd_alpha | in | 8 | OSD alpha 0=transparent 255=opaque |
| spec_rgb | in | 24 | Spectrum layer RGB |
| spec_alpha | in | 8 | Spectrum alpha |
| param | in | 64 | Parameter bus |
| de_out | out | 1 | Display enable (aligned) |
| hs_out | out | 1 | HS (aligned) |
| vs_out | out | 1 | VS (aligned) |
| rgb_out | out | 24 | Final composed pixel |

## 3. Parameters and Defaults

None.

## 4. Clocking and Reset

- **Domain**: `clk_pix` (25.000 MHz)
- **Reset**: Async-assert, sync-release.
- **Pipeline depth**: 4 cycles:
  1. Capture inputs
  2. Brightness/contrast
  3. OSD blend
  4. Spectrum blend + output
- `de_out`/`hs_out`/`vs_out` are delayed by 4 cycles vs `de_in`/`hs_in`/`vs_in`.

## 5. Functional Behavior

### 5.1 Brightness/Contrast

```
gain = contrast / 128  (Q4.4 fixed point; contrast=128 → gain=1.0)
bias = brightness - 128  (-128..+127)

out = saturate( clamp(in + bias, 0, 255) * gain )
```

Implemented as:
1. `biased = clamp(in + bias, 0, 255)` (9-bit)
2. `tmp = biased * gain_q44` (9-bit × Q4.4 → Q12.4)
3. `out = tmp[15:8]` (upper 8 bits after 4 fractional bits discarded)

### 5.2 Alpha Blend

```
out = base + (top - base) * alpha / 255
```

Applied twice: first for OSD, then for spectrum.

### 5.3 Output

`rgb_out` and `de_out`/`hs_out`/`vs_out` are registered together.

## 6. Timing, Latency, and Throughput

- **Latency**: 4 cycles from input to output.
- **Throughput**: 1 pixel/cycle.
- **Alignment**: `de_out` rising edge aligns with `rgb_out` first valid pixel.
- All video modules must match this 4-cycle delay for `de`/`hs`/`vs`.

## 7. Assumptions and Chosen Defaults

- `brightness=128`, `contrast=128` are neutral (pass-through).
- Clamp prevents overflow from contrast > 128.
- Alpha=255: top layer fully opaque. Alpha=0: top layer transparent.

## 8. Edge Cases

- `de_in=0`: all blend stages pass through (no change).
- `contrast=0`: output = biased value (0 gain, effectively brightness only).
- `contrast=255`: gain = 255/128 ≈ 1.99.

## 9. Synthesis Notes

- **EG4 resource**: ~120 LUT4 + ~80 DFF. No BRAM, no multiplier.
- **Multiplier**: one 9×11 multiply per channel per cycle. Total 3 per cycle.
  At 25 MHz with 3 channels, 75 M multiplications/s — within EG4 budget.
- **Assumed IP**: None.

## 10. Verification Plan

1. **iverilog compile**: zero errors.
2. **Functional TB**:
   - Brightness=128, contrast=128: output == input.
   - Contrast=192: output = input * 1.5, clamped to 255.
   - Contrast=64: output = input * 0.5.
   - Brightness=200: output = input + 72, clamped.
   - OSD alpha=255: output = OSD RGB (base ignored).
   - OSD alpha=0: output = base (OSD ignored).
   - Spectrum layer blended on top of OSD.

## 11. Acceptance Criteria

- [x] All ports present, correct widths.
- [x] Brightness=128/contrast=128 is pass-through.
- [x] Contrast 128 → gain 1.0; 64 → 0.5; 192 → 1.5.
- [x] Brightness bias applied before contrast.
- [x] OSD blended with base via alpha.
- [x] Spectrum blended on top of OSD.
- [x] `de_out`/`hs_out`/`vs_out` delayed to match `rgb_out` (4 cycles).
- [x] No `TODO`/`FIXME`/`TBD`/`stub` in source.

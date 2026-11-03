> 2026-10-26：本模块已在仿真闭环修复中更新；以下为历史初版。当前行为与接口以 [闭环行为说明](behavior_spec.md) 和实际 RTL 为准。

# bilinear_scaler Behavior Specification

## 1. Requirement Summary

Bilinear interpolation scaler on the LOAD path. Scales any `src_w` × `src_h`
input pixel stream to fixed 640×480 top-down RGB888 output. Two ping-pong line
buffers store consecutive input rows for vertical interpolation. Q16.16 fixed-point
accumulators drive the phase. Bypass passthrough when source is already 640×480.

## 2. Public Interface

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| clk | in | 1 | System clock 50 MHz |
| rst_n | in | 1 | Async reset, active low |
| bypass | in | 1 | 1=pass through when src==640x480 |
| src_w | in | 11 | Source image width 1..1024 |
| src_h | in | 11 | Source image height 1..1024 |
| in_valid | in | 1 | Input pixel valid |
| in_rgb | in | 24 | Input pixel RGB |
| in_x | in | 11 | Input pixel column 0..src_w-1 |
| in_y | in | 11 | Input pixel row 0..src_h-1 |
| in_last | in | 1 | Last pixel of source image |
| out_valid | out | 1 | Output pixel valid |
| out_rgb | out | 24 | Output pixel RGB |
| out_x | out | 10 | Output column 0..639 |
| out_y | out | 10 | Output row 0..479 |
| out_last | out | 1 | Last pixel of output frame |

## 3. Clocking and Reset

- **Domain**: `clk_sys` (50.000 MHz)
- **Reset**: Async-assert, sync-release.
- **Throughput**: Processes input at system clock rate; output rate varies.

## 4. Functional Behavior

### 4.1 Bypass

When `bypass==1` and `src_w==640` and `src_h==480`, each input pixel is
forwarded to output with `out_valid=1`, `out_x=in_x[9:0]`, `out_y=in_y[9:0]`.

### 4.2 Line Buffer Filling

Input pixels are written into the current row buffer (`row_buf[buf_sel]`) as they
arrive. When a row completes (`in_y` changes), the buffers swap: `buf_sel`
toggles, `prev_row_n` records the completed row number.

Two consecutive rows must be buffered before scaling can begin.

### 4.3 Bilinear Interpolation

For each output pixel `(ox, oy)`:

```
sx_float = ox * src_w / 640
sy_float = oy * src_h / 480
sx0 = floor(sx_float),  sy0 = floor(sy_float)
fx  = sx_float - sx0    (0..65535)
fy  = sy_float - sy0    (0..65535)
```

Four surrounding source pixels `p00, p01, p10, p11` are read from the line
buffers. The bilinear blend is:

```
top  = p00 + (p01 - p00) * fx / 65536    (horizontal)
bot  = p10 + (p11 - p10) * fx / 65536    (horizontal)
out  = top + (bot - top) * fy / 65536    (vertical)
```

### 4.4 Output Pacing

Output pixels are generated only when both required source rows are available
in the line buffers. This means output is generated at the same average rate
as the input but with a one-row look-ahead.

### 4.5 Q16.16 Accumulators

`h_phase` increments by `h_step = src_w * 65536 / 640` each output column.  
`v_phase` increments by `v_step = src_h * 65536 / 480` each output row.  
Both reset to 0 at the start of each output frame.

## 5. Timing, Latency, and Throughput

- **Latency**: Variable. Input row N is buffered, then output rows referencing N
  are generated as subsequent input arrives.
- **Throughput**: Matches input pixel rate. Scales to output at the same average
  throughput, with buffering to handle bursts.
- **BRAM usage**: 2 × 1024 × 24-bit line buffers ≈ 48 Kbit.

## 6. Assumptions and Chosen Defaults

- `src_w` and `src_h` are stable during the image.
- Source pixels arrive in scanline order, no gaps.
- `in_x` resets to 0 at the start of each row.
- At most 1024 pixels per row.

## 7. Edge Cases

- **`src_w` or `src_h` = 1**: step accumulates slowly; interpolation degrades
  gracefully to nearest-neighbor.
- **`src_w` or `src_h` > 1024**: line buffers cap at 1024; results undefined.
- **`in_last` before rows 0 and 1 complete**: scale never starts, module goes to DONE.
- **Boundary pixels**: at the right/bottom edge, `sx1`/`sy1` clamp to `src_w-1`/`src_h-1`.

## 8. Synthesis Notes

- **EG4 resource**: ~400 LUT4 + ~200 DFF + 2 × 1024×24 ERAM.
- **Multiplier**: Two 21×32 multiplies for step calculation (once per frame),
  four 8×16 multiplies per output pixel for bilinear blend.
- **Assumed IP**: None.

## 9. Verification Plan

1. **iverilog compile**: zero errors.
2. **Functional TB**:
   - Bypass mode: output pixel == input pixel.
   - Known src: generate test image, verify scaled output size 640×480.
   - Check bilinear: diagonal edge should show smooth gradient.
   - Check boundary clamping.
   - Stress: random src_w/src_h 1..1024.

## 10. Acceptance Criteria

- [x] All ports present, correct widths.
- [x] Output is always 640×480 when not bypassing.
- [x] Bypass passes through unchanged when src==640x480.
- [x] Bilinear interpolation produces correct weighted blend.
- [x] Two-line buffer correctly provides consecutive rows.
- [x] `out_last` pulses on last output pixel.
- [x] No `TODO`/`FIXME`/`TBD`/`stub` in source.

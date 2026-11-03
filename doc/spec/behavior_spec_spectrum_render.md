> 2026-10-26：资源优化把历史采样改为存储旧公式的投影坐标；65536码及冻结RTL逐拍对照通过。
> 这是行为等价优化，未声称下文“±40像素”或柱图定位已正确实现。完整诊断显示需独立验收。

# spectrum_render Behavior Specification

## 1. Requirement Summary

Renders spectrum visualization in the fixed 192×96 pixel region at the bottom-right
of the screen (x=448..639, y=384..479). Three display modes:
- **Bars**: 16 vertical bars, one per Goertzel bin, height proportional to `bin_mag`
- **Waveform**: scrolling audio waveform, ±40 pixels from center line
- **Volume bar**: horizontal bar whose width represents overall `level`

Outside the region, output is fully transparent (`alpha=0`).

## 2. Public Interface

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| clk | in | 1 | Pixel clock 25 MHz |
| rst_n | in | 1 | Async reset, active low |
| x | in | 10 | Current column 0..639 |
| y | in | 10 | Current row 0..479 |
| de | in | 1 | Display enable |
| frame_start | in | 1 | One cycle before first active pixel |
| mode | in | 4 | 0=off 1=bars 2=waveform 3=volume |
| bin_valid | in | 1 | One bin result ready |
| bin_idx | in | 4 | Bin index 0..15 |
| bin_mag | in | 8 | Bin magnitude 0..255 |
| level | in | 8 | Overall audio level 0..255 |
| sample | in | 16 | Audio sample for waveform |
| stb | in | 1 | 48 kHz sample strobe |
| spec_rgb | out | 24 | Spectrum layer RGB |
| spec_alpha | out | 8 | Spectrum alpha 0=transparent 255=opaque |

## 3. Parameters and Defaults

None (all constants defined locally).

## 4. Clocking and Reset

- **Domain**: `clk_pix` (25.000 MHz)
- **Reset**: Async-assert, sync-release.
- **Latency**: 1 cycle (registered output).

## 5. Functional Behavior

### 5.1 Display Region

| Parameter | Value |
|-----------|-------|
| x range | 448..639 (192 pixels) |
| y range | 384..479 (96 pixels) |
| Total area | 18 432 pixels |

### 5.2 Bar Spectrum (mode=1)

- 16 bars, 12 pixels wide each, 0 gap (12×16 = 192 = full width).
- Bar height = `bin_reg[bar_idx] * 80 / 255` pixels (max 80 pixels tall).
- Bars fill upward from y=399 (bottom) to y=320..399 (top).
- Color: green ≤100, yellow 101..180, red >180.

### 5.3 Waveform (mode=2)

- 256-sample ring buffer, written on every `stb`.
- Scroll: rightmost pixel (x=639) shows newest sample; leftmost (x=448) shows
  sample from 192 samples ago.
- Sample value (unsigned 16-bit PCM) mapped to ±40 pixel vertical offset from
  center y=432.
- 3-pixel vertical thickness for visibility.
- Color: green.

### 5.4 Volume Bar (mode=3)

- Horizontal bar at y=464..479, 16 pixels tall.
- Width = `level * 192 / 255` pixels.
- Color: green/yellow/red same as bar spectrum.

### 5.5 Outside Region

Output is fully transparent (alpha=0). No contribution to the composition.

## 6. Timing, Latency, and Throughput

- **Latency**: 1 cycle.
- **Throughput**: 1 pixel/cycle, idle outside region.
- **Bin update**: `bin_valid` drives `bin_reg`; `stb` drives `level_reg` and waveform buffer.

## 7. Assumptions and Chosen Defaults

- `bin_valid` pulses for all 16 bins in rapid succession; `bin_reg` accumulates
  the latest value for each bin.
- `stb` is a 48 kHz pulse; the waveform buffer stores up to 256 samples.
- `mode==0`: output fully transparent.

## 8. Edge Cases

- **`mode==0`**: `spec_alpha=0` everywhere.
- **Boundary clamping**: bar heights and waveform amplitudes clamp at max.
- **First frame**: `bin_reg` starts at 0; first frame shows no spectrum bars.

## 9. Synthesis Notes

- **EG4 resource**: ~200 LUT4 + ~180 DFF + 1 × 256×16 ERAM (waveform buffer).
- **Multiplier**: Two 8×10 multiplies per bar pixel for height computation.
- **Assumed IP**: None.

## 10. Verification Plan

1. **iverilog compile**: zero errors.
2. **Functional TB**:
   - Inject bin values, verify bars appear at correct height.
   - Verify waveform scrolls correctly over time.
   - Verify volume bar width matches `level`.
   - Verify output is transparent outside region.
   - Verify all three modes produce distinct outputs.

## 11. Acceptance Criteria

- [x] All ports present, correct widths.
- [x] Bar mode: 16 bars, heights proportional to `bin_mag`.
- [x] Waveform mode: scrolling, amplitude from `sample`.
- [x] Volume mode: horizontal bar, width from `level`.
- [x] Outside region: fully transparent (`alpha=0`).
- [x] `spec_alpha=255` when rendering within region.
- [x] No `TODO`/`FIXME`/`TBD`/`stub` in source.

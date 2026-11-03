> 2026-10-26：本模块已在仿真闭环修复中更新；以下为历史初版。当前行为与接口以 [闭环行为说明](behavior_spec.md) 和实际 RTL 为准。

# video_timing Behavior Specification

## 1. Requirement Summary

Generate precise 640×480@60 VGA timing on `clk_pix` (25.000 MHz):
- Horizontal total: 800 pixels (active + front porch + sync + back porch)
- Vertical total: 525 scanlines
- HS/VS negative polarity, DE active-high
- Outputs per-pixel coordinates `x[9:0]` and `y[9:0]` valid only within the active region
- One-cycle `frame_start` / `line_start` pulses one cycle before the first active pixel

## 2. Public Interface

| Port      | Dir | Width | Description                                              |
|-----------|-----|-------|----------------------------------------------------------|
| clk       | in  | 1     | Pixel clock 25.000 MHz                                    |
| rst_n     | in  | 1     | Async reset, active low                                   |
| de        | out | 1     | Display enable, active high within 640×480 region         |
| hs        | out | 1     | Horizontal sync, negative polarity                        |
| vs        | out | 1     | Vertical sync, negative polarity                          |
| x         | out | 10    | Active column 0..639; holds last value outside region     |
| y         | out | 10    | Active row 0..479; holds last value outside region       |
| frame_start | out | 1   | One-cycle pulse, one cycle before first active pixel      |
| line_start | out | 1    | One-cycle pulse, one cycle before first pixel of each line |
| frame_cnt | out | 16    | Increments on falling edge of VS                         |

## 3. Parameters and Defaults

| Parameter  | Default | Description                            |
|------------|---------|----------------------------------------|
| H_ACT      | 640     | Active width in pixels                 |
| H_FP       | 16      | Horizontal front porch                 |
| H_SYNC     | 96      | Horizontal sync pulse width             |
| H_BP       | 48      | Horizontal back porch                   |
| V_ACT      | 480     | Active height in scanlines             |
| V_FP       | 10      | Vertical front porch                   |
| V_SYNC     | 2       | Vertical sync pulse width              |
| V_BP       | 33      | Vertical back porch                   |

Derived: `H_TOTAL = H_ACT+H_FP+H_SYNC+H_BP = 800`; `V_TOTAL = V_ACT+V_FP+V_SYNC+V_BP = 525`.

## 4. Clocking and Reset

- **Domain**: `clk_pix` (25.000 MHz)
- **Reset**: Async assert, sync release via external `rst_n` (from `rst_sync`).
- **Assumption**: Pixel clock derived from `clk_wize` PLL C1, exactly 25.000 MHz.
  If the oscillator is not 25 MHz, these parameter values need adjustment.

## 5. Functional Behavior

### 5.1 Horizontal Counter

Counts 0 → H_TOTAL−1 repeatedly. `h_end` is high only when `h_cnt == H_TOTAL−1`.

### 5.2 Vertical Counter

Increments on every `h_end` (end of each scanline). Counts 0 → V_TOTAL−1 repeatedly.

### 5.3 Sync Generation

- `hs` = 0 (active low) when `H_ACT ≤ h_cnt < H_ACT+H_SYNC`; otherwise 1.
- `vs` = 0 when `V_ACT ≤ v_cnt < V_ACT+V_SYNC`; otherwise 1.

### 5.4 Display Enable

`de` = 1 only when `h_cnt < H_ACT` and `v_cnt < V_ACT`.

### 5.5 Coordinates

- `x` increments from 0 at the start of each active line, holds last value
  during porch and sync.
- `y` increments from 0 at the first active line, holds last value during
  vertical porch and sync.
- Both reset to 0.

### 5.6 Frame Counter

`frame_cnt` increments on the falling edge of `vs` (detected by `!vs && vs_d1`),
i.e., at the start of each new frame.

### 5.7 Edge Pulses

- `line_start` = `h_end`: fires at the end of each scanline; the next
  `clk` cycle is the first active pixel of the next line.
- `frame_start` = `h_end && v_cnt==0`: fires at the end of line 0; the next
  cycle is the first active pixel of the frame.

## 6. Timing, Latency, and Throughput

- **Latency**: 0 — outputs are combinationally derived from counters.
- **Throughput**: 1 pixel per clock cycle (640×480 active, blanking idle).
- **Timing budget**: 40 ns per cycle at 25 MHz, trivial for counter logic.
- **Pipeline alignment**: `de`, `hs`, `vs`, `x`, `y` all update in the same
  cycle. `frame_start` and `line_start` are one-cycle pulses aligned to the
  clock edge just before the event they describe.

## 7. Assumptions and Chosen Defaults

- Pixel clock is exactly 25.000 MHz. If different, `H_TOTAL`/`V_TOTAL` must
  be recalculated to maintain 60 Hz ± tolerance.
- Reset is async-assert, sync-release. `rst_n` is held low for sufficient cycles
  to cover at least one full frame.
- `frame_cnt` starts at 0 and overflows after 65535 frames (~18 minutes at 60 Hz).

## 8. Edge Cases

- **Reset mid-frame**: Counters restart from 0; `frame_cnt` does not increment
  during reset even if `vs` would have fallen.
- **rst_n assertion during blanking**: Counters freeze; on release they
  continue from wherever they are (may cause a brief glitch in sync).
- **Frame start after reset**: On the very first `h_end` where `v_cnt==0`,
  `frame_start` fires normally. No special handling needed.

## 9. Synthesis Notes

- **EG4 resource**: ~30 LUT4 + ~30 DFF. Negligible.
- **No IP required**: Pure counter/compare logic.
- **Multiplier**: None.
- **BRAM**: None.

## 10. Verification Plan

1. **iverilog compile**: zero errors.
2. **Functional TB assertions**:
   - `de` is high exactly 640×480 cycles per frame.
   - `hs` pulse width = H_SYNC = 96 cycles, negative polarity.
   - `vs` pulse width = V_SYNC = 2 lines, negative polarity.
   - `x` == 0 at the cycle immediately after `line_start`.
   - `y` == 0 at the cycle immediately after `frame_start`.
   - `frame_start` fires once per frame.
   - `line_start` fires 525 times per frame.
3. **Phase check**: `de` rising edge aligns with `x` transitioning to 0.

## 11. Acceptance Criteria

- [x] `de` is high for exactly 640 consecutive cycles, 480 times per frame.
- [x] `hs` is low for 96 cycles every line, high for 704 cycles.
- [x] `vs` is low for 2 full lines every frame.
- [x] `x` counts 0..639 within the active region and holds outside.
- [x] `y` counts 0..479 within the active region and holds outside.
- [x] `frame_start` is a one-cycle pulse exactly once per frame.
- [x] `line_start` is a one-cycle pulse exactly once per line.
- [x] `frame_cnt` increments every frame.
- [x] No `TODO`/`FIXME`/`TBD`/`stub` in source.

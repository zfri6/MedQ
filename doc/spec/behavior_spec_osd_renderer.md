> 2026-10-26：本模块已在仿真闭环修复中更新；以下为历史初版。当前行为与接口以 [闭环行为说明](behavior_spec.md) 和实际 RTL 为准。

# osd_renderer Behavior Specification

## 1. Requirement Summary

Line-buffered OSD text renderer with ping-pong line buffers for up to 16 text fields.
While displaying line N, the module renders line N+1 into the opposite buffer.
On `line_start`, the buffers swap: the just-rendered line becomes the display source.

Each field has: position, scale (1x/2x/3x/4x), RGBA color, optional blink,
character string base pointer, and length. The font ROM provides glyph bitmaps.

Font ROM read has 1-cycle latency, so the total pipeline depth is 2 cycles.
`de` / `hs` / `vs` are delayed by 2 cycles to remain aligned with `osd_rgb`.

## 2. Public Interface

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| clk | in | 1 | Pixel clock 25 MHz |
| rst_n | in | 1 | Async reset, active low |
| x | in | 10 | Pixel column 0..639 |
| y | in | 10 | Pixel row 0..479 |
| de | in | 1 | Display enable |
| line_start | in | 1 | One cycle before first pixel of line |
| frame_start | in | 1 | One cycle before first pixel of frame |
| frame_cnt | in | 16 | Frame counter for blink phase |
| qstate | in | 128 | Queue state bus (consumed by upper layers) |
| param | in | 64 | Parameter bus |
| cfg_we | in | 1 | Write enable for config port |
| cfg_addr | in | 10 | Config address (see below) |
| cfg_wdata | in | 32 | Config write data |
| font_addr | out | 14 | Font ROM address |
| font_dout | in | 32 | Font ROM row data |
| osd_rgb | out | 24 | OSD pixel RGB |
| osd_alpha | out | 8 | OSD pixel alpha 0=transparent 255=opaque |

## 3. Configuration Port Layout

| Address range | Content | Width per entry |
|---|---|---|
| 0..319 | Character RAM | 12-bit glyph index per slot |
| 512..527 | Field entries | 32-bit each |
| 640..655 | Field colors | 32-bit RGBA each |

### Field entry format `[31:0]`

| Bits | Name | Description |
|------|------|-------------|
| 0 | enable | 1=field active |
| 10:1 | x | Left edge in pixels 0..639 |
| 20:11 | y | Top edge in rows 0..479 |
| 22:21 | scale | 0=1x 1=2x 2=3x 3=4x |
| 26:23 | len | Number of characters 1..15 |
| 27 | blink_en | Blink enable |
| 31:27 | char_base>>3 | Character RAM base address (>>3, 5 bits) |

### Color entry format `[31:0]`

`[31:24]`=alpha, `[23:16]`=R, `[15:8]`=G, `[7:0]`=B.

## 4. Field Geometry

- Width = `len * 8 * scale` pixels
- Height = `16 * scale` pixels (all glyphs use 16-row bitmap height)
- Characters are arranged left-to-right within the field

## 5. Clocking and Reset

- **Domain**: `clk_pix` (25.000 MHz)
- **Reset**: Async-assert, sync-release.
- **Pipeline depth**: 2 cycles (font ROM read = 1 cycle, line buffer read = 1 cycle).
  `de`, `hs`, `vs` are delayed by 2 cycles to match `osd_rgb`/`osd_alpha`.

## 6. Functional Behavior

### 6.1 Ping-Pong Line Buffer

Two banks of 640×32-bit registers (`lbuf[0]` and `lbuf[1]`).  
`buf_sel` = 0: `lbuf[0]` = render target, `lbuf[1]` = display source.  
`buf_sel` flips on every `line_start`.

### 6.2 Rendering During Blanking

`render_en = !de && (render_y < 480)`. While the display is in blanking
(H-blank or V-blank), the FSM renders the next line into the current
render buffer. Rendering 640 pixels takes 640 cycles, well within the
800-cycle total line period.

### 6.3 Font ROM Address

Three segments:

| Segment | Glyph indices | Addr formula |
|---------|---------------|--------------|
| ASCII 8×16 | 0..95 | `{2'b00, glyph[5:0], pix_y[3:0]}` |
| Chinese 16×16 | 96..223 | `14'd384 + {glyph[6:0], pix_y[3:0]}` |
| Large 32×48 | 224.. | `14'd1408 + {glyph[5:0], pix_y[3:0]}` |

Pix_y selects which of the 16 rows within the glyph. For Chinese (32 rows) and
Large (48 rows), only the upper 16 rows are accessible at a time; full support
for tall glyphs requires additional row banking (future extension).

### 6.4 Blink

`blink = frame_cnt[6]` toggles at ~1 Hz at 60 fps. Fields with `blink_en=1`
are invisible on odd blink phases.

### 6.5 Priority

Field 0 has highest priority. When multiple fields overlap, the lowest-numbered
active field wins.

## 7. Timing, Latency, and Throughput

- **Render pipeline latency**: 0 cycles (render is in blanking, independent of display).
- **Display pipeline latency**: 2 cycles (font ROM 1 + buffer read 1).
- **de alignment**: `osd_rgb`/`osd_alpha` are delayed by 2 cycles vs `x`/`y`/`de`.
- **Resource**: Two 640×32-bit BRAM for ping-pong line buffers.

## 8. Assumptions and Chosen Defaults

- All glyphs have 16-pixel height. Chinese (16×16) and Large (32×48) are
  rendered using only their top 16 rows; full height support is future work.
- At least one full frame after reset is required before the first valid OSD
  output (lines are rendered during the previous frame's VBI).
- `blink = frame_cnt[6]` gives ~0.5 Hz toggle at 60 fps (1 second per full cycle).

## 9. Edge Cases

- **`cfg_we` during active display**: writes go to RAM/registers; no hazard with rendering.
- **`render_x` overflow**: capped at 639.
- **Overlapping fields**: priority encoder selects lowest-index field.
- **Empty field (len=0 or char_base out of range)**: field contributes no pixels.

## 10. Synthesis Notes

- **EG4 resource**: ~500 LUT4 + ~300 DFF + 2 × 640×32 ERAM (line buffers).
- **Multiplier**: None (division by constant scale, implemented as shifts).
- **Assumed IP**: None.

## 11. Verification Plan

1. **iverilog compile**: zero errors.
2. **Functional TB**:
   - Write a field config and verify the correct pixel appears at the right position.
   - Verify priority: field 0 occludes field 1.
   - Verify scale 1x/2x doubles the visual size.
   - Verify blink toggles field visibility.
   - Verify `osd_alpha` is 0 outside OSD regions.
   - Verify line buffer swap on `line_start`.

## 12. Acceptance Criteria

- [x] All ports present, correct widths, match `interface_contract.yaml`.
- [x] 16 fields configurable via cfg_* port.
- [x] Ping-pong line buffer swaps on every `line_start`.
- [x] Font ROM read with 1-cycle latency, 2-cycle total display pipeline.
- [x] `osd_rgb` and `osd_alpha` aligned with `de` (same delay).
- [x] Blink works at ~1 Hz.
- [x] No `TODO`/`FIXME`/`TBD`/`stub` in source.

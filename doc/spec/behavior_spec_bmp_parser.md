> 2026-10-26：本模块已在仿真闭环修复中更新；以下为历史初版。当前行为与接口以 [闭环行为说明](behavior_spec.md) 和实际 RTL 为准。

# bmp_parser Behavior Specification

## Requirement Summary

Tolerant BMP file parser. Validates BMP header, handles arbitrary bfOffBits (palette/ext header skip), negative biHeight (top-down), 4-byte row alignment padding, 24/32-bit depth, BI_RGB compression only. Outputs top-down RGB888 pixel stream.

## Public Interface

| Port       | Direction | Width | Description |
|------------|-----------|-------|-------------|
| clk        | in        | 1     | System clock, 50 MHz |
| rst_n      | in        | 1     | Async reset, active low |
| start      | in        | 1     | Start parsing (single-cycle pulse) |
| in_valid   | in        | 1     | Input byte valid |
| in_data    | in        | 8     | Input byte |
| hdr_valid  | out       | 1     | Header parsed, single-cycle pulse |
| img_width  | out       | 11    | Decoded image width |
| img_height | out       | 11    | Decoded image height (absolute value) |
| img_bpp    | out       | 6     | Bits per pixel |
| img_topdown| out       | 1     | 1=top-down, 0=bottom-up |
| px_valid   | out       | 1     | Pixel output valid |
| px_rgb     | out       | 24    | {R,G,B} — top-down order |
| px_x       | out       | 11    | Column 0..img_width-1 |
| px_y       | out       | 11    | Row in top-down order (0=top) |
| done       | out       | 1     | Done, single-cycle pulse |
| err        | out       | 1     | Error, single-cycle pulse |
| err_code   | out       | 4     | 1=nonBM 2=comp 3=bpp 4=size 5=truncated |

## Clocking and Reset

- Domain: clk_sys (50 MHz)
- Reset: rst_n active low, async assert, sync release

## Functional Behavior

### Parse Stages

```
IDLE → PARSE_HDR → SKIP_DATA → PARSE_PIXELS → DONE/ERR
```

#### PARSE_HDR
Read first 54 bytes (minimum BMP header):
- Bytes 0..1: `bfType` → must be 'BM' (0x42, 0x4D). If not, err_code=1.
- Bytes 2..5: `bfSize` (total file size, 32-bit LE).
- Bytes 6..9: `bfReserved1,2` (ignore).
- Bytes 10..13: `bfOffBits` (pixel data start offset, 32-bit LE). Used to skip to pixel data.
- Bytes 14..17: `biSize` (InfoHeader size). For BITMAPINFOHEADER = 40.
- Bytes 18..21: `biWidth` (32-bit LE, signed 32-bit → truncate to 11 bits, max 2047).
- Bytes 22..25: `biHeight` (32-bit LE, signed). Negative = top-down. Store sign.
- Bytes 26..27: `biPlanes` must be 1.
- Bytes 28..29: `biBitCount` → must be 24 or 32. If not, err_code=3.
- Bytes 30..33: `biCompression` → must be 0 (BI_RGB). If 1/2/3, err_code=2.
- Bytes 34..37: `biSizeImage` (pixel data size, may be 0 for BI_RGB).
- Bytes 38..41: `biXPelsPerMeter` (ignore).
- Bytes 42..45: `biYPelsPerMeter` (ignore).
- Bytes 46..49: `biClrUsed` (ignore, palette colors used).
- Bytes 50..53: `biClrImportant` (ignore).

Validate:
- bfType = 'BM'.
- biCompression = 0.
- biBitCount = 24 or 32.
- img_width ≤ 1024 and img_height ≤ 1024. If >1024, err_code=4.

After validation: hdr_valid=1, store img_width, img_height(|biHeight|), bpp, topdown flag.

#### SKIP_DATA
Read (bfOffBits - 54) bytes and discard. These are palette or DIB extension header bytes.

#### PARSE_PIXELS
Read pixel rows. For each row:
- Read (img_width × bpp/8) pixel bytes.
- Pad row to 4-byte boundary: `(bpp/8 * img_width + 3) & ~3` bytes per row.
- For 24-bit: each pixel is BGR (3 bytes). Convert BGR→RGB.
- For 32-bit: each pixel is BGRA (4 bytes). Ignore alpha, convert BGR→RGB.
- Output px_rgb = {R,G,B}, px_x = column, px_y = row number (always top-down).
- For bottom-up (biHeight>0): invert y = (img_height - 1 - row).

Row counter increments after each full row.

#### DONE
- done=1 pulse.
- FSM returns to IDLE.

### Pixel Coordinate System

- px_x: 0..img_width-1
- px_y: 0 (top) .. img_height-1 (bottom) — always top-down output regardless of file orientation.

## Timing, Latency, and Throughput

- Header parse: 54 cycles (1 byte/cycle).
- Pixel output: 1 pixel per bpp/8 cycles.
- Row padding discarded inline.

## Assumptions and Chosen Defaults

- BMP file data is byte-aligned at input; this module consumes one byte per cycle.
- Caller provides continuous byte stream without back-pressure.
- Only BI_RGB (uncompressed) is supported.

## Edge Cases and Error Handling

- err_code=1: bfType != 'BM'.
- err_code=2: biCompression != 0.
- err_code=3: biBitCount not 24 or 32.
- err_code=4: img_width > 1024 or img_height > 1024.
- err_code=5: input stream ends before all pixels received.

## Synthesis Notes

- Target: EG4S20.
- No BRAM needed; streaming design.
- FSM ~8 states.
- Estimated LUT4: ~200–300.

## Verification Plan

1. Valid 24-bit BMP, top-down, no padding → verify px_rgb order.
2. Valid 24-bit BMP, bottom-up → verify px_y is inverted.
3. Valid 32-bit BMP with alpha → verify alpha ignored, RGB correct.
4. BMP with row padding → verify padding bytes discarded, px_x resets.
5. Invalid bfType → err_code=1.
6. biCompression=1 (RLE8) → err_code=2.
7. img_width=2048 → err_code=4.
8. Truncated file → err_code=5.

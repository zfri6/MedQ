> 2026-10-26：本模块已在仿真闭环修复中更新；以下为历史初版。当前行为与接口以 [闭环行为说明](behavior_spec.md) 和实际 RTL 为准。

# frame_reader Behavior Specification

## 1. Requirement Summary

Read pixel data from SDRAM and stream it to the pixel pipeline at exactly the
rate demanded by the 640×480@60 display timing.  
Two clock domains: `clk_pix` (pixel output / control) and `clk_mem` (SDRAM burst
transactions).  
Async FIFO bridges the domains with minimum depth of 2 rows (≥1280 words).  
Underrun during `de==1` outputs solid magenta and asserts `underrun`.

## 2. Public Interface

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| clk_pix | in | 1 | Pixel clock 25 MHz |
| rst_n_pix | in | 1 | Reset for pixel domain |
| clk_mem | in | 1 | SDRAM clock 100 MHz |
| rst_n_mem | in | 1 | Reset for SDRAM domain |
| fb_base | in | 22 | Frame buffer base word address, sampled at frame_start |
| frame_start | in | 1 | One cycle before first active pixel |
| line_start | in | 1 | One cycle before first pixel of each line |
| de | in | 1 | Display enable from video_timing |
| px_rgb | out | 24 | Pixel RGB, or magenta on underrun |
| underrun | out | 1 | High while outputting underrun pixels |
| disp_req_valid | out | 1 | Burst request valid |
| disp_req_ready | in | 1 | Arbitration grant |
| disp_req_addr | out | 22 | Burst start address (word) |
| disp_req_we | out | 1 | 0 = read |
| disp_req_len | out | 9 | Burst length in words (1..256) |
| disp_wr_valid | out | 1 | Write-data valid |
| disp_wr_ready | in | 1 | Write-data accepted |
| disp_wr_data | out | 32 | Write data |
| disp_rd_valid | in | 1 | Read-data valid |
| disp_rd_ready | out | 1 | Read-data accepted |
| disp_rd_data | in | 32 | Read data |

## 3. Clocking and Reset

- `clk_pix` domain: control FSM, pixel output, FIFO read pointer, read-side CDC.
- `clk_mem` domain: SDRAM transactions, FIFO write pointer.
- Reset is async-assert, sync-release from `rst_sync`. Each domain has its own
  `rst_n` input.
- `fb_base` is sampled into an internal register on `frame_start`.

## 4. Functional Behavior

### 4.1 Line Prefetch FSM

State machine on `clk_pix`:

| State | Description |
|-------|-------------|
| IDLE | Waiting for first `frame_start` to capture `fb_base` |
| PREFETCH | `line_start` triggers burst request for the next row |
| READING | Waiting for next `line_start` to prefetch the following row |

- `prefetch_y` tracks which row to fetch next (0..479).  
  On each `line_start`, the FSM issues a burst for row `prefetch_y`, then
  increments `prefetch_y` (wrapping 479→0).
- On `frame_start`, `fb_base` is re-sampled and `prefetch_y` resets to 0.

### 4.2 Burst Generation

Each active row (640 pixels = 640 words = 256+256+128) is fetched as up to
three back-to-back SDRAM bursts:

| Burst | Length | Address offset |
|-------|--------|---------------|
| 0 | 256 | row_base + 0 |
| 1 | 256 | row_base + 256 |
| 2 | 128 | row_base + 512 |

`disp_req_valid` is held high until `disp_req_ready` is asserted; then the
FSM moves to the next burst. `disp_req_len` carries the burst length.

### 4.3 Async FIFO

- Dual-port BRAM inferred for storage.
- Write side (`clk_mem`): `disp_rd_valid` increments write pointer.
- Read side (`clk_pix`): one word consumed per `clk_pix` cycle when `de==1`.
- Read/write pointers cross clock domains via Gray-code CDC.
- Depth: 1024 words (≈1.6 lines), well above the 2-line minimum.

### 4.4 Underrun Handling

When `de==1` and the FIFO is empty: output solid magenta (`24'hFF00FF`) and
set `underrun` high. `underrun` stays high until the next `de==0` (blanking).

### 4.5 Pixel Output Format

SDRAM stores one pixel per 32-bit word: `{8'h00, R[7:0], G[7:0], B[7:0]}`.
The lower 24 bits are forwarded as `px_rgb`.

## 5. Timing, Latency, and Throughput

- **Latency**: 1 cycle through FIFO (synchronous read).
- **Throughput**: 640 pixels/line × 480 lines = 307 200 pixels/frame; 60 fps.
- **SDRAM bandwidth**: 307 200 × 60 = 18.43 MWord/s ≈ 18.4% of 100 MHz SDRAM peak.
- **FIFO fill requirement**: FIFO must contain ≥640 words before the first
  active pixel of a line. This is guaranteed by issuing the burst one line
  ahead via `line_start`.

## 6. Assumptions and Chosen Defaults

- SDRAM supports ≥256-word linear bursts. If max burst < 256, the burst
  counter must split into smaller chunks (see R1 in `risks.md`).
- `disp_req_ready` is granted within reasonable time (a few SDRAM cycles).
- `disp_rd_valid` follows the request within predictable latency; the FIFO
  depth absorbs worst-case SDRAM round-trip delay.
- Pixel format: one pixel per 32-bit word, top-down row order.

## 7. Edge Cases

- **Underrun on first line**: If `frame_start` has not yet fired when the
  first `de` cycle arrives, the FIFO is empty → magenta output.
- **Rapid fb_base changes**: `fb_base` is only sampled at `frame_start`. The
  row currently being prefetched uses the old `fb_base_r`. The new `fb_base`
  takes effect from the next `frame_start`.
- **FIFO overflow**: `disp_rd_ready` is de-asserted when FIFO is nearly full.
  The SDRAM controller must back-pressure accordingly.

## 8. Synthesis Notes

- **EG4 resource**: ~200 LUT4 + ~180 DFF for FSM + CDC; BRAM: 1 × 1024×32
  (≈32 Kbit), inferred from dual-port RAM.
- **No hard IP required**; inferred BRAM is inferred from `fifo_mem`.
- **Multiplier**: None.
- **Assumed IP**: None (all behavioral).

## 9. Verification Plan

1. **iverilog compile**: zero errors.
2. **Functional TB**:
   - Drive `fb_base`, `frame_start`, `line_start`, `de` as per 640×480 timing.
   - Connect `disp_*` to a behavioral SDRAM model that returns random pixels.
   - Assert `px_rgb` always valid when `de==1` (or magenta with `underrun`).
   - Assert `underrun` is never high without a real FIFO underrun condition.
   - Verify burst addresses are sequential within each row.
   - Verify `underrun` is pulsed correctly when the SDRAM model stalls.
3. **Phase check**: the first `px_rgb` after `de` rises matches the first word
   at `fb_base + 0`.

## 10. Acceptance Criteria

- [x] All ports present and match `interface_contract.yaml` exactly.
- [x] `px_rgb` outputs valid pixels whenever `de==1` (or magenta on underrun).
- [x] `underrun` asserted within one cycle of FIFO empty during `de`.
- [x] Burst requests are exactly 256+256+128 words per row, in-order.
- [x] `fb_base` sampled only at `frame_start`.
- [x] FIFO CDC uses Gray-code, no metastability path.
- [x] No `TODO`/`FIXME`/`TBD`/`stub` in source.

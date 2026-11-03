> 2026-10-26：本模块已在仿真闭环修复中更新；以下为历史初版。当前行为与接口以 [闭环行为说明](behavior_spec.md) 和实际 RTL 为准。

# audio_pcm_player Behavior Specification

## Requirement Summary

Play back pre-loaded 16 kHz 16-bit mono PCM audio from SDRAM AUDIO_POOL, upsample to 48 kHz via 3x linear interpolation, and output signed 16-bit PCM samples on every 48 kHz `stb`. The module crosses from `clk_mem` (SDRAM) to `clk_pix` (audio output) and includes underrun detection for the critical R7 audio risk.

## Public Interface

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk_pix` | in | 1 | Pixel clock, 25.000 MHz |
| `rst_n_pix` | in | 1 | Async reset, low-active (clk_pix domain) |
| `clk_mem` | in | 1 | SDRAM clock, 100 MHz |
| `rst_n_mem` | in | 1 | Async reset, low-active (clk_mem domain) |
| `stb` | in | 1 | 48 kHz sample gate |
| `play_req` | in | 1 | Start playback (single-cycle pulse, clk_pix) |
| `play_base` | in | 22 | Word address in AUDIO_POOL |
| `play_samples` | in | 22 | Number of 16 kHz samples |
| `play_busy` | out | 1 | Playback in progress |
| `play_done` | out | 1 | Single-cycle pulse on playback end |
| `sample` | out | 16 | Signed 16-bit output at 48 kHz |
| `underrun` | out | 1 | FIFO ran dry; stays high until next play_req |
| `aud_req_*` | (see below) | | SDRAM master port (clk_mem domain) |
| `aud_rd_*` | (see below) | | SDRAM read data return (clk_mem domain) |

## Parameters

No module parameters. All values are run-time.

## Clocking and Reset

- `clk_pix`: 25.000 MHz — audio output domain, interpolation, control FSM
- `clk_mem`: 100.000 MHz — SDRAM master port, FIFO write side, request FSM
- Both resets are async assert / sync release, active low
- The FIFO IP uses active-HIGH async reset internally (converted via `fifo_rst = ~rst_n_mem`)

## Functional Behavior

### 1. Playback Request CDC

`play_req` is a single-cycle pulse in `clk_pix`. It is captured in a `play_req_latch` register, synchronized to `clk_mem` via 3-stage FF chain, and acknowledged back to `clk_pix` via a 3-stage ack chain. Parameters (`play_base`, `play_samples`) are stable during the handshake.

### 2. SDRAM Request State Machine (clk_mem)

- `M_IDLE`: waiting for `req_start_mem` (play request from clk_pix)
- `M_REQ`: asserting `aud_req_valid`; wait for `aud_req_ready`
- `M_READ`: accepting `aud_rd_valid` data into FIFO; count words received
- `M_WAIT`: brief drain period
- `M_DONE`: assert `ack_mem`, transition to `M_IDLE`

Request length = `ceil(play_samples / 2) + 8` words (margin for pipeline).

### 3. Async FIFO

- **Width conversion**: 32-bit SDRAM word → 32-bit output (no conversion needed)
- **Depth**: 1024 words = 2048 samples ≈ 42.7 ms at 48 kHz (well above 10.7 ms requirement)
- **Type**: AL IP `afifo_8i_32o_1024` (already present in `rtl/al_ip/`)
- **Mode**: Show-ahead, no output register — `valid` is combinatorial

### 4. 3x Linear Interpolation (clk_pix)

Source: 16 kHz, 2 samples per word `{s1, s0}`. Output: 48 kHz.

Algorithm:
- `interp_frac` Q14 accumulator, step = floor(16384/3) = 5461
- Each `stb`: `interp_frac += 5461`
- If `interp_frac >= 16384`: overflow → advance to next word, `interp_frac -= 10923` (i.e., `frac - (16384 - step)`)
- `sample = s0 + (diff × frac) >> 14`, where `diff = s1 - s0`
- Clamp to signed 16-bit range

This produces exactly 3 output samples per input sample pair, converting 16 kHz → 48 kHz.

### 5. Status Outputs

| Signal | Domain | Meaning |
|--------|--------|---------|
| `play_busy` | clk_pix | High during M_REQ/M_READ/M_WAIT/M_DONE in clk_mem |
| `play_done` | clk_pix | Single-cycle pulse when playback finishes |
| `underrun` | clk_pix | FIFO empty when output needed; stays high until next play_req |
| `sample` | clk_pix | Signed 16-bit PCM; 0 when underrun or idle |

## Latency and Throughput

- **SDRAM request latency**: ~5–10 `clk_mem` cycles (typical)
- **FIFO propagation**: 1 `clk_mem` → `clk_pix` crossing per word
- **Interpolation**: 1 `clk_pix` cycle per sample
- **Total audio latency from request to first sample**: ~20–30 cycles (~0.8–1.2 µs)

## Assumptions and Chosen Defaults

- `aud_req_len` ≤ 256 (fits within SDRAM burst limit)
- Audio素材预载入到 SDRAM 在播放前已完成；asset_loader 负责先决条件
- FIFO 始终有足够数据（至少 512 样本），因aud有最高 SDRAM 优先级

## Edge Cases and Error Handling

- **FIFO empty during playback**: `underrun <= 1`, output silence, playback continues until `play_samples` exhausted
- **play_req while already playing**: ignored (play_req_latch guards)
- **play_req at exact moment of play_done**: next request handled next cycle
- **play_samples = 0**: transition to DONE immediately without SDRAM access
- **SDRAM returns fewer words than requested**: FIFO drains, playback ends at FIFO empty

## Synthesis Notes

- **Async FIFO**: `afifo_8i_32o_1024` (AL IP, already present) — no inferred RAM
- **Multiplier**: one 16×16 → 31-bit for interpolation (`diff × frac`)
  - TD maps to 1 DSP block
- **Resources**: ~800 LUT4 + 1 DSP + 1 FIFO BRAM ≈ well within E-group budget
- **Clock domains**: `clk_pix` and `clk_mem` are independent; all CDC is explicit

## Verification Plan

1. **Functional playback**: feed a known pattern (e.g., 440 Hz sine) into SDRAM; assert output frequency and amplitude match ±1%.
2. **Underrun**: load a short clip (e.g., 200 samples), assert `underrun` goes high before playback ends.
3. **CDC handshake**: assert `play_busy` and `play_done` are correctly synchronised to `clk_pix`.
4. **3x interpolation correctness**: for input `{s0=0, s1=32767}`, assert the three interpolated values are approximately `{0, 10922, 21845}`.
5. **Reset**: after `rst_n` drop, all state clears, no spurious SDRAM requests.

## Acceptance Criteria

- [ ] Playback of a known 1 kHz sine (pre-loaded to SDRAM) outputs at 1 kHz ± 0.5%.
- [ ] `play_done` fires exactly once per playback session.
- [ ] `underrun` asserts when FIFO empties mid-playback.
- [ ] Reset clears all internal state and stops SDRAM requests.
- [ ] RTL compiles with iverilog and ModelSim with zero errors.

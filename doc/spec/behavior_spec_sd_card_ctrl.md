# sd_card_ctrl Behavior Specification

## Requirement Summary

SD card SPI-mode initialization (74+ idle clocks → CMD0 → CMD8 → ACMD41 loop → CMD58 check CCS → CMD16 for SDSC) and sector read (CMD17). Timeout on each init step. Reports card_ready / card_sdhc / init_fail.

## Public Interface

| Port         | Direction | Width | Description |
|--------------|-----------|-------|-------------|
| clk          | in        | 1     | System clock, 50 MHz |
| rst_n        | in        | 1     | Async reset, active low |
| rd_req       | in        | 1     | Sector read request, single-cycle pulse |
| rd_lba       | in        | 32    | Logical block address |
| rd_busy      | out       | 1     | Read in progress |
| rd_done      | out       | 1     | Full sector received, single-cycle pulse |
| rd_err       | out       | 1     | Timeout or response error, single-cycle pulse |
| byte_valid   | out       | 1     | One byte of sector data valid |
| byte_data    | out       | 8     | The byte |
| byte_idx     | out       | 9     | In-sector byte offset 0..511 |
| card_ready   | out       | 1     | Init completed successfully |
| card_sdhc    | out       | 1     | 1=SDHC, 0=SDSC |
| init_fail    | out       | 1     | Init failed (timeout or error) |
| spi_sclk     | out       | 1     | To TF card |
| spi_mosi     | out       | 1     | To TF card |
| spi_miso     | in        | 1     | From TF card |
| spi_cs_n     | out       | 1     | Card select, active low |

## Clocking and Reset

- Domain: clk_sys (50 MHz)
- Reset: rst_n active low, async assert, sync release
- Init phase: SCLK ≤ 400 kHz (clk_div = 62 → 396.8 kHz)
- Normal phase: SCLK ≤ 12.5 MHz (clk_div = 1 → 12.5 MHz)

## Functional Behavior

### Initialization Sequence

```
IDLE → INIT_IDLE (74 clocks) → CMD0 → CMD8 → ACMD41_LOOP → CMD58 → (SDSC:CMD16) → READY
         │                       │      │        │              │
         └──── timeout ──────────┘      │        └──── timeout ─┘
                         └── error ─────┘
```

#### INIT_IDLE
- CS=1 (inactive), send ≥74 SCLK pulses with MOSI=1.
- Duration: 74 × (2*(62+1)) = 9176 cycles ≈ 183 μs.
- Then enter CMD0 with CS=0.

#### CMD0 (GO_IDLE_STATE)
- tx: 0x40, 0x00×4, 0x95 (CRC7 for cmd0, arg=0).
- Wait for R1 response (first non-0xFF byte).
- Expected R1 = 0x01 (idle).
- Retry up to 100 ms.

#### CMD8 (SEND_IF_COND)
- tx: 0x48, 0x00,0x00,0x01,0xAA, 0x87 (CRC7).
- R7 response (4 bytes after 0xFF): check 0x01AA pattern.
- If card returns 0x05 (illegal cmd) → Ver1.0 or MMC; skip ACMD41 loop after longer wait.
- If card returns 0x01 + correct pattern → Ver2.0+ SD.

#### ACMD41_LOOP (SD_SEND_OP_COND)
- tx: CMD55 (0x77,0x00×4,0x??) then ACMD41 (0x69,arg=0x40000000,0x??).
- Poll until R1 != 0x01 (idle=0 means ready).
- Timeout: 1 second.
- arg: 0x40000000 for SDHC, 0x00000000 for SDSC (host can support both).

#### CMD58 (READ_OCR)
- tx: 0x7A, 0x00×4, 0x??.
- Read CCS bit (bit 30 of 4-byte response): 1=SDHC, 0=SDSC.
- This is valid only after ACMD41 returns idle=0.

#### CMD16 (SET_BLOCKLEN) — SDSC only
- tx: 0x50, 0x00,0x00,0x02,0x00, 0x?? (512 bytes).
- R1 response.

#### READY
- card_ready=1, card_sdhc= CCS. FSM stays in READY until reset.

### Read Sequence (CMD17, single block)

```
READ_WAIT → SEND_CMD17 → SKIP_TOKEN → READ_DATA → READ_CRC → READ_IDLE
```

- rd_req pulse only accepted in READY state.
- SDHC: rd_lba is block address (multiply by 512 internally for the CMD17 arg, but CMD17 in SDHC mode uses block units).
- SDSC: rd_lba is byte address → pass as-is as CMD17 arg.
- CMD17 tx: 0x51, arg[31:24], arg[23:16], arg[15:8], arg[7:0], CRC7.
- Wait for 0xFE data token.
- Read exactly 512 bytes.
- Read 2 CRC bytes (discarded).
- rd_done pulse + byte_idx wraps.

### Response Reception
- After sending a command, poll MISO each bit.
- The first 0x00-to-0xFF transition marks the start of the response.
- If response never arrives within timeout, set init_fail or rd_err.

### Byte Index
- byte_idx counts 0..511 for each sector read.
- Increments on each byte_valid.
- Wraps after 511.

## Timing, Latency, and Throughput

- Init: ~500 ms worst case (ACMD41 polling).
- Read: ~512 bytes × 16 cycles/byte @ 12.5 MHz ≈ 655 μs.
- Both init_fail and rd_err are single-cycle pulses.

## Assumptions and Chosen Defaults

- SD card responds with R1 within 500 ms for each command.
- CRC7 is not checked for reads (simplified).
- No SPI bus re-initialization mid-session.

## Edge Cases and Error Handling

- init_fail: any timeout or unexpected R1 during init.
- rd_err: timeout waiting for data token or incomplete sector.
- rd_req ignored when not in READY state.
- R1 responses: 0x00 OK, 0x01 idle (init), 0xFF no response.

## Synthesis Notes

- Target: EG4S20, any speed grade.
- No BRAM, no DSP.
- FSM uses ~16 states.
- Estimated LUT4: ~300–400.

## Verification Plan

1. Init sequence with a known SD card image (hex dump).
2. Simulate timeout on ACMD41 by asserting MISO=0xFF.
3. CMD17 read: inject data token + 512 bytes + CRC.
4. Verify card_sdhc=1 for SDHC image, card_sdhc=0 for SDSC.
5. Assert rd_req in wrong state → should be ignored.
6. Verify byte_idx wraps 0→511→0.

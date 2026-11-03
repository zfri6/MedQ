# spi_flash_store Behavior Specification

## Requirement Summary

Persist the 128-bit queue state to an SPI NOR Flash chip using a dual-slot protocol with CRC-32 protection. This ensures that a power interruption during a write does not corrupt the previously saved state, enabling reliable recovery at power-on.

## Public Interface

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | in | 1 | System clock, 50 MHz |
| `rst_n` | in | 1 | Synchronous reset, active-low |
| `save_req` | in | 1 | Single-cycle pulse; start a save operation |
| `save_data[127:0]` | in | 128 | Queue state to persist |
| `save_busy` | out | 1 | High while a save is in progress |
| `save_done` | out | 1 | Single-cycle pulse on successful save |
| `load_req` | in | 1 | Single-cycle pulse; start a load operation |
| `load_data[127:0]` | out | 128 | Recovered queue state |
| `load_valid` | out | 1 | Single-cycle pulse; load_data is valid |
| `load_fail` | out | 1 | Single-cycle pulse; both slots had bad CRC |
| `fl_sclk` | out | 1 | SPI clock to Flash |
| `fl_mosi` | out | 1 | SPI MOSI |
| `fl_miso` | in | 1 | SPI MISO |
| `fl_cs_n` | out | 1 | SPI chip select, active-low |

**Pin assignment**: Physical pins pending schematic confirmation (Q4 in risks.md). All `fl_*` signals are unconnected in the current `rtl/top.v` skeleton.

## Parameters and Defaults

| Name | Default | Description |
|------|---------|-------------|
| `SLOT_A_ADDR` | `0x000000` | Sector 0 address |
| `SLOT_B_ADDR` | `0x001000` | Sector 1 address |
| `PAYLOAD_BYTES` | 20 | 16 data + 4 CRC |
| `SPI_DIV` | 3 | `SCLK = 50MHz / (2×(3+1)) = 6.25 MHz` |
| `ERASE_POLL_MAX` | 5000 | ~6.4 ms timeout for erase poll |
| `PGM_POLL_MAX` | 200 | ~256 µs timeout for program poll |

## Clocking and Reset

- **clk**: 50 MHz system clock. All SPI bit-banging, CRC computation, and state machines run here.
- **rst_n**: Synchronous reset. Clears all FSMs, counters, and output flags.
- No asynchronous reset is used.

## Storage Layout

Each slot occupies 20 bytes in Flash:

```
Byte 0..15:  save_data[127:0]    (LSB = byte 0)
Byte 16..19: CRC-32 of bytes 0..15
```

CRC-32 uses the Ethernet / ITU polynomial `0x04C11DB7`, reflected input byte, reflected output CRC, with final XOR `0xFFFFFFFF`.

## Flash Command Protocol

All commands use SPI mode 0 (CPOL=0, CPHA=0, MSB first).

| Command | Code | Sequence |
|---------|------|----------|
| Write Enable | 0x06 | CS↓ → 0x06 → CS↑ |
| Sector Erase | 0x20 | CS↓ → 0x20 → 3-byte addr → CS↑ → poll RDSR until bit0=0 |
| Page Program | 0x02 | CS↓ → 0x02 → 3-byte addr → 1..256 data bytes → CS↑ → poll RDSR |
| Read | 0x03 | CS↓ → 0x03 → 3-byte addr → data bytes → CS↑ |
| Read Status Register | 0x05 | CS↓ → 0x05 → status → CS↑ |

## Functional Behavior

### Save Sequence

1. Latch `save_data` and compute its CRC-32 (16 bytes → 32-bit CRC).
2. WREN command.
3. SECTOR_ERASE of the non-active slot (active slot = last-written slot).
4. Poll RDSR until bit 0 = 0 (erase done). Timeout = 5000 polls (~6.4 ms).
5. WREN command.
6. PAGE_PROGRAM: send 20 bytes (16 data + 4 CRC) to the erased sector.
7. Poll RDSR until bit 0 = 0 (program done). Timeout = 200 polls (~256 µs).
8. Set `save_done`, flip `active_slot`.

### Load Sequence

1. Initiate READ of SLOT_A_ADDR (20 bytes).
2. Capture all 20 bytes into a register buffer.
3. Compute CRC-32 of the first 16 bytes. Compare to bytes 16..19.
4. If slot A CRC matches: assemble `load_data`, set `load_valid`.
5. If slot A CRC fails: initiate READ of SLOT_B_ADDR, CRC-check it.
6. If slot B CRC matches: assemble `load_data`, set `load_valid`.
7. If both slots fail: set `load_fail` only.

### Dual-Slot State Machine

`active_slot[0]` tracks which slot was most recently written:
- 0 = SLOT_A is the active slot.
- 1 = SLOT_B is the active slot.

On every save, the non-active slot is erased and programmed, then `active_slot` is flipped. On load, both slots are read; the algorithm prefers A if both are valid.

### CRC-32 Engine

- **Type**: Bit-serial LFSR, 32 cycles per byte.
- **Polynomial**: 0x04C11DB7 (Ethernet).
- **Init**: 0xFFFFFFFF.
- **Input**: Each data byte is reflected (LSB first) before entering the LFSR.
- **Output**: The LFSR state is reflected bit-by-bit and XORed with 0xFFFFFFFF.
- **Latency**: 16 bytes × 32 cycles = 512 cycles after the last byte is fed.

### SPI Engine

- **Bit rate**: 6.25 MHz (derived from 50 MHz / 8).
- **Bit order**: MSB first.
- **CPOL/CPHA**: 0/0 (idle low, data captured on rising edge, changed on falling edge).
- **Byte order**: Little-endian within the payload (byte 0 = save_data[7:0]).

## Timing, Latency, and Throughput

| Operation | Duration (approx) |
|-----------|------------------|
| Save (erase + program) | ~10 ms |
| Load (both slots) | ~80 µs |
| CRC-32 computation | ~10 µs |
| SPI byte (6.25 MHz) | 1.28 µs |

## Assumptions and Chosen Defaults

- Flash is a standard SPI NOR device supporting the listed commands. Common parts (W25Qxx series, MX25Lxxx) are compatible.
- Sector size is 4 KiB, which matches SLOT_B_ADDR = SLOT_A_ADDR + 4096.
- The Flash supports continuous-read beyond page boundaries; we program exactly 20 bytes per slot.
- The Flash status register bit 0 is write-in-progress (WIP). We poll it to confirm erase/program completion.
- `save_req` and `load_req` are single-cycle pulses. If a request arrives while `save_busy` is high, it is ignored.
- Page programming is always ≤ 256 bytes (our 20-byte payload fits in one page).

## Edge Cases and Error Handling

| Condition | Behavior |
|-----------|----------|
| `save_req` while `save_busy` | Ignored; FSM stays busy |
| `load_req` while busy | Ignored |
| CRC mismatch on slot A only | Use slot B |
| CRC mismatch on both slots | `load_fail = 1`, `load_valid = 0`, `load_data = 0` |
| Erase poll timeout | Proceed to program anyway |
| Program poll timeout | Treat as success (data may still be correct) |
| Reset during save | `save_busy` cleared; partial write is discarded; `active_slot` unchanged |
| Reset during load | `load_valid`/`load_fail` cleared; FSM returns to IDLE |
| Flash returns all 0xFF | CRC will mismatch (0xFFFFFFFF XOR 0xFFFFFFFF = 0, not 0xFF...) — correctly treated as bad slot |

## Synthesis Notes (EG4S20BG256)

- **LUT4 estimate**: ~350 (SPI engine + FSM + CRC + buffers).
- **FF estimate**: ~200.
- **BRAM**: 0 (all buffers are register arrays).
- **No DSP**.
- The register-array `rx_buf[0..4]` (5 × 32-bit) is implemented as distributed registers, well within budget.
- The CRC engine is bit-serial and infers a wide combinational LFSR that collapses to ~40 LUT4s.

## Verification Plan

1. **Save sanity**: Save a known value, then load it back. Verify `load_data` equals `save_data` and `load_valid = 1`.
2. **CRC corruption**: Save, manually flip one bit in Flash model, load. Verify `load_fail = 1`.
3. **Dual-slot**: Save 3 times. Verify `active_slot` cycles: 0→1→0→1.
4. **Load A valid**: Write valid data to both slots; verify A is preferred.
5. **Load B valid**: Write valid data to slot B only; verify B is used.
6. **Both bad**: Write corrupted data to both slots; verify `load_fail = 1`.
7. **Timeout on erase poll**: Stub the Flash model to never clear WIP; verify timeout exits.
8. **Reset during save**: Fire `save_req`, wait 5 µs, assert `rst_n`. Verify FSM resets to IDLE.
9. **Concurrent requests**: Fire both `save_req` and `load_req` simultaneously; verify only save is accepted.

## Acceptance Criteria

- [ ] `save_done` pulses exactly once per successful save.
- [ ] `active_slot` flips after each save.
- [ ] `load_data` equals the previously saved `save_data`.
- [ ] `load_valid` pulses when a valid slot is found.
- [ ] `load_fail` pulses when both slots have CRC errors.
- [ ] Flash SPI transactions follow the documented command sequences.
- [ ] CRC-32 of a known pattern matches a reference implementation (test in TB with golden values).
- [ ] Reset cleanly aborts any in-progress operation.
- [ ] `fl_*` pins are unconnected in `rtl/top.v` pending schematic confirmation.
- [ ] `fl_cs_n` idles high (deselected) when not in a transaction.

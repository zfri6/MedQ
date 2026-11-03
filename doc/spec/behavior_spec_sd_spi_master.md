# sd_spi_master Behavior Specification

## Requirement Summary

SPI Mode 0 master (CPOL=0 CPHA=0: sample on rising edge, drive on falling edge). Variable clock divider, no TX/RX FIFO, blocking one-byte transactions.

## Public Interface

| Port        | Direction | Width | Description |
|-------------|-----------|-------|-------------|
| clk         | in        | 1     | System clock, 50 MHz |
| rst_n       | in        | 1     | Async reset, active low |
| clk_div     | in        | 8     | SCLK = clk / (2*(clk_div+1)) |
| tx_valid    | in        | 1     | Start one-byte TX |
| tx_ready    | out       | 1     | Idle / can accept new byte |
| tx_data     | in        | 8     | Byte to send (MSB first) |
| rx_valid    | out       | 1     | One-cycle pulse when byte received |
| rx_data     | out       | 8     | Received byte |
| busy        | out       | 1     | Transaction in progress |
| spi_sclk    | out       | 1     | SPI clock |
| spi_mosi    | out       | 1     | MOSI output |
| spi_miso    | in        | 1     | MISO input |

## Parameters and Defaults

| Parameter | Default | Description |
|-----------|---------|-------------|
| none      | -       | All configuration via ports |

## Clocking and Reset

- Domain: clk_sys (50 MHz)
- Reset: rst_n active low, async assert, sync release
- SCLK frequency formula: SCLK = clk_sys / (2 * (clk_div + 1))
  - clk_div=62 → SCLK ≈ 400 kHz (init phase)
  - clk_div=1  → SCLK ≈ 12.5 MHz (normal operation)

## Functional Behavior

### State Machine

```
IDLE ─(tx_valid)─► TX_BIT ──► TX_WAIT ──► IDLE
```

- **IDLE**: busy=0, tx_ready=1. On tx_valid pulse, latch tx_data, enter TX_BIT.
- **TX_BIT**: send 8 bits MSB-first. CPOL=0: SCLK low in IDLE, toggle for each bit.
  - On falling edge of SCLK: shift MOSI with current bit.
  - On rising edge of SCLK: sample MISO into shift register.
  - bit_cnt increments on each SCLK rising edge.
- **TX_WAIT**: (optional) one cycle settle before returning to IDLE.
- **IDLE**: rx_valid=1 for one cycle with completed rx_data; tx_ready=1.

### CPOL=0 CPHA=0 Timing

- SCLK idles LOW.
- MOSI changes on SCLK falling edge (half cycle after sample edge).
- MISO is sampled on SCLK rising edge.
- Total bits per byte: 8 SCLK cycles.

### SCLK Generation

- Use a counter `sclk_cnt` that runs when busy=1.
- Toggle SCLK when sclk_cnt == clk_div (full half-period).
- Keep SCLK stable (low) during IDLE.

## Timing, Latency, and Throughput

- Throughput: 1 byte per (16 * (clk_div+1)) clk cycles.
- rx_valid pulse: 1 cycle after the last bit is sampled.
- tx_ready deasserts as soon as tx_valid is accepted; reasserts when returning to IDLE.

## Assumptions and Chosen Defaults

- spi_miso is assumed stable at the sampling edge; no metastability hardening in this module.
- clk_div must be ≥1; clk_div=0 gives SCLK=clk/2 (may exceed SD card spec).

## Edge Cases and Error Handling

- If tx_valid arrives while busy=1: ignored (back-pressure via tx_ready).
- No timeout; caller is responsible for watchdog.

## Synthesis Notes

- Target: EG4S20, any speed grade.
- No BRAM, no DSP, no multiplication.
- Estimated LUT4: ~80–120.

## Verification Plan

1. TX byte 0xAA, verify MOSI sequence: 1-0-1-0-1-0-1-0.
2. Inject MISO pattern 0x55, verify rx_data = 0x55.
3. Toggle clk_div between 62 (400 kHz) and 1 (12.5 MHz) mid-session.
4. Assert tx_valid while busy → must be ignored.

## Acceptance Criteria

- [ ] MOSI outputs correct MSB-first bit pattern for any tx_data.
- [ ] rx_data equals injected MISO pattern, sampled on rising SCLK edges.
- [ ] SCLK frequency = clk / (2*(clk_div+1)).
- [ ] SCLK idles LOW.
- [ ] tx_ready goes low for exactly the busy window; pulses do not stack.
- [ ] rx_valid is a single-cycle pulse.

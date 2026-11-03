> 2026-10-26：本模块已在仿真闭环修复中更新；以下为历史初版。当前行为与接口以 [闭环行为说明](behavior_spec.md) 和实际 RTL 为准。

# rst_sync Behavior Specification

## Requirement Summary

Provide a universal asynchronous-assert, synchronous-release reset synchronizer for each clock domain. Guarantees metastability-free reset release regardless of which condition causes the release (PLL lock or POR timer expiry).

## Public Interface

| Port   | Direction | Width | Description |
|--------|-----------|-------|-------------|
| `clk`       | in | 1  | Domain clock |
| `ext_rst_n` | in | 1  | External async reset, active low; tie to 1'b1 if unused |
| `pll_locked`| in | 1  | PLL lock flag, active high; tie to 1'b1 if no PLL |
| `rst_n_out` | out| 1  | Domain reset, active low, synchronous to `clk` |

## Parameters and Defaults

| Parameter | Default | Description |
|-----------|---------|-------------|
| `POR_CYCLES` | `50000` | POR count limit @50 MHz = 1 ms; adjust if clock frequency changes |

## Clocking and Reset

- **Clock**: any frequency; `POR_CYCLES` is expressed in clock cycles.
- **Reset release**: two flip-flops in series on the target `clk` domain, guaranteeing no metastability on `rst_n_out`.
- **POR timer**: 16-bit counter; fits `POR_CYCLES` up to 65535. Default 50000 < 65535.

## Functional Behavior

### Reset Assert (immediate, asynchronous)
`rst_n_out` goes low as soon as `ext_rst_n == 0` or `pll_locked == 0`, with no clock required. This is the async-assert path.

### Reset Release (synchronous)
`rst_n_out` rises only after both conditions hold simultaneously:
1. `ext_rst_n == 1` AND `pll_locked == 1` (PLL-locked path), OR
2. `ext_rst_n == 1` AND `por_done == 1` (no PLL, POR expiry path).

When either path is satisfied, `release_req` becomes 1, and `rst_n_out` releases through two registers on `clk`. This satisfies "async assert, sync release."

### POR Counter Behavior
- Counts up when `pll_locked == 0` (PLL not yet locked).
- Clears immediately when `pll_locked == 1` (PLL locks).
- If `pll_locked` stays 0 forever (no PLL), counter runs to `POR_CYCLES` and then sets `por_rst_n = 1`, enabling release.
- If `pll_locked` goes high, counter resets, so a subsequent relock still triggers a proper reset sequence.

### Release Gate
`release_req = pll_locked | por_rst_n` — either PLL lock or POR done. This is a logical OR (not priority-encoded); both paths share the same two-FF chain.

## Timing, Latency, and Throughput

- Assert latency: 0 cycles (asynchronous).
- Release latency: 2 cycles after `release_req` rises.
- POR counter period: `POR_CYCLES` clock cycles from `pll_locked` falling edge.

## Assumptions and Chosen Defaults

- `ext_rst_n` is an external button or power-on signal, assumed to be properly debounced and safe against switch bounce.
- `pll_locked` ties to `1'b1` when no PLL is present.
- `POR_CYCLES = 50000` at 50 MHz yields 1 ms, sufficient for most FPGA fabric reset sequences.
- 16-bit counter is sufficient for default `POR_CYCLES`; if clock frequency drops significantly and `POR_CYCLES` must increase above 65535, the counter width must expand to 17+ bits.

## Edge Cases and Error Handling

| Case | Behavior |
|------|----------|
| `ext_rst_n` pulses low while PLL is locked | Immediate re-assert via `release_req=0`; counters clear; release sequence restarts |
| `pll_locked` drops after having been high | Counter restarts; `rst_n_out` re-asserts immediately |
| `pll_locked` is permanently 0 and no PLL exists | POR counts to `POR_CYCLES`, then releases; one-shot |
| `pll_locked` and `ext_rst_n` both 1 from the start | `release_req = 1` immediately; two-FF chain releases in 2 cycles |

## Synthesis Notes

- **Target**: Anlogic TD 6.2.1, EG4S20BG256
- **Resource**: 2 flip-flops + 1 adder for counter (~50 LUT4 total)
- **No BRAM / DSP / PLL required**
- The two-FF sync chain is the standard circuit for reset domain crossing; it is not optional.

## Verification Plan

1. **Assert path**: Drop `ext_rst_n` or `pll_locked`; confirm `rst_n_out` goes 0 within 1 ns (zero-cycle).
2. **Release path**: Raise both `ext_rst_n` and `pll_locked`; capture `rst_n_out` rising edge; confirm it occurs 2 clock cycles later.
3. **POR path**: Tie `ext_rst_n=1`, `pll_locked=0`; wait for counter expiry; confirm `rst_n_out` releases after expiry + 2 cycles.
4. **Relock**: Simulate PLL relocking mid-count; confirm counter resets and release waits for fresh lock.

## Acceptance Criteria

- [ ] `rst_n_out` asserts within 1 ns of `ext_rst_n` falling or `pll_locked` falling.
- [ ] `rst_n_out` does NOT release until at least 2 rising edges of `clk` after `release_req` is high.
- [ ] With `ext_rst_n=1`, `pll_locked=0`, and no PLL, `rst_n_out` releases after exactly `POR_CYCLES + 2` clock cycles.
- [ ] With `ext_rst_n=1`, `pll_locked=1`, `rst_n_out` releases within 2 cycles.
- [ ] Dropping `pll_locked` after release immediately re-asserts `rst_n_out`.
- [ ] No combinational loop between `pll_locked` and `rst_n_out`.
- [ ] Code is pure Verilog-2001, no SystemVerilog syntax.

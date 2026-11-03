# cdc_sync_bit Behavior Specification

## Requirement Summary

Single-bit clock domain crossing (CDC) using a multi-flip-flop synchronizer chain. Eliminates metastability when a one-bit signal crosses from one clock domain to another.

## Public Interface

| Port   | Direction | Width | Description |
|--------|-----------|-------|-------------|
| `clk`   | in | 1  | Destination clock domain |
| `rst_n` | in | 1  | Active-low reset for destination domain |
| `d_in`  | in | 1  | Signal from source domain |
| `d_out` | out| 1  | Synchronized signal on destination domain |

## Parameters and Defaults

| Parameter | Default | Description |
|-----------|---------|-------------|
| `STAGES` | `2` | Number of flip-flop stages in the synchronizer chain |
| `INIT`   | `0` | Initial value driven on `rst_n` release |

## Clocking and Reset

- **Source clock**: unknown to this module; `d_in` can originate from any clock domain.
- **Destination clock**: `clk`, on which all internal registers operate.
- **Reset**: active-low synchronous reset, clears the entire sync chain to `INIT`.

## Functional Behavior

### Synchronizer Chain
A chain of `STAGES` flip-flops, each driven by `clk`. `d_in` connects to the first flop; each subsequent flop captures the output of the previous one.

The probability of metastability is reduced with each additional stage. `STAGES=2` is the industry-standard minimum; `STAGES=3` may be used for source clocks that are close in frequency to the destination clock.

### Output Validity
`d_out` becomes valid `STAGES` clock cycles after `d_in` changes, but due to possible metastability the safe rule is: **never use `d_out` to generate any edge that drives logic in the destination domain** (that requires `cdc_pulse`). `cdc_sync_bit` is suitable only for:
- Control/valid flags (level signals)
- Slow-changing signals that are stable for many destination clock cycles

## Timing, Latency, and Throughput

- **Latency**: `STAGES` clock cycles.
- **Throughput**: continuous; each clock cycle captures `d_in` into the chain.
- **Metastability MTBF**: improves exponentially with `STAGES`. At typical FPGA conditions with `STAGES=2`, MTBF >> system lifetime.

## Assumptions and Chosen Defaults

- `d_in` is expected to be stable for at least `STAGES + 1` destination clock cycles before it may change again. Violating this may result in `d_out` capturing an undefined or transitional value.
- The two default parameter values (`STAGES=2`, `INIT=0`) match the consensus recommendation in FPGA/ASIC design guidelines (Cummings, "Clock Domain Crossing (CDC) Design & Verification Techniques Using SystemVerilog").

## Edge Cases and Error Handling

| Case | Behavior |
|------|----------|
| `d_in` toggles faster than `STAGES` destination cycles | `d_out` may miss transitions; safe operation requires `d_in` to be stable |
| `rst_n` asserted | All chain flops reset to `INIT`; `d_out = INIT` |
| `rst_n` released | First rising edge loads `d_in` into stage 0; `d_out` valid after `STAGES` cycles |
| `d_in` is a one-cycle pulse | `d_out` may or may not capture it depending on phase; use `cdc_pulse` for pulses |

## Synthesis Notes

- **Target**: Anlogic TD 6.2.1, EG4S20BG256
- **Resource**: `STAGES` flip-flops (~`STAGES` LUT4). At `STAGES=2`: 2 DFF.
- **No BRAM / DSP / PLL required**.
- Inferring a shift-register SRL is possible but not guaranteed; explicit registers are clearer.

## Verification Plan

1. **Reset behavior**: Assert `rst_n`; confirm `d_out = INIT`. Release `rst_n`; after `STAGES` cycles, `d_out` reflects current `d_in`.
2. **Transition capture**: Toggle `d_in`; confirm `d_out` changes exactly `STAGES` cycles later.
3. **Glitch rejection**: Apply a pulse shorter than one destination clock cycle on `d_in`; confirm `d_out` may not capture it.
4. **Parameter sweep**: Verify `STAGES=2` and `STAGES=3` both work; `INIT=0` and `INIT=1` both reset correctly.

## Acceptance Criteria

- [ ] `d_out` is stable and valid `STAGES` clock cycles after `d_in` changes.
- [ ] `rst_n` reset drives all chain flops to `INIT` simultaneously.
- [ ] No combinational path from `d_in` to `d_out`; the output is purely sequential.
- [ ] Simulation shows metastability window on first flop does not propagate to `d_out` (waveform zoomed at the capture edge).
- [ ] Code is pure Verilog-2001.

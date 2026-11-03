> 2026-10-26：本模块已在仿真闭环修复中更新；以下为历史初版。当前行为与接口以 [闭环行为说明](behavior_spec.md) 和实际 RTL 为准。

# cdc_pulse Behavior Specification

## Requirement Summary

Single-cycle pulse crossing from one clock domain (`src_clk`) to another (`dst_clk`) with full handshake flow control. The source side asserts `src_busy` during the transaction to prevent concurrent pulse forwarding.

## Public Interface

| Port      | Direction | Width | Description |
|-----------|-----------|-------|-------------|
| `src_clk`    | in | 1 | Source clock domain |
| `src_rst_n`  | in | 1 | Active-low reset for source domain |
| `src_pulse`  | in | 1 | Single-cycle pulse on source domain to forward |
| `src_busy`   | out| 1 | 1=handshake in-flight; pulses ignored while high |
| `dst_clk`    | in | 1 | Destination clock domain |
| `dst_rst_n`  | in | 1 | Active-low reset for destination domain |
| `dst_pulse`  | out| 1 | Single-cycle pulse on destination domain |

## Parameters and Defaults

No configurable parameters. Internal `cdc_sync_bit` uses `STAGES=2`.

## Clocking and Reset

- **Source clock**: `src_clk`; drives `src_req_reg`, `src_busy`, and the source-side synchronizer.
- **Destination clock**: `dst_clk`; drives `dst_ack_reg`, `dst_pulse`, and the destination-side synchronizer.
- **Reset**: independent resets `src_rst_n` and `dst_rst_n` for respective domains.

## Functional Behavior

### Handshake Protocol (two-toggle synchronizer)

```
src: src_pulse arrives -> src_req_reg toggles  -> src_busy = 1
dst: src_req_sync sees toggle  -> dst_ack_reg toggles -> dst_pulse=1
src: dst_ack_sync returns      -> src_busy = 0
```

The two synchronizers (`cdc_sync_bit`) transfer the toggle state of `src_req_reg` and `dst_ack_reg` across the clock boundary.

### Source-Side Rules
1. `src_busy` is high whenever `src_req_reg != dst_ack_sync`. This holds while the destination has not yet acknowledged.
2. When `src_pulse` arrives and `src_busy == 0`, `src_req_reg` toggles, initiating a new transaction.
3. When `src_pulse` arrives and `src_busy == 1`, the pulse is **dropped** — no new transaction is started.

### Destination-Side Rules
1. A rising edge on `src_req_sync` (synchronized request) generates a one-cycle `dst_pulse`.
2. `dst_ack_reg` toggles on the same rising edge, sending an acknowledgment back to source.
3. The acknowledgment crosses back to `src_clk` via another `cdc_sync_bit`, completing the cycle.

### Timing Diagram (conceptual)
```
src_clk:  __/    \________/    \__
          pulse  busy hi    busy lo

dst_clk:          __/    \__
                  pulse   ack toggle
```
The exact cycle count between `src_pulse` and `dst_pulse` depends on relative clock phases; typically 1-4 cycles.

## Timing, Latency, and Throughput

- **src_pulse → dst_pulse latency**: 2–5 clock cycles (destination domain), depending on phase.
- **Minimum pulse spacing on src**: at least one handshake round-trip; `src_busy` being deasserted is the signal to send the next pulse.
- **Throughput**: one pulse per round-trip; not pipelined.

## Assumptions and Chosen Defaults

- `src_pulse` is a single-cycle event on `src_clk`. If it is wider, the logic treats each rising edge as a new pulse; wide pulses may be double-counted if they span the busy-deassert transition.
- The two `cdc_sync_bit` instances each use `STAGES=2` for a balance of metastability protection and latency.
- The toggle/ack protocol guarantees that even if the source clock is much faster than the destination, no pulses are lost and no extra pulses are generated.

## Edge Cases and Error Handling

| Case | Behavior |
|------|----------|
| Two `src_pulse` arrive while `src_busy == 1` | Both are dropped; `src_req_reg` only toggles once per acknowledged transaction |
| `src_pulse` arrives exactly when `src_busy` deasserts | One pulse is forwarded; the other is dropped (race is resolved by the toggle comparator) |
| `src_rst_n` or `dst_rst_n` pulsed mid-transaction | Reset clears registers; handshake restarts; no corrupted state |
| `dst_clk` stops while `src_pulse` arrives | Source side waits indefinitely (destination clock must run); `src_busy` stays high |

## Synthesis Notes

- **Target**: Anlogic TD 6.2.1, EG4S20BG256
- **Resource**: 2× `cdc_sync_bit` (4 flops) + 2 extra flops for edge detection + 2 toggle registers = ~8 DFF total
- **No BRAM / DSP / PLL required**
- Two `cdc_sync_bit` sub-modules are instantiated explicitly; the module itself is pure RTL

## Verification Plan

1. **Basic forward**: Apply `src_pulse`; confirm `dst_pulse` arrives within expected latency range.
2. **Busy blocking**: Assert `src_busy` by keeping `dst_ack_sync` low; apply `src_pulse`; confirm it is dropped.
3. **Multi-pulse**: Send two pulses separated by the round-trip time; confirm two `dst_pulse` arrive with correct spacing.
4. **Reset isolation**: Pulse `src_rst_n` mid-transaction; confirm source resets without corrupting the destination side.
5. **Back-to-back**: After `src_busy` deasserts, immediately assert a new `src_pulse`; confirm it is forwarded.

## Acceptance Criteria

- [ ] A single `src_pulse` generates exactly one `dst_pulse`.
- [ ] `src_busy` is 1 during the handshake and 0 after completion.
- [ ] A `src_pulse` arriving while `src_busy == 1` does NOT generate a `dst_pulse`.
- [ ] Reset on either side does not corrupt the other side's state.
- [ ] The handshake is idempotent: multiple fast pulses do not cause double-forward.
- [ ] Code is pure Verilog-2001; `cdc_sync_bit` sub-module is instantiated correctly.

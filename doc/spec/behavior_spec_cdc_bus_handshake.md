> 2026-10-26：本模块已在仿真闭环修复中更新；以下为历史初版。当前行为与接口以 [闭环行为说明](behavior_spec.md) 和实际 RTL 为准。

# cdc_bus_handshake Behavior Specification

## Requirement Summary

Wide bus (W-bit) crossing from `src_clk` to `dst_clk` using a four-phase (request-acknowledge) handshake. All W bits are sampled together on the destination side, forming an atomic snapshot that cannot be corrupted by the destination seeing bits from different source clock cycles.

## Public Interface

| Port       | Direction | Width | Description |
|------------|-----------|-------|-------------|
| `src_clk`    | in | 1 | Source clock domain |
| `src_rst_n`  | in | 1 | Active-low reset for source domain |
| `src_data`   | in | W | Data to be transferred; must be stable while `src_req=1` |
| `dst_clk`    | in | 1 | Destination clock domain |
| `dst_rst_n`  | in | 1 | Active-low reset for destination domain |
| `dst_data`   | out| W | Received data; stable until next transfer completes |

## Parameters and Defaults

| Parameter | Default | Description |
|-----------|---------|-------------|
| `W` | `128` | Bus width in bits (128 for qstate_bus, 64 for param_bus) |

## Clocking and Reset

- **Source clock**: `src_clk`; drives source-side request FSM, `src_req`, and source-side synchronizer.
- **Destination clock**: `dst_clk`; drives destination-side capture FSM, `dst_ack`, and destination-side synchronizer.
- **Reset**: independent `src_rst_n` and `dst_rst_n`.

## Functional Behavior

### Four-Phase Handshake

```
Phase 1: Source sends request
  src: (src_data valid) & (src_req == 0) -> src_req <= 1
Phase 2: Destination acknowledges
  dst: sees src_req_sync=1 -> dst_data <= src_data; dst_ack <= 1
Phase 3: Source drops request
  src: sees dst_ack_sync=1 -> src_req <= 0
Phase 4: Destination drops ack
  dst: sees src_req_sync=0 -> dst_ack <= 0
  -> cycle complete, ready for next transfer
```

### Source-Side FSM
States: `S_IDLE` (waiting for new data), `S_WAIT_ACK` (waiting for destination ack).

- **S_IDLE**: Watches `src_data`. When it differs from the previously captured value, raises `src_req`.
- **S_WAIT_ACK**: Holds `src_req=1`. When `dst_ack_sync` is seen, lowers `src_req` and returns to S_IDLE.

A `src_data` capture register (updated in S_IDLE) provides the comparison baseline. This ensures a new transaction is started only when data actually changes, and not spuriously when the same value is held.

### Destination-Side FSM
States: `S_IDLE` (idle), `S_SAMPLE` (data captured, waiting for request drop).

- **S_IDLE**: Watches `src_req_sync`. When it goes high, captures `src_data` into `dst_data_raw`, asserts `dst_ack`.
- **S_SAMPLE**: Holds `dst_ack=1`. When `src_req_sync` goes low, lowers `dst_ack` and returns to S_IDLE.

### Atomicity Guarantee
All W bits of `src_data` are captured simultaneously on the same destination clock edge. The destination never sees a partial update. This is critical for fields like `qstate_bus` where tearing between source cycles would cause incorrect display combinations.

## Timing, Latency, and Throughput

- **src → dst latency**: ~3–7 clock cycles of `dst_clk` (2 for request CDC + 1 for data capture + 2 for ack CDC).
- **Minimum throughput**: one complete transfer per round-trip (~6–12 `dst_clk` cycles).
- **Backpressure**: the source cannot initiate a new transfer until the current one completes (busy-wait in S_WAIT_ACK). This is inherent to four-phase handshake.

## Assumptions and Chosen Defaults

- `src_data` is stable while `src_req == 1`. The source FSM holds it stable for the entire request phase.
- `src_data` changes only when the source has new meaningful information; comparisons are byte-wise identical.
- `W=128` for `qstate_bus` matches the full bundle width. Other instantiations (e.g., `W=64` for `param_bus`) use the same module with a different parameter.
- For very wide buses (≥128 bits), no additional logic is needed; the data is transferred in a single handshake cycle.

## Edge Cases and Error Handling

| Case | Behavior |
|------|----------|
| `src_data` changes while module is in S_WAIT_ACK | The change is invisible until the current handshake completes; the source-side capture register picks up the latest stable value |
| `src_data` returns to its previous value | No spurious transfer; only changes from the captured baseline trigger new transactions |
| `src_rst_n` pulsed during S_WAIT_ACK | Resets source FSM; handshake aborts; destination side continues to completion; no corruption |
| `dst_rst_n` pulsed during S_SAMPLE | Resets destination FSM; `dst_data_raw` cleared; when source retransmits, handshake restarts cleanly |
| Two consecutive identical values sent | Only the first triggers a transfer; the second is dropped at the comparison stage |

## Synthesis Notes

- **Target**: Anlogic TD 6.2.1, EG4S20BG256
- **Resource**: 2× `cdc_sync_bit` (4 DFF) + source FSM (2 bits) + destination FSM (1 bit) + `W` bits of data registers. At `W=128`: ~140 DFF.
- **No BRAM / DSP / PLL required**.
- The two `cdc_sync_bit` sub-modules are instantiated explicitly.

## Verification Plan

1. **Single transfer**: Drive `src_data` through a known value while idle; confirm `dst_data` receives the same value after handshake completes.
2. **Data stability**: Change `src_data` mid-transfer (while `src_req=1`); confirm `dst_data` still captures the first stable value.
3. **Back-to-back**: Send two consecutive values as fast as possible; confirm `dst_data` receives both, correctly ordered.
4. **No spurious**: Hold `src_data` constant; confirm no new transfers occur.
5. **Atomicity**: Toggle individual bits of `src_data`; confirm `dst_data` always reflects a coherent old or new value, never a torn intermediate.
6. **Reset**: Reset source or destination mid-transfer; confirm clean restart with no corrupted `dst_data`.

## Acceptance Criteria

- [ ] All W bits of `dst_data` are from the same `src_clk` cycle (no tearing).
- [ ] A change in `src_data` produces exactly one `dst_data` update after handshake.
- [ ] Holding `src_data` constant produces zero transfers.
- [ ] Source cannot start a new transfer while one is in progress (`src_req` stays high until ack).
- [ ] Reset on either side does not corrupt the other side or produce a spurious `dst_data` update.
- [ ] `W=128` with 128-bit data path synthesizes correctly.
- [ ] Code is pure Verilog-2001; `cdc_sync_bit` sub-modules are instantiated correctly.

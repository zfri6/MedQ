> 2026-10-26：本模块已在仿真闭环修复中更新；以下为历史初版。当前行为与接口以 [闭环行为说明](behavior_spec.md) 和实际 RTL 为准。

# sdram_arbiter Behavior Specification

## Requirement Summary

4-master / 1-slave round-robin/priority bus arbiter for the SDRAM port. Arbitration granularity is the entire burst transaction (no mid-burst preemption). Priority order: aud > disp > tr > wr normally; wr is temporarily promoted above aud after `STARVE_MAX` consecutive denials to prevent write starvation.

## Public Interface

All ports match `interface_contract.yaml` (sdram_master_port, 12 signals per master).

| Port prefix | Owner | Priority | Normal priority |
|-------------|-------|----------|-----------------|
| `aud_*` | `audio_pcm_player` | 1 (highest) | always highest |
| `disp_*` | `frame_reader` (main) | 2 | — |
| `tr_*` | `frame_reader` (transition) | 3 | — |
| `wr_*` | `asset_loader` | 4 (lowest) | boosted above all after `STARVE_MAX` denials |
| `mem_*` | `sdram_ctrl_wrap` (slave) | — | — |

## Parameters and Defaults

| Parameter | Default | Description |
|-----------|---------|-------------|
| `STARVE_MAX` | `64` | Number of consecutive denials before wr is promoted to highest priority |

## Clocking and Reset

- **Clock**: `clk_mem` at 100 MHz.
- **Reset**: active-low `rst_n` clears grant state, starvation counter, and data-phase registers.

## Functional Behavior

### Arbitration FSM

States: `IDLE` and `SERVING`.

```
IDLE:
  - mem_req_ready = 1 (slave can accept new request)
  - Select highest-priority requesting master
  - Grant to that master; assert its *_req_ready
  - Transition to SERVING

SERVING:
  - mem_req_ready = 0 (slave is busy with current master)
  - Hold current grant; slave continues to serve granted master
  - Data phase handshakes (wr_*/rd_*) pass through bidirectionally
  - Monitor (mem_req_valid && mem_req_ready): request phase complete
  - When granted master drops mem_req_valid: transaction done → return to IDLE
```

The key design decision: **grant persists until the master itself drops `req_valid`**. The master controls the end of its transaction; the arbiter does not infer completion. This is safe because the master is required to hold `req_valid` throughout the entire burst (request + data phases).

### Starvation Prevention

`wr_deny_cnt` increments whenever:
- `wr_req` is asserted
- The arbiter grants to someone other than wr
- `mem_req_valid` is high (bus is busy)

`wr_deny_cnt` resets when wr is granted or when `wr_req` is deasserted.

When `wr_deny_cnt >= STARVE_MAX`, `wr_boosted = 1` and wr becomes the highest-priority request, above aud. The promotion is temporary: as soon as wr is granted and completes a transaction, `wr_deny_cnt` resets and normal priority resumes.

### Data Phase Passthrough

During SERVING, the granted master's full port (req_*, wr_*, rd_*) is connected directly to the slave. Non-granted masters see their `*_req_ready` deasserted (0). The connection matrix guarantees each master only uses the bus when granted.

### Read Data Routing

`mem_rd_data_in` is the slave's read data output. The arbiter fans this out to all masters as `*_rd_data`. Only the granted master's `*_rd_valid_out` is asserted, since only the granted master is consuming the data. The other masters' `*_rd_ready` inputs are routed to the slave as `mem_rd_ready`.

## Timing, Latency, and Throughput

- **Grant latency**: 1 cycle from IDLE to granting a new master.
- **Burst atomicity**: once granted, a master owns the bus for the full burst; no preemption.
- **Rotation**: after a master drops `req_valid`, the next grant occurs in the same cycle (IDLE with 1-cycle selection).

## Assumptions and Chosen Defaults

- Each master holds `req_valid` continuously from the start of request phase through the end of data phase. The spec requires this; violation causes the FSM to stay in SERVING.
- `STARVE_MAX=64` at 100 MHz = 640 ns per denial cycle. 64 denials = 40.96 µs. A typical write burst of 256 words takes 2.56 µs at 100 MHz, so 64 denials would represent a very long period of write suppression.
- The four masters are well-behaved and do not hold `req_valid` indefinitely.

## Edge Cases and Error Handling

| Case | Behavior |
|------|----------|
| Two masters request simultaneously | Highest-priority by normal order wins. Others wait. |
| New request arrives while serving | Wait for current master to drop `req_valid`; then serve new request. |
| wr is starved (`wr_boosted=1`) and aud also requests | wr wins (boosted above aud). This is intentional: prevents permanent write suppression. |
| Grant changes while a master is mid-data-phase | The old master sees `*_req_ready=0`; it must complete and drop `req_valid`. The arbiter waits in SERVING (with old grant held) until old master finishes. |
| Master drops `req_valid` in same cycle as req handshake completes | FSM correctly transitions from SERVING → IDLE on the `req_valid` falling edge. |
| All masters idle | `idle` state holds; `mem_req_ready=1`. |

## Synthesis Notes

- **Target**: Anlogic TD 6.2.1, EG4S20BG256
- **Resource**: ~150 LUT4 (grant FSM + starvation counter + data mux). No BRAM/DSP.
- Priority encoder is a simple series of `if/else` gates; no special encoding needed.

## Verification Plan

1. **Basic grant**: Assert one master's req; confirm it gets grant and mem_* are connected.
2. **Priority**: Assert two masters simultaneously; confirm highest priority wins.
3. **Burst completion**: Grant to a master; simulate the master dropping req_valid; confirm FSM returns to IDLE.
4. **No preemption**: Grant to a low-priority master; assert a higher-priority request mid-burst; confirm higher priority waits until low drops req_valid.
5. **Starvation boost**: Continuously deny wr for STARVE_MAX cycles; confirm wr_boosted activates and wr eventually wins.
6. **Starvation reset**: After wr wins following boost, confirm starvation counter resets and normal priority resumes.
7. **Data phase**: With a granted master performing a write, confirm wr_data flows correctly to mem_wr_data.
8. **Read data routing**: With a granted master performing a read, confirm mem_rd_data_in fans out correctly and only granted master's rd_valid_out is asserted.

## Acceptance Criteria

- [ ] Grant always goes to exactly one master (or NONE in IDLE).
- [ ] A master's req handshake completes correctly when both req_valid and req_ready are high.
- [ ] The FSM stays in SERVING only while the granted master holds req_valid.
- [ ] wr_deny_cnt increments only when wr is denied while requesting.
- [ ] wr_deny_cnt resets to 0 when wr is granted.
- [ ] When wr_boosted=1, wr wins over aud.
- [ ] Non-granted masters' *_req_ready are always 0.
- [ ] Data phase signals (wr_*, rd_*) pass through correctly during SERVING.
- [ ] Code is pure Verilog-2001.

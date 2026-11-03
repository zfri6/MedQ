# latency_probe Behavior Specification

## Requirement Summary

Measure the wall-clock latency from a key-press to the updated queue state appearing on the display. Output microseconds (lat_us) and whole video frames (lat_frames) so the engineering-diagnostics page can display a concrete number instead of a checkbox.

## Public Interface

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk_sys` | in | 1 | System clock, 50 MHz |
| `rst_n_sys` | in | 1 | Synchronous reset, active-low |
| `start_evt` | in | 1 | Single-cycle pulse in `clk_sys`; rising edge arms the probe |
| `clk_pix` | in | 1 | Pixel clock, 25 MHz |
| `rst_n_pix` | in | 1 | Synchronous reset, active-low |
| `stop_evt` | in | 1 | Single-cycle pulse in `clk_pix`; first `frame_start` after qstate update |
| `lat_us[15:0]` | out | 16 | Latency in microseconds (unsigned) |
| `lat_frames[7:0]` | out | 8 | Whole video frames (unsigned) |
| `lat_valid` | out | 1 | Single-cycle pulse in `clk_pix`; result is ready this cycle |

## Parameters and Defaults

| Name | Default | Description |
|------|---------|-------------|
| none | — | No configurable parameters; all constants derived from board clocks |

## Clocking and Reset

- **clk_sys** (50 MHz): Free-running counter and FSM. `rst_n_sys` resets counter to 0 and FSM to IDLE.
- **clk_pix** (25 MHz): Stop event, CDC bridge, and result output. `rst_n_pix` resets all `clk_pix`-domain registers.
- Two distinct reset domains. Both resets are synchronous (FPGA style: `always @(posedge clk or negedge rst_n)`).

## Functional Behavior

### State Machine (clk_sys)

Three states, stored in `state_sys[1:0]`:
- **IDLE** (`2'b00`): counter = 0. Waits for `start_evt`.
- **RUN** (`2'b01`): counter increments every clk_sys tick. Stops on `stop_latched_sys` (stop event seen in clk_sys domain). Saturates at MAX without error.
- **DONE** (`2'b10`): counter holds final value. Next `start_evt` re-arms to IDLE.

### Timing Sequence

1. User presses a key → `start_evt` fires in `clk_sys`.
2. `state_sys` moves IDLE → RUN. Counter starts from 0.
3. The result of that key press propagates through queue FSM, CDC, OSD renderer, video pipeline, and HDMI TX.
4. When the updated qstate is first fully rendered on screen, `stop_evt` fires in `clk_pix` (first `frame_start` after the new qstate snapshot).
5. `stop_evt` is CDC'd to `clk_sys` via a two-FF synchroniser.
6. On the next `clk_sys` edge where the synchronised stop flag is high and state is RUN, `stop_latched_sys` is set. Counter freezes.
7. `captured_ticks_sys` captures the frozen counter value.
8. `captured_valid_sys` pulses high for one `clk_sys` cycle.
9. This strobe is CDC'd to `clk_pix`. When it arrives, the 22-bit tick count is latched into `ticks_pix` and `lat_us` / `lat_frames` are computed combinatorially from it.
10. `lat_valid` pulses for one `clk_pix` cycle.

### CDC Strategy

Three independent CDC paths, all using two FF synchronisation:
- `stop_evt` (clk_pix → clk_sys): gates counter stop and FSM transition.
- `captured_valid_sys` (clk_sys → clk_pix): triggers result capture.
- `captured_ticks_sys` (clk_sys → clk_pix): 22-bit data value.

## Timing, Latency, and Throughput

| Item | Value | Note |
|------|-------|------|
| Counter resolution | 20 ns | 1 tick @ 50 MHz |
| Max measurable latency | 83.886 ms | counter saturates at 2^22 |
| Result latency after stop_evt | ≤ 3 clk_pix cycles | CDC + register output |
| Measurement frequency | Event-driven | One result per key-press |
| us accuracy | ±1 tick (20 ns) | Error dominated by CDC meta-stability |

## Assumptions and Chosen Defaults

- The source of `stop_evt` is `osd_renderer` asserting that the new qstate has entered the render pipeline. The precise definition of "first frame where qstate appears" is upstream's responsibility.
- If `start_evt` arrives while already RUN, the module stays in RUN (no re-arm). A new measurement starts only from DONE/IDLE.
- The counter saturates at MAX rather than wrapping, to avoid delivering a spuriously small result.

## Edge Cases and Error Handling

| Condition | Behavior |
|-----------|----------|
| `stop_evt` arrives before `start_evt` | Ignored; stop must be preceded by start |
| `start_evt` during DONE state | Re-arms: state → RUN, counter → 0 |
| Counter saturates at MAX | Saturates; result will be capped at max_us |
| Two stop events in same measurement | First one wins; subsequent stops ignored until re-arm |
| Reset during RUN | Counter → 0, state → IDLE; any in-flight stop_evt is also flushed by the reset on stop_evt's domain |

## Synthesis Notes (EG4S20BG256)

- **LUT4 estimate**: ~120 (counter + FSM + CDC + 2 dividers as shift-subtract).
- **FF estimate**: ~60.
- **No BRAM, no DSP, no RAM**.
- Two async FIFOs implemented as register arrays (CDC depth = 2).
- Divider `div_u22_u16` (÷50) and `div_u16_u8` (÷16667) are combinational shift-subtract. At 25 MHz they easily meet timing.

## Verification Plan

1. **Zero-measurement sanity**: start_evt, then stop_evt within 1 µs. Expect lat_us ≈ 0–2.
2. **Known-delay injection** (TB injects a fixed-delay model): Verify lat_us ≈ injected_delay × 50 ticks/µs.
3. **Counter saturation**: TB waits for counter to reach MAX, then fires stop_evt. Expect result clamped to MAX_US.
4. **CDC metastability probe**: Vary the phase relationship between start_evt and stop_evt to exercise the CDC paths.
5. **Multi-measurement**: Rapid start/stop pairs; verify each measurement is independent.
6. **Reset during RUN**: Fire start_evt, hold for 10 ticks, assert rst_n_sys. Expect state back to IDLE and counter = 0.

## Acceptance Criteria

- [ ] `lat_valid` fires exactly once per complete start→stop cycle.
- [ ] `lat_us` is within ±1 µs of the true elapsed time for any delay ≥ 2 µs.
- [ ] `lat_frames` equals `lat_us / 16667` (integer truncation).
- [ ] `start_evt` during DONE/IDLE always starts a fresh measurement.
- [ ] `stop_evt` before `start_evt` has no effect.
- [ ] Reset on either domain cleanly aborts any in-progress measurement.
- [ ] No combinational loops between clk_sys and clk_pix domains.
- [ ] `lat_valid` is a single-cycle pulse (not a level).

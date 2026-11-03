# key_debounce Behavior Specification

## Requirement Summary

Multi-key debouncer with four output types: stable level, single-cycle press pulse, single-cycle release pulse, and hold indicator (high continuously after 1 second of continuous press).

## Public Interface

| Port       | Direction | Width | Description |
|------------|-----------|-------|-------------|
| `clk`        | in | 1 | System clock (50 MHz) |
| `rst_n`      | in | 1 | Active-low reset |
| `key_in_n`   | in | N | Raw keys, active low (pressed = 0) |
| `key_level`  | out| N | Debounced level, high = pressed |
| `key_press`  | out| N | Single-cycle pulse on 0→1 transition |
| `key_release`| out| N | Single-cycle pulse on 1→0 transition |
| `key_hold`   | out| N | High while key held continuously ≥ 1 s |

## Parameters and Defaults

| Parameter   | Default     | Description |
|-------------|-------------|-------------|
| `N`         | `4`         | Number of keys |
| `CNT_MAX`   | `500000`    | 10 ms @ 50 MHz debounce threshold |
| `HOLD_TIME` | `50000000`  | 1 s @ 50 MHz hold threshold (internal) |

## Clocking and Reset

- **Clock**: `clk_sys` at 50 MHz. All counters and state are in this domain.
- **Reset**: active-low synchronous reset clears all per-key state.

## Functional Behavior

### Debounce FSM (per key)

Each key has an independent debouncer with two states:
1. **Stable**: `raw_input == debounced`. Counter resets.
2. **Unstable**: `raw_input != debounced`. Counter increments each clock cycle.

When the counter reaches `CNT_MAX` (10 ms), the raw input wins and the debounced state updates. This is the standard counter-based debouncer.

### Hold Detection (per key)

When `debounced == 1` (pressed) and stays pressed continuously:
- A separate hold counter increments each cycle.
- When the hold counter reaches 50,000,000 (1 second), `key_hold` becomes 1.
- `key_hold` stays high as long as the key remains pressed.
- Any release resets both the hold counter and `key_hold`.

### Edge Pulse Generation

- `key_press`: `debounced & ~prev_deb` — rises for exactly one cycle when `debounced` transitions 0→1.
- `key_release`: `~debounced & prev_deb` — rises for exactly one cycle when `debounced` transitions 1→0.
- Both are combinational from `debounced` and `prev_deb`, guaranteeing single-cycle width.

### Hold Counter Width

- Stable counter: 19 bits (2^19 = 524,288 > 500,000)
- Hold counter: 26 bits (2^26 = 67,108,864 > 50,000,000)

## Timing, Latency, and Throughput

- **Debounce latency**: 10 ms minimum; up to 20 ms worst case (if a transition occurs just after the counter resets).
- **Hold detection latency**: exactly 1 second from first stable press.
- **Hold release**: immediate on release detection.
- **All N keys processed in parallel**: no serialization.

## Assumptions and Chosen Defaults

- `key_in_n` has an external pull-up; pressing the button pulls it to 0.
- The 50 MHz clock is precise enough for the 10 ms and 1 s counters.
- If the board clock is not 50 MHz, `CNT_MAX` and the hold threshold must be scaled proportionally.
- Memory arrays `stable_cnt` and `hold_cnt` are inferred as distributed registers; the tool will infer the correct depth.

## Edge Cases and Error Handling

| Case | Behavior |
|------|----------|
| Key bounces repeatedly within 10 ms | Counter keeps resetting; debounced state does not change until stability achieved |
| Key held for exactly 999 ms then released | `key_hold` never asserts; `key_release` fires on release |
| Key pressed and released within 10 ms | Nothing changes; both are filtered out |
| All 4 keys pressed simultaneously | All four debouncers operate independently |
| `rst_n` asserted while key is held | All state clears including hold counter; must re-hold to re-assert `key_hold` |

## Synthesis Notes

- **Target**: Anlogic TD 6.2.1, EG4S20BG256
- **Resource**: N×5 registers (debounced, prev, hold, two counters) + edge logic. At N=4: ~100 DFF.
- **No BRAM / DSP / PLL required**
- Counter arrays (`stable_cnt`, `hold_cnt`) may infer SRL16/32 if the tool chooses; explicit distributed RAM is not required.

## Verification Plan

1. **Bounce filtering**: Drive key_in_n with a noisy waveform (rapid toggles < 10 ms apart); confirm debounced output stays stable.
2. **Stable acceptance**: After 10 ms of consistent input, confirm debounced matches raw.
3. **Press/release pulse**: Apply a clean long press; confirm key_press fires exactly once at press, key_release fires exactly once at release.
4. **Hold detection**: Press and hold for exactly 1.5 seconds; confirm key_hold rises after 1 s and stays high.
5. **Hold release**: While key_hold is asserted, release the key; confirm key_hold goes low immediately.
6. **Multi-key**: Press all N keys in varying patterns; confirm no cross-talk between keys.

## Acceptance Criteria

- [ ] All four outputs (`level`, `press`, `release`, `hold`) are correct per the description.
- [ ] A stable press of > 10 ms transitions `debounced` to 1.
- [ ] `key_press` is exactly 1 cycle wide and occurs at the debounced transition.
- [ ] `key_hold` is high after 1 second of continuous press and low otherwise.
- [ ] Releasing the key at any time resets the hold counter and `key_hold`.
- [ ] The module synthesizes with zero errors in Anlogic TD 6.2.1.
- [ ] Code is pure Verilog-2001; no SystemVerilog arrays (`bit`/`logic`) or procedural assertions.

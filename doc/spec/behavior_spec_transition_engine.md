# transition_engine Behavior Specification

## 1. Requirement Summary

Apply visual transition effects between two successive frame buffers:
- **Mode 1 (Fade)**: alpha-blend `rgb_cur` and `rgb_next` pixel-by-pixel
- **Mode 2 (Slide-left)**: new frame reveals from the right, pushing old left
- **Mode 3 (Slide-right)**: new frame reveals from the left, pushing old right
- **Mode 4 (Wipe)**: old frame wipes away left-to-right revealing new

Modes 2/3/4 need only one frame reader active. Mode 1 asserts `need_second`
to enable the second frame reader. `alpha` increases linearly from 0 to 255 over
`duration` frames (1..255).

## 2. Public Interface

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| clk | in | 1 | Pixel clock 25 MHz |
| rst_n | in | 1 | Async reset, active low |
| start | in | 1 | Pulse to begin a transition |
| mode | in | 4 | 1=fade, 2=slide-left, 3=slide-right, 4=wipe |
| duration | in | 8 | Frames for the transition (1..255) |
| frame_start | in | 1 | One cycle before first active pixel |
| x | in | 10 | Current column 0..639 |
| y | in | 10 | Current row 0..479 |
| de | in | 1 | Display enable |
| rgb_cur | in | 24 | Current frame pixel |
| rgb_next | in | 24 | Next frame pixel (used in fade only) |
| rgb_out | out | 24 | Transitioned pixel |
| need_second | out | 1 | 1=second frame reader must be active |
| busy | out | 1 | High during an active transition |
| done | out | 1 | One-cycle pulse when transition ends |

## 3. Parameters and Defaults

None beyond the interface contract. All timing constants are per-frame
computations using combinational logic.

## 4. Clocking and Reset

- **Domain**: `clk_pix` (25.000 MHz)
- **Reset**: Async-assert, sync-release via `rst_n`.

## 5. Functional Behavior

### 5.1 State Machine

Three states:

| State | Description |
|-------|-------------|
| IDLE | Waiting for `start` pulse. `rgb_out = rgb_cur`. |
| ACTIVE | Transition in progress. Frames 1..duration-1. |
| COMPLETE | Last frame held; one `fs_re` then returns to IDLE. |

`busy` is high in ACTIVE and COMPLETE. `done` pulses for one cycle
on the `frame_start` edge that exits COMPLETE.

### 5.2 Alpha (Fade) — Mode 1

`frame_counter` starts at 0 when `start` arrives and increments on each
`frame_start` rising edge. At frame `k` (1-indexed), alpha is:

```
alpha[k] = round((k / duration) * 255)
```

Implemented as `alpha_prod[23:16]` where
`alpha_prod = (frame_counter + 1) * 255` (Q24.8 fixed-point).

### 5.3 Progress Threshold (Slide/Wipe) — Modes 2/3/4

At frame `k`, the pixel threshold is:

```
threshold[k] = round((k / duration) * 640)  // pixels
```

Implemented as `prog_prod[23:14]` where
`prog_prod = (frame_counter + 1) * 640` (Q24.8).

- Mode 2 (slide-left) / mode 4 (wipe): `x >= threshold` → show `rgb_next`
- Mode 3 (slide-right): `x < 640 - threshold` → show `rgb_next`

### 5.4 need_second

`need_second = 1` iff `mode == 1` (fade) AND `state != IDLE`.

### 5.5 Output

`rgb_out = de ? rgb_mixed : rgb_cur` where `rgb_mixed` is:
- **Fade**: `rgb_cur + (rgb_next - rgb_cur) * alpha / 255`, per channel, saturated to 0..255
- **Slide/Wipe**: `rgb_next` or `rgb_cur` selected by threshold

## 6. Timing, Latency, and Throughput

- **Latency**: 1 cycle (registered output).
- **Throughput**: 1 pixel/cycle, 640×480@60.
- **Alpha/progress computation**: pure combinational from `frame_counter`,
  `duration_r`, and `state`. No division tree — the product is computed
  once per pixel and the division is just a bit-slice (`prod[23:16]`).

## 7. Assumptions and Chosen Defaults

- `duration >= 1`. If `duration == 0`, transition completes instantly.
- Alpha at frame 0 (idle) is 0, so no blend at the start.
- `frame_counter` is 16 bits, sufficient for ~18 hours at 60 fps before overflow.

## 8. Edge Cases

- **`start` while busy**: Ignored; must wait for `done`.
- **`duration == 1`**: Only the COMPLETE state exists; `rgb_out` immediately
  becomes `rgb_next` after the first frame.
- **`mode == 0` (no transition)**: `rgb_out = rgb_cur`; `busy = 0`.

## 9. Synthesis Notes

- **EG4 resource**: ~80 LUT4 + ~60 DFF. No BRAM, no multiplier.
- **Multiplier**: One 24×8 multiply per pixel (or one 16×8 if packed).
  At 25 MHz this is well within timing budget.
- **Assumed IP**: None.

## 10. Verification Plan

1. **iverilog compile**: zero errors.
2. **Functional TB**:
   - Mode 1: assert alpha increases monotonically 0→255 over `duration` frames.
   - Mode 2/3: assert left/right boundary moves monotonically across the screen.
   - Mode 4: same as slide-left.
   - `need_second` is 1 only during fade.
   - `busy` and `done` behave correctly.
   - `rgb_out` outside active region (`de==0`) equals `rgb_cur`.
3. **Phase check**: `rgb_out` and `de` have the same 1-cycle alignment.

## 11. Acceptance Criteria

- [x] All ports present and match contract.
- [x] Fade: alpha increases from 0 to 255 across `duration` frames.
- [x] Slide-left/wipe: new frame revealed from right to left.
- [x] Slide-right: new frame revealed from left to right.
- [x] `need_second` = 1 only during fade transitions.
- [x] `busy` high during transition, `done` one-cycle pulse at end.
- [x] Output latency: 1 cycle, aligned with input.
- [x] No `TODO`/`FIXME`/`TBD`/`stub` in source.

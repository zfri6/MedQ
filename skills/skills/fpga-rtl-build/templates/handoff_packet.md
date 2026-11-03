# RTL 生成交接文档

## Read First

- `doc/spec/behavior_spec.md`
- RTL sources under `rtl/` (top module: `<name>`)

## Anlogic IP required before synthesis

| Wrapper module | Type | Configuration | Generate with |
| --- | --- | --- | --- |
| `pll_sys` (example) | PLL | 25 MHz in → 100 MHz out, reset active-high, use `extlock` | TD → Tools → IP Generator → PLL, save to `rtl/al_ip/` |

Leave this table empty when the design is pure logic.

## Optional Next Stages

- TestBench: `fpga-tb-write` — needs `behavior_spec.md` (present) and the port table.
- Compile check: `fpga-compile-and-repair` (`--rtl-only` right after RTL; `--include-al-ip` when wrappers exist).
- Simulation: `fpga-sim-run` once a TB exists.
- Constraints: `fpga-adc-gen` — needs `rtl/top.v` with board-facing ports and `doc/hw/extracted_facts.json`.
- Synthesis / timing / bitstream: `fpga-td-build`.

## Inputs To Pass

- RTL file list and top module name
- Clock frequency assumed (default 25 MHz on HX4S20) and every real-time constant derived from it
- Board signal polarities assumed (e.g. LED active-low)

## Open Risks

| Risk | Impact | Mitigation |
| --- | --- | --- |

## Stop Conditions For Next Skill

- Interface/contract mismatch → back to `fpga-architecture` / `fpga-register-spec` / `fpga-behavior-and-wave-plan`.
- TD rejects a construct → `fpga-rtl-build` with the TD error line; see `references/anlogic_td_notes.md`.

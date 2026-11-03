# TB 生成交接文档

## Read First

- `tb/tb_top.v` — TB top module
- `tb/dut_inst.vh` — DUT instantiation
- `tb/scenario_matrix.md` — scenario coverage
- `sim/run_sim.py` — unified simulation entry (ModelSim first, iverilog fallback)
- `sim/modelsim/run.do`, `sim/modelsim/wave.do` — ModelSim batch / GUI scripts

## Compile / Run Entry

```
python sim/run_sim.py --compile-only            # syntax check with the first available simulator
python sim/run_sim.py                           # compile + run, PASS/FAIL from TB output
python sim/run_sim.py --vcd                     # also write sim/wave.vcd
python sim/run_sim.py --with-al-ip              # design uses rtl/al_ip/*.v -> ModelSim + TD sim_release libs
```

- TB top module is `tb_top` (matches `module tb_top;`); override with `--tb-top <name>`.
- All `.v` under `rtl/` and `tb/` are auto-discovered; `rtl/al_ip/` only with `--with-al-ip`.

## DUT Information

| Field | Value |
| --- | --- |
| RTL Module | TODO: fill in module name |
| Clock | TODO: fill in frequency (HX4S20 default 25 MHz per DEMO; confirm in doc/hw/extracted_facts.json) |
| Reset | TODO: fill in (e.g. async low-active `rst_n`) |
| Parameters | TODO: list all parameters and their values |
| Uses Anlogic IP | TODO: yes/no (PLL / BRAM from rtl/al_ip) |

## Optional Next Stages

- Compile check: `fpga-compile-and-repair`
- Simulation run: `fpga-sim-run`
- Waveform: `fpga-sim-run` with VCD, or ModelSim GUI via `sim/modelsim/wave.do`

## Open Risks

| Risk | Impact | Mitigation |

## Stop Conditions For Next Skill

- Compile fails: `fpga-compile-and-repair` fixes TB syntax and retries
- Simulation fails: DUT logic → `fpga-rtl-build`; TB expectation → `fpga-tb-write`
- DUT ports are wrong: back to `fpga-rtl-build`
- `EG_*` primitives undefined: not a code bug; enable `--with-al-ip` (ModelSim + TD sim_release)

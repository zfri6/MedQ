# 编译检查报告

## Compile Result

| Item | Value |
| --- | --- |
| Status | COMPILE_PASS / COMPILE_FAIL |
| Tools | iverilog (exit N) / vlog (exit N) — from `sim/sim_result.json.tools` |
| Log | `sim/compile.log` |
| Anlogic IP included | yes (`--include-al-ip`, ModelSim + TD sim_release) / no |

## Diagnostics (if failed)

| Severity | Tool | File | Line | Message | Root Cause |
| --- | --- | --- | --- | --- | --- |

## Patches Applied (if any)

| File | Change | Reason |
| --- | --- | --- |
| | | |

## Synthesizability Notes

- iverilog/vlog acceptance is not a TD synthesis result. List anything seen that TD may reject (SystemVerilog constructs in `rtl/`, `initial` blocks, `#` delays, `$display` outside `ifdef SIMULATION`, multiple drivers).

## Remaining Issues

-

## Recommended Next Stage

- Failed after 3 attempts: `fpga-tb-write` (revise TB) or `fpga-rtl-build` (fix RTL)
- Passed, user wants runtime evidence: `fpga-sim-run`
- Passed, user wants resource/timing evidence: `fpga-td-build`
- Passed, nothing else requested: done

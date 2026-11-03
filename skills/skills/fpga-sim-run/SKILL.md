---
name: 仿真运行
description: 仅在用户明确要求运行仿真或看波形时使用。用 sim/run_sim.py 驱动 ModelSim（优先）或 iverilog 运行已有 RTL+TB，判定 PASS/FAIL，按需导出 VCD 或打开 ModelSim 波形窗口。不生成 RTL，不生成 TB。
allowed-tools: [Bash, Read, Grep, Glob, Write, Edit]
user-invocable: true
argument-hint: "<optional: run_sim | generate_vcd | gui>"
arguments: [mode]
when_to_use: 用户明确要求跑仿真、验证 TestBench 结果、生成 VCD / 看波形时使用。
version: "1.0.0"
---

# Simulation Run

## Boundaries

- 只对已有 `rtl/` + `tb/` 跑仿真。缺 RTL → `fpga-rtl-build`；缺 TB → `fpga-tb-write`。
- 仿真器选择：ModelSim 优先（比赛指定，且是唯一能仿真安路 IP 的）；没装或用户指定时用 iverilog。
- 波形默认关闭；只有用户说"波形 / VCD / 看看信号"或 mode 为 `generate_vcd` / `gui` 时才开。
- 仿真编译失败不在这里修 → `fpga-compile-and-repair`。
- TB 期望错 → `fpga-tb-write`；DUT 行为错 → `fpga-rtl-build`。判断依据是 `sim/sim.log` 里的 `ERROR [scene]` 行与 `doc/spec/behavior_spec.md` 的规则。
- 产物只进 `sim/`，报告进 `doc/compile/`。

## Context Derivation

1. 读 `doc/spec/behavior_spec.md`、`tb/scenario_matrix.md`（若有），知道每个场景该是什么结果。
2. Glob `rtl/*.v`、`tb/*.v`，确认 `sim/run_sim.py` 存在；不存在则从 `fpga-tb-write/templates/run_sim.py` 复制一份到 `sim/`。
3. `rtl/al_ip/` 非空 → 必须 `--sim modelsim --anlogic-lib`；TD 未安装则报告阻塞（找不到 `sim_release`）。

## Mode

| mode | 命令 |
|---|---|
| `run_sim`（默认） | `python sim/run_sim.py --run` |
| `generate_vcd` | `python sim/run_sim.py --run --vcd` → `sim/wave.vcd` |
| `gui` | `python sim/run_sim.py --gui` → 打开 ModelSim，加载 `sim/modelsim/wave.do`（非阻塞，交给用户看） |

附加：`--sim iverilog|modelsim`、`--tb-top <module>`、`--anlogic-lib`、`--timeout <s>`。

## Workflow

1. 运行对应命令；退出码 127 = 无仿真器 → 停止并报告。
2. 读 `sim/sim_result.json`：`status` 为 `PASS` / `FAIL` / `COMPILE_FAIL`，`details` 列出 TB 打印的 `ERROR`/`TIMEOUT` 行。
3. `COMPILE_FAIL` → 不修，路由 `fpga-compile-and-repair`。
4. `FAIL` → 对照 `behavior_spec.md` 逐条判断是 TB 期望错还是 DUT 错，写进报告并给去向。
5. 写 `doc/compile/run_report.md`：命令、仿真器与版本、PASS/FAIL、失败场景、日志路径、波形路径、下一步。
6. 在总结里给关键结论（几条场景通过、哪条失败、失败信号名与时间）。

## Output Artifacts

- `sim/compile.log`、`sim/sim.log`、`sim/sim_result.json`
- `sim/wave.vcd`（`generate_vcd`）或 ModelSim 窗口（`gui`）
- `doc/compile/run_report.md`

## Completion Gate

- 仿真退出 0 且日志有 `PASS` → 完成
- 或失败但报告已写清失败阶段、日志路径、失败场景、下一步归属

## 说明

- `run_sim.py` 的判定规则：退出码 0、存在 `PASS` 行、不存在 `FAIL`/`ERROR`/`TIMEOUT`/`Fatal` 行。TB 不按此约定打印时先修 TB。
- ModelSim 批处理用 `vsim -c ... -do "run -all; quit -f"`，工作库在 `sim/work/`（可删）。
- 仿真通过不代表时序满足；上板前仍要 `fpga-td-build` 看 `*_pr.timing`。

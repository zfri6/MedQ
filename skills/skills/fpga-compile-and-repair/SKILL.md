---
name: 编译检查
description: 对 rtl/ + tb/ 做纯编译检查：iverilog -tnull 秒级快检，ModelSim vlog 作为权威结论；工具输出为准定位语法错误，最小补丁收敛修复。不运行仿真，不生成波形。
allowed-tools: [Bash, Read, Grep, Glob, Edit, Write]
user-invocable: true
argument-hint: "<optional: tb_top=<module> | tool=iverilog|modelsim|both>"
arguments: [compile_entry]
when_to_use: 需要检查 RTL/TB 能否通过编译，或修复编译错误时使用。
version: "1.0.0"
---

# Compile & Check

## Boundaries

- 只编译不仿真：不调用 `vvp` / `vsim`。
- 诊断必须来自真实工具输出（`sim/compile.log`）。
- 以 ModelSim `vlog` 为权威；iverilog 只做快检。二者不一致时信 vlog；iverilog 对合法 Verilog-2001 的独有报错记录后忽略。
- 最小补丁：只改报错指向的位置，不重写、不"顺手优化"。
- 不忽略会改变行为的告警：位宽截断、有符号/无符号混用、latch 推断、多驱动、复位语义。
- 3 轮修复未收敛 → 写 `doc/compile/repair_report.md` 停止。
- 工具缺失按 `rules/30-fpga-toolchain.md` 报告阻塞；不建议系统级安装。
- 编译通过 ≠ TD 可综合。总结里明确这一点，并建议下一步 `fpga-td-build synth_only`。

## Context Derivation

1. `doc/intake/summary.md`、`doc/spec/behavior_spec.md` 存在 → 取模块名与约定。
2. 直接调用 → 扫 `rtl/*.v`、`rtl/al_ip/*.v`、`tb/*.v`；TB 顶层默认 `tb_top`，否则从文件名推。不要因为缺上游文件而拒绝。
3. `rtl/al_ip/` 非空 → 加 `--with-anlogic-lib`（需要 TD 已安装以找到 `sim_release`；未安装时 vlog 会报 `EG_PHY_PLL` 未定义，这是**预期内**的，标注为 "IP model missing (TD not installed)" 而不是 RTL 错误）。

### 参数 compile_entry（可选）

- `tb_top=<module>`：指定 TB 顶层
- `tool=iverilog|modelsim|both`：指定工具（默认 auto：有什么用什么，都有则两个都跑）

## Workflow

### Step 1 — 编译

```powershell
python <skill>/scripts/compile_check.py [--tool auto|iverilog|modelsim|both] [--tb-top tb_top] [--with-anlogic-lib]
```

产出 `sim/compile.log`、`sim/compile_result.json`。退出码 0 PASS / 1 FAIL / 127 无工具。

### Step 2 — 诊断

```powershell
python <skill>/scripts/parse_compile_log.py sim/compile.log --out sim/compile_diag.json
```

按 `file:line` 聚类错误；一个根因往往产生多条报错，先修最早的那条。

### Step 3 — 修复循环（最多 3 轮）

1. 读报错位置前后 20 行。
2. 按 `references/minimal_patch_policy.md` 施加一个逻辑修复批次。
3. 重跑 Step 1。
4. 报错指向规格/接口歧义（端口不存在、位宽与契约矛盾、参数含义不明）→ 停止，路由 `fpga-rtl-build` 或 `fpga-tb-write`，附诊断。

### Step 4 — 报告

写 `doc/compile/check_report.md`（模板 `templates/check_report.md`）：每个工具的 PASS/FAIL 与退出码、错误/告警计数、已应用的补丁列表、下一步归属。未收敛时另写 `doc/compile/repair_report.md`（模板 `templates/repair_report.md`）。

## Output Artifacts

- `sim/compile.log`、`sim/compile_result.json`、`sim/compile_diag.json`
- `doc/compile/check_report.md`
- `doc/compile/repair_report.md`（未收敛时）
- 修补后的 RTL/TB

## Completion Gate

- 权威工具（有 ModelSim 时为 vlog；否则 iverilog）退出码 0 → 报告 PASS
- 或 3 轮未收敛 → `repair_report.md` 写明根因假设、已试补丁、建议去向

## Skill Handoff

- PASS → 可选：`fpga-sim-run` 跑 TB；`fpga-td-build synth_only` 验证 TD 可综合
- RTL 逻辑/接口问题 → `fpga-rtl-build`
- TB 结构问题 → `fpga-tb-write`

## Bundled Resources

- `scripts/compile_check.py`：iverilog / vlog 编译，写 log 与 json
- `scripts/parse_compile_log.py`：iverilog / ModelSim / TD 日志 → JSON 诊断
- `references/minimal_patch_policy.md`、`references/tool_first_diagnostics.md`
- `templates/check_report.md`、`templates/repair_report.md`

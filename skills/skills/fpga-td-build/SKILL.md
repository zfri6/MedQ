---
name: TD工程构建
description: 为安路 EG4S20BG256（康芯 HX4S20 板）生成 TD 6.2.1 工程文件（.al）与批处理 Tcl，运行综合、布局布线、生成位流，并把资源/时序报告摘要成 markdown。用于"综合一下""看资源占用""生成位流""上板"等请求。
allowed-tools: [Read, Grep, Glob, Write, Edit, Bash]
user-invocable: true
argument-hint: "<optional: top_module | synth_only | bitgen>"
arguments: [mode]
when_to_use: RTL 已通过仿真编译检查、约束（.adc/.sdc）已生成，或用户明确只想看综合结果时使用。上板前的最后一步。
version: "1.0.0"
---

# TD Build (Anlogic Tang Dynasty 6.2.1)

## MedQ 本机校准入口（2026-10-26，优先于下方历史脚本）

使用项目 prj/td/medq_td.py，见 prj/td/README.md；旧 gen_td_project.py/run_td.py 保留为历史模板，当前项目不再使用。
已实测：TD 已装；td_commands_prompt.exe script.tcl；package=EG4S20BG256；逐源 analyze + elaborate；授权已复测通过，真实顶层已完成综合。
--mode synth 只到 optimize_gate，implement/bitgen 要求真实硬件前置条件。无完成标记/产物或未知时序不能判 PASS。
工程 XML 只是准备结果，GUI 加载未验收；当前批处理不依赖普通 open_project .al。

把 `rtl/` + `prj/constr/` 变成 TD 能打开的工程和能下载到 HX4S20 的位流。器件、Tcl 命令、报告路径以 `rules/05-hx4s20-target.md`、`rules/30-fpga-toolchain.md` 与 `references/td_flow_notes.md` 为准。

## Boundaries

- 不修改 RTL、不修改约束。TD 报错按 `rules/50-fpga-compile-fail-routing.md` 的表格路由回 `fpga-rtl-build` / `fpga-adc-gen` / `fpga-hw-manual-extraction`。
- 不猜器件。`.al` 固定 `EG4` / `EG4S20BG256`；`build.tcl` 默认 `import_device eagle_s20.db -package BG256`，实际 `.db` 名由 `find_tools.py` 在 `<TD_HOME>/arch/` 里核实并写入 `doc/hw/toolchain.json`。
- 没有 `.adc` 时不要跑到 bitgen：TD 会自动分配引脚，位流在真实板子上是危险的。只允许 `synth_only`（`--no-bitgen`），并在总结里说明缺约束。
- TD 未安装（当前本机状态）时只生成 `.al` + `build.tcl`，输出"等待安装 TD"及安装包路径，不做替代方案。
- 下载位流需要人操作 TD Download 工具，skill 只给步骤。

## Context Derivation

1. 运行 `find_tools.py` 刷新 `doc/hw/toolchain.json`（TD / ModelSim / iverilog 路径、`arch/*.db` 列表、workspace 是否为 ASCII 路径）。
2. 顶层模块名：参数 > `doc/arch/interface_contract.yaml` 的 top > `rtl/top.v` 里的 `module top` > 唯一的板级模块。找不到就问。
3. Glob `rtl/*.v`、`rtl/al_ip/*.v`、`prj/constr/*.adc`、`prj/constr/*.sdc`。
4. `toolchain.json` 的 `workspace_ascii` 为 `false`（当前 workspace 在 `Desktop\安路\` 下）→ 运行 TD 时必须 `--mirror C:/anlogic_work/<name>`。

## Workflow

### Step 1 — 探测工具

```powershell
python <skill>/scripts/find_tools.py
```

退出码 2 = TD 未装：仍可继续 Step 2 生成工程文件，然后停止。

### Step 2 — 生成工程与批处理脚本

```powershell
python <skill>/scripts/gen_td_project.py --top <top> [--name <name>] [--no-bitgen]
```

产出 `prj/td/<name>.al`（可直接双击用 TD GUI 打开，结构与 DEMO 一致）和 `prj/td/build.tcl`（`import_device → read_verilog → read_adc/sdc → elaborate → optimize_rtl → optimize_gate → place → route → bitgen`，报告写到 `prj/td/reports/`）。

### Step 3 — 运行 TD

```powershell
python <skill>/scripts/run_td.py                                   # ASCII 路径的 workspace
python <skill>/scripts/run_td.py --mirror C:/anlogic_work/<name>   # 中文路径的 workspace（当前情况）
python <skill>/scripts/run_td.py --report-only                     # 只重新解析已有报告
```

- 退出码 127 = 未找到 `td.exe` → 停止，报告。
- 退出码 1 = TD 报 ERROR 或时序未收敛 → 读 `prj/td/td_run.log` 与 `doc/compile/td_report.md`，按 `rules/50` 分流；同一问题最多 3 轮。
- `td.exe -f` 若在本机 TD 上不被接受，改为提示用户在 TD GUI 的 Tcl Console 中 `cd <prj_dir>; source prj/td/build.tcl`，并把这一事实写入 `doc/hw/toolchain.json` 的 `td.batch_mode` 字段。

### Step 4 — 读报告

`run_td.py` 已生成 `prj/td/reports/summary.json` 与 `doc/compile/td_report.md`（含每份报告的原文尾部）。解析是启发式的：若 `area` / `timing` 字段为空，直接读 `prj/td/reports/*_phy.area`、`*_pr.timing` 原文，把 LUT/FF/BRAM/PLL 用量与最差 slack 手工补进 `td_report.md`，并修正 `run_td.py` 的正则、更新 `references/td_flow_notes.md` 的"Reports"一节。

### Step 5 — 下载步骤（写进总结，不执行）

1. TD → Tools → Download。
2. Add 选择 `prj/td/output/<name>.bit`（`--mirror` 运行时已拷回本目录）。
3. 模式 `JTAG`，Operation `Program`（SRAM，掉电丢失）或 `Program Flash`（固化）。板子上电、USB 下载线接好后 Run。
4. 需要下载器驱动时指向 `HX4S20_Contest_202606/1_安路工具和软件/`。

## Output Artifacts

- `doc/hw/toolchain.json`
- `prj/td/<name>.al`、`prj/td/build.tcl`
- `prj/td/td_run.log`、`prj/td/reports/*`（`*_rtl.area`、`*_phy.area`、`*_pr.timing`、`*_phy.ts`、`summary.json`）
- `prj/td/output/<name>.bit`
- `doc/compile/td_report.md`

## Completion Gate

- `synth_only`：`optimize_gate` 完成、`*_gate.area` 存在、日志无 ERROR。
- 完整构建：`.bit` 存在、`summary.json` 的 `timing_met` 不为 `false`（或负 slack 已在总结里如实报告并给出去向）、`td_report.md` 已写。
- 任何一步失败：总结里说明失败的 TD 步骤、日志路径、下一步归属，不得写"应该能过"。

## 与 DEMO 工程的关系

`HX4S20_Contest_202606/2_Example/DEMO/*` 是同一芯片、同一 TD 版本跑通过的工程。遇到 TD 行为不确定时（命令名、报告格式、IP 例化方式），优先对照对应 DEMO 的 `*_Runs/syn_1/*.tcl`、`*.al`、`al_ip/*.v`，而不是查 Xilinx/Intel 资料。

## Bundled Resources

- `scripts/find_tools.py`：探测 TD / ModelSim / iverilog，写 `doc/hw/toolchain.json`
- `scripts/gen_td_project.py`：生成 `.al` 与 `build.tcl`
- `scripts/run_td.py`：运行 TD（支持 `--mirror`），解析报告
- `references/td_flow_notes.md`：TD 流程命令、`.al` 结构、IP 产物、报告格式（待校准）

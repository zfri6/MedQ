# FPGA Toolchain Policy（安路 TD + ModelSim + iverilog）

2026-10-26 本机修订：TD 已安装（见 doc/hw/toolchain.json），综合授权已复测通过，当前缺口见 doc/compile/td_report.md。
已验证批处理为 td_commands_prompt.exe + prj/td/medq_td.py，EG4 模型在 sim_release/eg4。
下文“TD 尚未安装（当前本机状态）”为历史描述，不适用于当前 MedQ 工作区。

## 三个工具各司其职

| 工具 | 用途 | 权威性 |
|---|---|---|
| **安路 TD 6.2.1** | 综合、布局布线、时序分析、位流生成、下载 | 最终交付的唯一权威。RTL 是否"可综合"、资源是否够、时序是否收敛，只信 TD 报告 |
| **ModelSim**（本机 10.4，比赛 14.1） | 功能仿真；安路 IP（PLL/BRAM）仿真必须用它 | 仿真结果的权威 |
| **iverilog**（本机 `C:\iverilog\bin`） | 秒级语法快检、纯逻辑模块的快速仿真 | 仅作预检。iverilog 通过不代表 TD 能综合；iverilog 报错基本可信 |

不要用 iverilog 的结论替代 TD；不要在 iverilog 上仿真含 `EG_PHY_PLL`、`EG_LOGIC_BRAM` 等原语的设计。

## 工具发现顺序

所有脚本（`sim/run_sim.py`、`fpga-compile-and-repair/scripts/compile_check.py`、`prj/td/build.tcl` 的驱动脚本）按以下顺序找工具，找不到就**报告阻塞并停止**，不要反复重试、不要建议 `apt/brew/yum`：

1. 环境变量：`TD_HOME`、`MODELSIM_HOME`、`IVERILOG_HOME`
2. `doc/hw/toolchain.json`（首次探测成功后由脚本写入，字段：`td_home`、`td_exe`、`device_db`、`package`、`modelsim_bin`、`iverilog_bin`、`sim_release_dirs`）
3. PATH：`td.exe`、`vsim`/`vlog`、`iverilog`/`vvp`
4. 常见安装目录：`C:\Anlogic\TD*`、`D:\Anlogic\TD*`、`C:\modeltech64_*`、`C:\intelFPGA*\*\modelsim_ase\win32aloem`、`C:\iverilog`

TD 尚未安装时（当前本机状态），涉及 TD 的阶段直接输出"等待安装 TD 6.2.1"并给出安装包路径 `HX4S20_Contest_202606/1_安路工具和软件/`，提醒按 `重要！安装后必看.txt` 替换 license；不要尝试替代方案。

## 路径规则

- 本机 shell 是 **PowerShell**，`bash` 指向 WSL 的 `System32\bash.exe`，不保证可用。工具脚本统一用 **Python 3**（`python`，本机 3.12），不写 bash。
- 脚本内一律用相对于工程根目录的相对路径；需要绝对路径时用 `Path.cwd()` 拼。
- 传给 TD Tcl 和 ModelSim `.do` 的路径用正斜杠 `/`（两者都接受 `C:/...`）。
- 中文路径：TD 6.2 对中文路径支持不稳定。**工程目录（含 `prj/td/`）必须放在纯 ASCII 路径下**；若 workspace 在 `Desktop\安路\...` 这类路径下，`fpga-td-build` 应把 TD 工程输出到用户指定的 ASCII 路径（默认 `C:\anlogic_work\<name>\`），并在 `doc/hw/toolchain.json` 记录映射。

## iverilog 用法（快检）

```powershell
iverilog -g2012 -Wall -tnull -I rtl -I tb -s tb_top rtl/*.v tb/*.v 2>&1 | Tee-Object sim/compile.log
```

- `-tnull` 只做语法/连接检查，不产出 `.vvp`。
- `-g2012` 仅为了让 TB 里可用 SV 断言/`$fatal`；RTL 本身必须是 Verilog-2001。

## ModelSim 用法（权威编译 + 仿真）

```
vlib sim/work
vmap work sim/work
vlog -work work +define+SIMULATION rtl/*.v tb/*.v
vlog -work work -incr <TD_HOME>/sim_release/al/*.v <TD_HOME>/sim_release/eg/*.v   ;# 仅在用了安路 IP 时
vsim -c -voptargs=+acc work.tb_top -do "run -all; quit -f"
```

- 批处理用 `vsim -c`，GUI 看波形用 `vsim -gui ... -do sim/modelsim/wave.do`。
- `+define+SIMULATION` 与 DEMO 一致，IP wrapper 内部会据此切换仿真模型。
- 输出：`sim/compile.log`（vlog）、`sim/sim.log`（vsim transcript）、波形 `sim/wave.wlf`（ModelSim 原生）或 `sim/wave.vcd`（TB 中 `$dumpfile`）。

## TD 用法（综合到位流）

- GUI：双击 `prj/td/<name>.al` 打开，依次 Synthesize → Place & Route → Generate Bitstream → Download。
- 批处理：`<TD_HOME>/bin/td.exe -f prj/td/build.tcl`（脚本模板见 `fpga-td-build/templates/build.tcl`）。若本机 `td.exe` 不接受 `-f`，改为在 TD 的 Tcl Console 里 `source prj/td/build.tcl`。
- 报告：`prj/td/reports/*_rtl.area`、`*_phy.area`（资源）、`*_pr.timing`（时序）。`fpga-td-build` 必须解析并摘要到 `doc/compile/td_report.md`。
- 下载：TD 的 Download 工具，JTAG 模式选 `JTAG`，文件选 `prj/td/output/<name>.bit`。这一步需要人操作，skill 只给步骤。

## 禁止事项

- 不执行或建议 `brew/apt/yum/pip install iverilog` 等系统级安装。
- 找不到工具时不反复重试、不换调用方式；工具缺失是阻塞条件。
- 不在 skill 之外做"工具链探测 + 安装建议"分支；工具可用性记为 `fpga-intake` 的阻塞项。
- 不生成 Vivado/Quartus/Gowin 的约束或脚本。

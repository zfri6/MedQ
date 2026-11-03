# 目标平台：康芯 HX4S20 开发板（安路 EG4S20BG256）

## MedQ / HX4S20C 实测修订（2026-10-26，优先于下文历史口径）

- 用户确认板型 HX4S20C，输入 50 MHz@R7；依据见 doc/hw/extracted_facts.json，不沿用旧示例 25 MHz 推断。
- TD 已装 V6.2.168116；入口 td_commands_prompt.exe script.tcl，package selector=EG4S20BG256，BG256 被实测拒绝。
- EG4 模型在 sim_release/eg4/；不是下文历史 eg/。真实综合授权已复测通过，见 doc/compile/td_report.md。
- 40 bit 主链路 IO 已按匹配 DEMO 原样映射并记录来源，可推进 ADC；具体电气冲突和扩展另核对。
- 当前校准入口为 prj/td/medq_td.py（逐源 analyze 后 elaborate）；下文旧 Tcl 不作为本机已验证命令。

本规则集面向 2026 安路赛道（HX4S20_Contest_202606）。所有 FPGA skill 在做器件、工具链、约束格式、仿真库相关决策时，以本文件为唯一事实来源；与本文件冲突的通用 FPGA 常识（Xilinx/Vivado/XDC 习惯）一律不采用。

## 已确认事实（来自比赛资料 DEMO 工程，可直接引用）

| 项目 | 值 | 证据 |
|---|---|---|
| 开发板 | 康芯 HX4S20 | `HX4S20_Contest_202606/资料指引.docx` 第 9 条 |
| FPGA 厂商 | 安路科技 Anlogic | — |
| 器件家族 | `EG4` | DEMO `*.al` 中 `<Family>EG4</Family>` |
| 器件型号 | `EG4S20BG256` | DEMO `*.al` 中 `<Device>EG4S20BG256</Device>` |
| 开发工具 | 安路 TD（Tang Dynasty）6.2.1，内部版本号 `6.2.168116` | `1_安路工具和软件/安路开发软件TD_6.2.1版本.zip`、DEMO `*.al` 中 `<TD_Version>` |
| 仿真器 | ModelSim 14.1（比赛提供）；本机已装 ModelSim 10.4（`C:\modeltech64_10.4`） | `1_安路工具和软件/ModelSimSetup-14.1.0.186-windows.exe` |
| 工程文件 | `<name>.al`（XML） | DEMO |
| 物理约束 | `.adc`（Anlogic Design Constraint），命令 `set_pin_assignment` | DEMO `*.adc` |
| 时序约束 | `.sdc`（`create_clock` / `create_generated_clock` / `set_clock_groups` / `derive_pll_clocks`） | DEMO `ph1_demo.sdc` |
| IP 文件 | `al_ip/*.v`（IP Generator 产物）+ `al_ip/*.ipc` | DEMO |
| PLL 原语 | `EG_PHY_PLL`（TD IP Generator 生成的 PLL wrapper 内部例化） | DEMO `al_ip/PLL.v` |
| 编码 | `.al` 中 `<TD_Encoding>GB2312</TD_Encoding>`；源码建议 UTF-8 无 BOM 且**注释避免中文**，防止 TD 6.2 报编码告警 | DEMO |

## 需要在真实资料中确认、不得臆测的事实

以下信息 DEMO 之间互相矛盾或未提供，必须由 `fpga-hw-manual-extraction` 从《HX4S20 使用手册/引脚说明》（资料目录 9）和原理图（资料目录 3）中确认：

- 板载晶振频率与引脚：DEMO `0_cnt1s` 用 `CLOCK` @ `R7`，1 秒计数值 `24999999`（暗示 25 MHz）；DEMO 以太网工程用 `clk_25` @ `R7`，`create_clock -period 40`（25 MHz）。两处一致指向 25 MHz @ R7，但仍要以手册为准。
- Bank 电压 / IOSTANDARD：DEMO `0_cnt1s` 全部 `LVCMOS33`，以太网 DEMO 全部 `LVCMOS25`。**同一块板不可能两者都对**，必须查原理图确定各 Bank 电压后再写 IOSTANDARD。
- LED / KEY / 数码管 / UART / VGA / 以太网 PHY（RTL8211E，RGMII）等外设的具体引脚：DEMO 各 `.adc` 可作为高置信度参考（它们是在该板上跑通过的），但必须标注 `source_ref` 指向具体 DEMO 文件，并用手册交叉校验。

## 约束文件语法（必须照此生成，不要写 Vivado XDC）

```tcl
# prj/constr/top.adc  —— 物理约束
set_pin_assignment	{ CLOCK }	{ LOCATION = R7; IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }
set_pin_assignment	{ LED[0] }	{ LOCATION = A4; IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 8; PULLTYPE = NONE; }
set_pin_assignment	{ rst_n }	{ LOCATION = A2; IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }
# 高速输出可加：SLEWRATE = FAST; DRIVESTRENGTH = 16; OUTDEL = 3;
# 不接实际引脚的端口：{ LOCATION = virtualIO; }
```

```tcl
# prj/constr/top.sdc  —— 时序约束
create_clock -name clk_in -period 40 -waveform {0 20} [get_ports {CLOCK}]
create_generated_clock -name {pll_c0} -source [get_ports {CLOCK}] -master_clock {clk_in} -multiply_by 2.000 [get_pins {u_pll/pll_inst.clkc[0]}]
set_clock_groups -exclusive -group [get_clocks {clk_a}] -group [get_clocks {clk_b}]
derive_pll_clocks -instance [get_cells {u_pll/pll_inst}]
```

- 总线端口逐 bit 写：`{ LED[0] }`、`{ LED[1] }`，不要写 `LED[3:0]`。
- 端口名必须与 RTL 顶层端口**完全一致**（大小写敏感）。
- 属性键：`LOCATION`、`IOSTANDARD`、`PULLTYPE`（`PULLUP|PULLDOWN|NONE`）、`DRIVESTRENGTH`（4/8/12/16）、`SLEWRATE`（`FAST|SLOW`）、`OUTDEL`。

## TD 批处理流程（参考 DEMO `*_Runs/syn_1/*.tcl` 的可编辑区）

```tcl
import_device eagle_s20.db -package BG256
read_verilog rtl/xxx.v            ;# 每个源文件一行，或 open_project prj/td/<name>.al
read_adc prj/constr/top.adc
read_sdc prj/constr/top.sdc
elaborate -top <top_module>
optimize_rtl
report_area -file prj/td/reports/<name>_rtl.area
optimize_gate
legalize_phy_inst
place
route
report_area -io_info -file prj/td/reports/<name>_phy.area
update_timing -mode final
report_timing_summary -file prj/td/reports/<name>_pr.timing
bitgen -bit prj/td/output/<name>.bit
```

`eagle_s20.db` 与 `BG256` 是 EG4S20BG256 对应的器件库与封装名；首次在本机运行前必须在 `<TD_HOME>/arch/` 下确认该 `.db` 文件存在，若名称不同以实际文件为准并更新 `doc/hw/toolchain.json`。

## ModelSim 仿真库

安路原语（PLL、BRAM 等）的仿真模型在 TD 安装目录 `<TD_HOME>/sim_release/`：

- `sim_release/al/*.v`：通用原语
- `sim_release/eg/*.v`：EG4 家族原语（`EG_PHY_PLL`、`EG_LOGIC_BRAM` 等）

只要 RTL 例化了 `al_ip/*.v` 里的 IP，ModelSim 编译就必须加这两组文件（`vlog -incr <TD_HOME>/sim_release/al/*.v <TD_HOME>/sim_release/eg/*.v`）。纯逻辑设计无需加载。iverilog 不能仿真这些原语，遇到 IP 一律用 ModelSim。

## 比赛资料目录索引

| 目录 | 内容 | 谁用 |
|---|---|---|
| `1_安路工具和软件` | TD 6.2.1 安装包、ModelSim 14.1、`Anlogic.lic`、安装教程 | 人工安装 |
| `2_Example/DEMO` | 30+ 个 TD 工程示例（`.al`、`.adc`、`.sdc`、`.v`、`sim/*.do`） | `fpga-hw-manual-extraction`（引脚参考）、`fpga-td-build`（工程模板）、`fpga-sim-run`（.do 模板） |
| `3_原理图` | 开发板与摄像头转接板原理图 | `fpga-hw-manual-extraction`（Bank 电压、引脚） |
| `4_芯片手册` | RTL8211E（以太网 PHY）、HR911130A（RJ45）、OV5640 | 外设接口设计 |
| `6_EG4S20` | EG4 系列技术手册 | 资源上限、原语、IO 标准 |
| `7_lab_ex_2026_nosoft` | 2026 赛题二例程与资料 | 赛题需求来源 |
| `9_康芯HX4S20使用手册及实验平台介绍` | 板卡使用手册、**引脚说明** | `fpga-hw-manual-extraction`（第一优先级来源） |

目录 3/6/7/9 当前本地未解压；需要时先向用户索取。

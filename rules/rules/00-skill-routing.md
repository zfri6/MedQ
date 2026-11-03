# Skills Routing Rules (FPGA / 安路 HX4S20)

总原则：

1. 优先使用最窄、产物最明确的 skill。
2. 需求模糊、缺少验收标准时先用 `fpga-intake`；需求明确（包含具体模块名、功能描述或已有代码参考）时直接跳到对应的实现类 skill。
3. 若用户明确指定某个 `fpga-*` skill，且与请求一致，则直接调用该 skill。
4. 器件、工具链、约束格式、仿真库的任何决策以 `rules/05-hx4s20-target.md` 为准。

## Skill 清单

| Skill | 职责 | 主要产物 |
|---|---|---|
| `fpga-intake` | 需求梳理、硬件依赖判断、路由 | `doc/intake/summary.md` |
| `fpga-hw-manual-extraction` | 从手册/原理图/DEMO `.adc` 提取引脚、时钟、电气事实 | `doc/hw/extracted_facts.json` |
| `fpga-architecture` | 模块拆分、接口契约、时钟/复位/CDC、顶层骨架 | `doc/arch/*`、`rtl/top_skeleton.v` |
| `fpga-register-spec` | 寄存器地图与语义 | `doc/reg/*` |
| `fpga-behavior-and-wave-plan` | 行为规格、波形检查点 | `doc/spec/*` |
| `fpga-rtl-build` | 可综合 Verilog-2001 RTL | `rtl/*.v`、`doc/spec/behavior_spec.md` |
| `fpga-tb-write` | 自检 TestBench | `tb/*.v`、`sim/run_sim.py`、`sim/modelsim/*.do` |
| `fpga-compile-and-repair` | 语法编译检查（iverilog 快检 + ModelSim vlog 权威）与最小修复 | `sim/compile.log`、`doc/compile/check_report.md` |
| `fpga-sim-run` | 运行仿真（ModelSim 优先，iverilog 备选），按需导出波形 | `sim/sim.log`、`sim/sim_result.json`、`sim/wave.vcd`/`.wlf` |
| `fpga-adc-gen` | 生成安路 `.adc` 物理约束 + `.sdc` 时序约束 | `prj/constr/top.adc`、`prj/constr/top.sdc` |
| `fpga-td-build` | 生成 TD 工程 `.al` 与批处理 Tcl，运行综合/布局布线/生成位流，解析报告 | `prj/td/<name>.al`、`prj/td/build.tcl`、`prj/td/reports/*`、`prj/td/output/*.bit` |

## 目录约定（所有 FPGA Skill 必须遵守）

| 产物类型 | 路径 | 规则 |
|---|---|---|
| RTL 源文件 | `rtl/*.v` | 可综合 Verilog-2001；`fpga-rtl-build` 专用 |
| 安路 IP | `rtl/al_ip/*.v` | TD IP Generator 生成的 wrapper，原样保留，不手改 |
| TB 源文件 | `tb/*.v`、`tb/*.vh` | `fpga-tb-write` 专用，平铺 |
| 仿真脚本与产物 | `sim/` | `run_sim.py`、`modelsim/*.do`、`compile.log`、`sim.log`、`sim_result.json`、`wave.vcd`、`work/` |
| 约束文件 | `prj/constr/*.adc`、`prj/constr/*.sdc` | `fpga-adc-gen` 专用 |
| TD 工程 | `prj/td/` | `.al`、`build.tcl`、`reports/`、`output/`、TD 运行产物 `*_Runs/` |
| 硬件事实 | `doc/hw/` | `extracted_facts.json`、`toolchain.json`、用户上传的手册/原理图副本 |
| 规格/说明 | `doc/intake/`、`doc/arch/`、`doc/reg/`、`doc/spec/`、`doc/compile/` | 只放 markdown/yaml/json |

> 可综合 RTL 只能写到 `rtl/`；`doc/` 下不得出现 `.v`。TB 只能写到 `tb/`；不要新建 `doc/sim/`。

## RTL / TB / 编译 分流

- **生成类**（从零生成模块、重写状态机、改接口协议、改数据通路）：必须通过 `fpga-rtl-build` / `fpga-tb-write`，一次一个模块或一套 TB。
- **编辑类**（加注释、格式化、修语法错误、改参数值/位宽）：直接用编辑工具改，不走 skill。
- 禁止在主对话里不经 `fpga-rtl-build` 直接写出完整的可综合模块正文。

## 多模块任务必须先架构

涉及 2 个以上相互通信的子模块、协议初始化序列（SPI Flash、SD 卡、以太网 PHY 初始化、UART 协议栈等）、CRC/包组装/握手、多时钟域，或顶层端口未定义时，先 `fpga-architecture` 再 `fpga-rtl-build`。`fpga-rtl-build` 一次调用只生成一个模块；架构给出 N 个模块就调用 N 次。

## 协议时序敏感模块判定标准

命中以下任一条的模块视为"协议时序敏感"，即使只有单个模块也**不得**走快速路径，必须先由 `fpga-architecture` 或 `fpga-behavior-and-wave-plan` 冻结契约：

1. 存在 launch edge / sample edge 选择（SPI 模式、I2C、RGMII DDR、SDRAM/DDR 接口、PS/2）。
2. 存在多阶段 phase ordering 或命令/响应边界（SD 卡 CMD0→CMD8→ACMD41…、以太网 PHY MDIO 配置、LCD/OLED 初始化序列、UART 协议帧解析）。
3. 存在片选/使能生命周期（CS 何时拉低拉高、burst 内是否保持）。
4. 存在跨时钟域数据通路且未说明 CDC 方式。
5. 需要与外部芯片手册（目录 `4_芯片手册`）中的时序参数对齐。

"契约已冻结"指以下内容已写入 `doc/arch/interface_contract.yaml` 或 `doc/spec/behavior_spec.md`：端口与位宽、时钟/复位极性、每个阶段的进入/退出条件、边沿语义、超时与错误处理。RTL 阶段若发现契约漂移，回退到上游补齐，不在同层盲重试。

## 路由表（按用户意图）

- 需求含混、缺验收：`fpga-intake`
- 简单单模块（计数器、分频器、移位寄存器、按键消抖、数码管扫描、简单 FSM）：直接 `fpga-rtl-build`，用合理默认端口（`clk`、低有效 `rst_n`），假设写入 `doc/spec/behavior_spec.md`
- 生成 TB：`fpga-tb-write`（按文件逐一调用）
- 语法检查 / 编译修复：`fpga-compile-and-repair`
- 跑仿真 / 看波形：`fpga-sim-run`（缺 TB 时先提示生成 TB）
- 管脚分配 / 约束：`fpga-adc-gen`；缺硬件事实时先 `fpga-hw-manual-extraction`
- 综合 / 布局布线 / 生成位流 / 看资源和时序报告 / 上板：`fpga-td-build`
- 寄存器表、总线控制面：`fpga-register-spec`
- 行为规格、波形检查点：`fpga-behavior-and-wave-plan`

### 板级顶层引导

用户提到 LED、KEY、数码管、蜂鸣器、UART、VGA、以太网、上板、管脚时，检查 `rtl/` 是否有板级顶层：

1. `doc/hw/extracted_facts.json` 已有板级信号名与引脚 → 生成 `rtl/top.v`（通过 `fpga-rtl-build`，或先 `fpga-architecture` 规划）。
2. 没有硬件事实 → 先 `fpga-hw-manual-extraction`（来源：目录 9 手册、目录 3 原理图、DEMO `.adc`），再 `top.v`，再 `fpga-adc-gen`。
3. 纯内部模块（ALU、FIFO、协议引擎）且用户没提上板 → 不主动建议 `top.v`。

约束依赖"顶层模块 + 硬件事实"两个前提，缺一不可；缺信息时补信息，不猜。

## 阶段可选策略（默认省算力）

- 用户只要 RTL：完成 RTL 后停止，把 TB / 编译检查 / 仿真 / 约束 / TD 构建作为可选下一步列出。
- 默认不自动编译、不自动仿真、不自动导波形、不自动生成约束、不自动跑 TD。
- 用户要求"完整流程/全套交付/上板"：RTL → TB → 编译检查 → 仿真 → 约束 → TD 构建 → 位流。波形仍需用户明确要求。
- 文件写入后不要再跑额外命令"确认"；直接给总结。

## 质量门槛（所有生成类 skill 通用）

- 产物中不得出现 `// ...`、`// TODO`、`// FIXME`、`// TBD`、`// stub`、"omitted"、空 `begin end` 块、注释掉的整段 `always/case`。出现即视为未完成，不得声称"已完成"。
- 未完成时如实说"部分完成"并列出缺什么；不得挑"看起来还行"的单文件交付。
- 同一任务连续 2 次无有效产物 → 停止重试，向用户说明并建议拆解任务、补充约束或先走 `fpga-architecture`。

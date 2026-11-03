---
name: RTL生成
description: 生成或修改面向安路 EG4S20（TD 6.2.1 综合）的可综合 Verilog-2001 RTL。既可在已有架构/接口/行为契约下实现模块，也可直接处理简单明确的单模块需求（计数器、分频器、按键消抖、数码管扫描、简单 FSM）。
allowed-tools: [Read, Grep, Glob, Write, Edit]
user-invocable: true
argument-hint: "<optional: file_or_module>"
arguments: [file_or_module]
when_to_use: 需要按已确认的架构/接口/行为规格生成或修改可综合 RTL 时使用。若命中 rules/00-skill-routing.md 的"协议时序敏感模块判定标准"且契约未冻结，不应直接进入本阶段。
version: "1.0.0"
---

# RTL Build (Verilog-2001 for Anlogic TD)

## Boundaries

- 目标综合器是安路 TD 6.2.1，目标器件 EG4S20BG256（见 `rules/05-hx4s20-target.md`）。RTL 写 **Verilog-2001**，不写 SystemVerilog（`logic`、`always_ff`、`interface`、`enum`、`typedef` 等一律不用）。TB 可以用 SV，RTL 不行。
- 不改已确认的端口、参数、层次、寄存器语义、时序契约，除非请求明确要求或已记录为架构/寄存器更新。
- 不重写无关文件；一次调用只生成一个模块（一个 `rtl/<module>.v`）。
- 板级顶层 `rtl/top.v` 在本 skill 范围内：请求涉及 LED、KEY、CLOCK、数码管、UART、VGA 等板级信号且板级信号名已知时可直接生成，顶层只做例化和连线，不含业务逻辑。
- 需要 PLL / BRAM / FIFO 时不要手写原语：写一个黑盒例化，模块名和端口按 TD IP Generator 的命名（见 `references/anlogic_td_notes.md`），并在 `behavior_spec.md` 里说明"需用 TD IP Generator 生成 `rtl/al_ip/<name>.v`，参数：…"。
- 不调用编译/仿真工具；那是 `fpga-compile-and-repair` / `fpga-sim-run` 的事。

## Context Derivation

按顺序：

1. `doc/intake/summary.md` 存在 → 先读任务简报。
2. `doc/arch/interface_contract.yaml`、`doc/arch/connection_matrix.md`、`rtl/top_skeleton.v` 存在 → 端口契约、命名、时钟域、复位策略、子模块层次以它们为准，**不可跳过**。
3. `doc/hw/extracted_facts.json` 存在 → 取时钟频率、板级信号名。
4. `doc/reg/register_map.yaml`、`doc/spec/behavior_spec.md`、`doc/spec/wave_plan.yaml` 存在 → 寄存器/行为契约。
5. 直接调用且没有任何上游文件 → 请求本身就是唯一事实，**直接实现，不要拒绝**：
   - 端口至少 `clk` 与低有效 `rst_n`（HX4S20 DEMO 惯例：`CLOCK` 25 MHz、`rst_n` 按键低有效）
   - 模块名从请求推导；默认位宽 8；时间常数按 25 MHz 计算并写成 `localparam`，同时在 spec 里注明"若板载晶振不是 25 MHz 需改此值"
   - 有歧义时做一个合理选择并写进 `doc/spec/behavior_spec.md`
6. 多模块/协议类任务且顶层端口未定义 → 不生成整套系统 RTL；输出"需要先做架构"并列出待定义项。若架构产物已定义好边界，则逐模块生成。
7. 命中"协议时序敏感模块判定标准"且边沿语义/阶段顺序/端口契约未被上游产物确认 → 不猜，指出缺哪份上游产物。

## Workflow

1. 读架构、寄存器、行为规格、既有 RTL 与 `references/`。
2. 确定最小文件集。
3. 保持公开接口；若必须改接口，停下并路由到 `fpga-architecture` / `fpga-register-spec`。
4. 时序逻辑显式复位；组合逻辑完整赋值（每个 `case` 有 `default`，每个 `if` 有 `else` 或前置默认值）。
5. 对齐 valid/data/sideband 与流水延迟。
6. 事实与假设分开；假设、延迟、资源敏感选择、验证钩子、可选下一步写进 `doc/spec/behavior_spec.md`。简单 RTL 不另建 notes/handoff 文件。
7. 始终创建或更新 `doc/spec/behavior_spec.md`。
8. RTL 写到 `rtl/`，用 Write 工具直接落盘。
9. 按 `references/synthesizable_verilog_rules.md`、`references/verilog_antipatterns.md`、`references/anlogic_td_notes.md` 自检一遍。

## Output Artifacts

- `rtl/<module>.v`
- `doc/spec/behavior_spec.md`
- `rtl/top.v`（按下表判断是否生成）

### 何时生成 `rtl/top.v`

| 情况 | 决定 |
|---|---|
| 模块端口是内部总线，且 `extracted_facts.json` 有板级信号名 | 生成，用已知板级信号名连线 |
| 模块端口是内部总线，无板级信号名 | 可生成并用文档化默认值，或推迟到硬件事实就绪 |
| 请求提到 LED/KEY/CLOCK 等板级信号 | 倾向生成 |
| 架构阶段已定义 top 或 `rtl/top.v` 已存在 | 不生成/不覆盖 |
| 模块本身就是板级顶层 | 不再包一层 |
| 用户只想单独验证一个模块 | 不生成 |

`top.v` 只能有：例化、连线、板级端口（`CLOCK`、`rst_n`、`LED[]`、`KEY[]`、`SEG[]`、`UART_TX` 等）、必要的 PLL 黑盒例化。不能有 FSM、计数器、控制逻辑。

## Completion Gate

只有全部满足才算完成：

- 模块体完整，无 `TODO` / `FIXME` / `TBD` / `...` / `stub` / "omitted" / 空 `always`。
- FSM 所有状态分支闭合，无静默漏赋值。
- 例化的子模块要么在本次或既有 `rtl/` 中有实现，要么是 `al_ip/` 的 IP 黑盒并已在 spec 里写明生成参数。
- 生成了 `top.v` 时：所有端口有连接，模块名为 `top`。
- 纯 Verilog-2001；无 `initial` 给非 RAM 寄存器赋初值来代替复位（TD 会忽略或告警，见 `anlogic_td_notes.md`）。
- 端口名、参数名、位宽、有效电平与上游契约一致。
- 无 `references/verilog_antipatterns.md` 里的语义替换错误（`&vec` 当 one-hot、`a-b<=0` 当比较、隐式位宽溢出等）。
- `doc/spec/behavior_spec.md` 足以让 TB 阶段不必重读需求。

不满足任何一条：如实说"部分完成"并列出缺口；缺关键输入时说"需要补充"并点名缺的上游产物。

### AXI-Lite / 标准总线外设清单

实现 AXI-Lite、APB、Wishbone 等总线时，以下必须全部实现，不得用 `// ...` 缩写：写地址/数据/响应三阶段状态机与握手；`wstrb` 逐字节使能；读地址/读数据两阶段；每个地址偏移显式 `case` 译码；每个寄存器独立写使能；读数据 mux 有 `default`。

## Behavior Spec 结构

`doc/spec/behavior_spec.md` 包含（确实无关的可省）：

1. `# <module> Behavior Specification`
2. `## Requirement Summary`
3. `## Public Interface`（端口表：名 / 方向 / 位宽 / 有效电平 / 说明）
4. `## Parameters and Defaults`
5. `## Clocking and Reset`（含"按 25 MHz 计算，待硬件事实确认"之类的注记）
6. `## Functional Behavior`（逐周期或逐状态规则）
7. `## Timing, Latency, and Throughput`
8. `## Assumptions and Chosen Defaults`
9. `## Edge Cases and Error Handling`
10. `## Synthesis Notes`（EG4 资源预估：LUT/FF/BRAM/PLL；需要的 IP 及参数）
11. `## Verification Plan`
12. `## Acceptance Criteria`

## Skill Handoff

RTL 完成后停止。总结里列可选下一步：生成 TB、编译检查、仿真、生成约束、TD 综合。只有用户本轮明确要求才继续。

## Bundled Resources

- `references/synthesizable_verilog_rules.md`：通用可综合规则
- `references/verilog_antipatterns.md`：语义替换反模式
- `references/rtl_integration_policy.md`：集成与编辑范围策略
- `references/axi_peripheral_checklist.md`：总线外设清单
- `references/anlogic_td_notes.md`：TD 6.2 / EG4 综合注意事项与 IP 例化约定
- `templates/module.sv`、`fsm.sv`、`pipeline_stage.sv`：结构模板（写成 `.v` 时去掉 SV 语法）

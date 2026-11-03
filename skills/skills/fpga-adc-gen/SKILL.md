---
name: 约束生成（安路 ADC/SDC）
description: 根据已确认的 RTL 顶层端口和 doc/hw/extracted_facts.json 中的硬件事实，生成安路 TD 的物理约束 .adc（set_pin_assignment）与时序约束 .sdc（create_clock 等）。不编造引脚、IOSTANDARD、时钟。用于"分配管脚""生成约束""上板前约束"等请求。
allowed-tools: [Read, Grep, Glob, Edit, Write]
user-invocable: true
argument-hint: "<optional: top_module>"
arguments: [top_module]
when_to_use: RTL 顶层已有板级端口（LED/KEY/CLOCK/UART/VGA/...）且硬件事实已提取时使用。缺硬件事实先走 fpga-hw-manual-extraction；缺板级顶层先生成 rtl/top.v。
version: "1.0.0"
---

# ADC / SDC Constraint Generation (Anlogic TD, EG4S20BG256)

目标格式、属性键、器件事实见 `rules/05-hx4s20-target.md`。**不生成 XDC / QSF / CST。**

## Boundaries

- 事实来源只有 `doc/hw/extracted_facts.json`（由 `fpga-hw-manual-extraction` 产出）。原始手册/原理图/DEMO `.adc` 只在事实缺失时作为补充查阅，并把新事实回写到 `extracted_facts.json`。
- 不编造 `LOCATION`、`IOSTANDARD`、时钟频率、复位极性、Bank 电压。缺就写 `prj/constr/missing_info.md` 并停止。
- `extracted_facts.json` 为 `partial` 时：只为已确认的端口写约束，未确认的端口写成注释行 `# TODO <port>: missing LOCATION (source: none)`，并在 `pin_summary.md` 里列出。
- 端口名与 RTL 顶层**逐字一致**（大小写敏感）；总线逐 bit 展开。
- 已有 `prj/constr/*.adc`（例如用户从 DEMO 拷来的）时，保留其格式与注释，只增改必要行。

## Inputs

1. `doc/hw/extracted_facts.json`：`pin_map`、`clock_facts`、`electrical_facts`、`device_facts`
2. `rtl/top.v`（或指定的顶层）：端口名、方向、位宽
3. `doc/arch/interface_contract.yaml` / `doc/spec/behavior_spec.md`：时钟频率、PLL 输出、异步时钟组
4. `rtl/al_ip/*.v`：PLL wrapper 中的实例名与 `clkc[n]` 输出，用于 `create_generated_clock`
5. 参考模板（只读）：`HX4S20_Contest_202606/2_Example/DEMO/*/*.adc`、`*.sdc`

## Workflow

1. 读 `extracted_facts.json`，检查 `status`：`needs_input` → 写 `prj/constr/missing_info.md`，停止；`partial` → 继续但标注缺口；`complete` → 正常。
2. 读顶层 RTL，列出所有端口与位宽；确认它们是板级信号（LED/KEY/CLOCK 等）。若顶层端口都是内部总线（`data_in`、`valid`）→ 写 `prj/constr/missing_top_module.md`，建议先生成 `rtl/top.v`，停止。
3. 逐端口匹配 `pin_map`（按板级信号名，允许用户在 `interface_contract.yaml` 里给出 RTL 端口名 ↔ 板级信号名的映射）。
4. 取 `electrical_facts`：`io_standard` 显式存在才写；只有 Bank 电压时按 EG4 规则写（3.3 V Bank → `LVCMOS33`，2.5 V → `LVCMOS25`，1.8 V → `LVCMOS18`），并在行尾注释 `# derived from bank voltage`；两者都没有 → `TODO`。
5. 输入类端口（KEY、rst_n）默认 `PULLTYPE = PULLUP`（与 DEMO 一致），时钟输入 `PULLTYPE = NONE` 或按事实；输出 `DRIVESTRENGTH = 8; PULLTYPE = NONE;`；高速输出（RGMII、HDMI、SDRAM）`DRIVESTRENGTH = 16; SLEWRATE = FAST;`。这些默认值必须在 `pin_summary.md` 里逐条标注为 default。
6. 写 `prj/constr/top.adc`。
7. 写 `prj/constr/top.sdc`：
   - 每个板级时钟输入 `create_clock -name <n> -period <ns> -waveform {0 <ns/2>} [get_ports {<port>}]`，周期来自 `clock_facts`。
   - 每个 PLL 输出 `create_generated_clock ... [get_pins {<inst>/pll_inst.clkc[i]}]`，倍/分频系数来自 `rtl/al_ip/*.v` 头部注释表。
   - 互不相关的时钟 `set_clock_groups -exclusive -group ...`。
   - 使用 PLL 时加 `derive_pll_clocks -instance [get_cells {<inst>/pll_inst}]`。
   - 没有任何时钟事实时不写 `.sdc`，并在总结中说明 TD 将不做时序检查。
8. 写 `prj/constr/pin_summary.md`：表格 = RTL 端口 | 板级信号 | LOCATION | IOSTANDARD | 其它属性 | 来源（`source_ref` 或 `default`/`TODO`）。
9. 用 Grep 做自检：`.adc` 里每个 `{ port }` 都在 RTL 端口列表内；RTL 每个板级端口都在 `.adc` 里（或在 TODO 列表里）。

## Output Format

```tcl
# prj/constr/top.adc -- generated for HX4S20 / EG4S20BG256
# source of truth: doc/hw/extracted_facts.json (status: complete)
set_pin_assignment	{ CLOCK }	{ LOCATION = R7; IOSTANDARD = LVCMOS33; PULLTYPE = NONE; }
set_pin_assignment	{ rst_n }	{ LOCATION = A2; IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }
set_pin_assignment	{ LED[0] }	{ LOCATION = A4; IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 8; PULLTYPE = NONE; }
# TODO UART_TX: missing LOCATION (source: none)
```

```tcl
# prj/constr/top.sdc
create_clock -name clk_in -period 40 -waveform {0 20} [get_ports {CLOCK}]
```

## Output Artifacts

- `prj/constr/top.adc`
- `prj/constr/top.sdc`（有时钟事实时）
- `prj/constr/pin_summary.md`
- `prj/constr/missing_info.md` / `missing_top_module.md`（阻塞时）

## Completion Gate

- 每个板级端口要么有确认引脚，要么在 TODO 列表里有明确缺口与来源说明。
- 没有任何一条 `LOCATION` 或 `IOSTANDARD` 是没有 `source_ref` 或 `default` 标注的。
- `.adc` 端口名通过与 RTL 的逐字比对。
- 下一步：`fpga-td-build`（`synth_only` 先验证 `read_adc` 无端口报错）。

## Bundled Resources

- 参考：`HX4S20_Contest_202606/2_Example/DEMO/0_cnt1s/cnt1s.adc`（最小示例）、`DEMO/33_*/par_ph1demo/ph1_constraints/ph1_demo.{adc,sdc}`（PLL + 多时钟组示例）

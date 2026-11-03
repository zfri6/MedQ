---
name: TestBench生成
description: 为 rtl/ 下的模块生成自检 TestBench（tb/tb_top.v 等）、统一仿真脚本 sim/run_sim.py 与 ModelSim .do 模板。不执行编译与仿真；生成后交 fpga-compile-and-repair 检查。
allowed-tools: [Read, Grep, Glob, Write, Edit]
user-invocable: true
argument-hint: "<optional: top_module>"
arguments: [top_module]
when_to_use: 用户明确要求生成 TestBench / 验证用例时使用。
version: "1.0.0"
---

# TB Write (ModelSim + iverilog compatible)

## Boundaries

- 只生成 TB 源码与仿真脚本。编译 → `fpga-compile-and-repair`；运行 → `fpga-sim-run`。
- TB 必须在运行时打印明确的 `PASS` 或 `FAIL errors=N`，并以 `$finish` 结束；`fpga-sim-run` 的 `run_sim.py` 靠这两行判定结果。
- TB 写 `tb/`，脚本写 `sim/`，绝不写 `doc/sim/`。
- 不在这里修 RTL/TB 语法错误。
- TB 可以用 SystemVerilog 断言/`$fatal`，但要同时能被 ModelSim（`vlog`）和 iverilog（`-g2012`）编译；不用 UVM、class、`program`。
- DUT 例化了 `rtl/al_ip/*.v` IP（PLL/BRAM）时，TB 注释顶部写明 `// requires: ModelSim + <TD_HOME>/sim_release (run_sim.py --anlogic-lib)`，并考虑用 `` `ifdef SIMULATION `` 在 TB 里旁路 PLL（直接用 TB 时钟驱动），使纯逻辑部分仍能在 iverilog 上跑。

## Context Derivation

1. `doc/intake/summary.md` → 任务简报
2. `doc/arch/interface_contract.yaml` / `connection_matrix.md` → 端口契约、时钟域、复位策略
3. `doc/spec/behavior_spec.md` / `scenario_matrix.md` → 测试计划与验收标准
4. `doc/hw/extracted_facts.json` → 板级时钟频率（无则按 25 MHz 并注明待确认）
5. 直接调用 → 直接读 `rtl/*.v`；没有 RTL 则说明"需要先有 RTL"并停止

## Workflow

### Step 0 — 读 RTL（不可跳过）

用 Glob 找 `rtl/*.v`，逐行读模块声明，提取：模块名（大小写敏感）、每个端口的名/方向/位宽、每个 `parameter` 与 `localparam`。总线接口（AXI 等）另读 `references/tb_selfcheck_patterns.md`。

### Step 1 — 规划

从 RTL 与规格确定：时钟/复位、协议握手、可观测的内部状态、场景列表（复位值 / 正常流 / 边界 / 错误恢复）。大常数（如 1 秒计数 24_999_999）不要真等：用层次引用把计数器置到终值附近，或让 RTL 的时间常数是 `parameter` 并在 TB 里覆盖成小值（只对 `parameter` 有效，`localparam` 不能覆盖）。

### Step 2 — 写 `tb/tb_top.v`

- 时钟：`initial clk = 0; always #(CLK_PERIOD_NS/2) clk = ~clk;`，周期由 `CLK_FREQ_HZ` 算出
- 复位：`rst_n = 0` 保持 5 个周期后 `#1 rst_n = 1`
- 等待用 `repeat (N) @(posedge clk);`，采样在 `@(posedge clk); #1;` 之后
- 比较用 `!==`，错误累加 `error_count`，每条错误 `$display("ERROR [scene] t=%0t exp=... got=...")`
- 超时看门狗：`TIMEOUT_CYCLES` 后 `$display("TIMEOUT ...")` 并 `$finish`
- VCD：`` `ifdef DUMP_VARS $dumpfile("wave.vcd"); $dumpvars(0, tb_top); `endif ``（路径相对 `sim/`，`run_sim.py` 在 `sim/` 下运行）
- DUT 例化写在 TB 内或 `` `include "dut_inst.vh" ``；参数用 `#(.P(v))`，不用 `defparam`
- 禁止 `// ...`、`// TODO`、空场景

### Step 3 — 写 `tb/scenario_matrix.md`

每行一个具体场景：名称（如 `reset_value`、`toggle_after_T1S`，不用 `test1`）、激励、期望、对应的 behavior_spec 规则 ID。简单模块 2-3 行即可，但不能只有表头。

### Step 4 — 写仿真脚本

- `sim/run_sim.py`：从 `templates/run_sim.py` 原样复制（它是通用的，不需要按项目改）。
- `sim/modelsim/run.do`、`sim/modelsim/wave.do`：从 `templates/run.do`、`templates/wave.do` 复制，并把 `wave.do` 里的信号路径改成本 DUT 的实际层次。用到 IP 时取消 `run.do` 里 `al_ip` 与 `sim_release` 三行的注释，`<TD_HOME>` 取 `doc/hw/toolchain.json` 的 `td.td_home`。

### Step 5 — 自检后再总结

用 Glob 确认 `tb/tb_top.v`、`tb/scenario_matrix.md`、`sim/run_sim.py`、`sim/modelsim/run.do`、`sim/modelsim/wave.do` 都在磁盘上且非空；`tb_top.v` 中同时存在 `$display("PASS")` 与 `FAIL errors=`；DUT 例化端口与 Step 0 提取的列表逐一对应。任何一项不满足：补写，或在总结里如实说"部分完成"并点名缺哪个文件。

## Output Artifacts

- `tb/tb_top.v`
- `tb/dut_inst.vh`（可选）
- `tb/scenario_matrix.md`
- `sim/run_sim.py`
- `sim/modelsim/run.do`、`sim/modelsim/wave.do`

## 运行方式（写进总结供用户复制）

```powershell
python sim/run_sim.py --run              # ModelSim 优先，缺则 iverilog
python sim/run_sim.py --run --vcd        # 生成 sim/wave.vcd
python sim/run_sim.py --gui              # ModelSim 图形界面 + wave.do
python sim/run_sim.py --run --anlogic-lib   # DUT 含安路 IP
```

## Completion Gate

- 上述文件全部落盘、非空、无 stub 语言
- 端口映射与 RTL 逐字一致，参数只覆盖 `parameter`
- 每个场景有具体期望值，`scenario_matrix.md` ≥ 2 行
- 大常数场景用了行为性检查而不是硬等百万周期

## References

- `references/tb_anti_patterns.md`：端口方向、时钟写法、defparam、stub、等待方式、大常数
- `references/tb_selfcheck_patterns.md`：场景类型、scoreboard、时钟周期、PASS/FAIL 约定
- `templates/tb_top.v`、`dut_inst.vh`、`scenario_matrix.md`、`run_sim.py`、`run.do`、`wave.do`、`handoff_packet.md`

# FPGA Workspace Layout Contract

```
<project>/
├── rtl/                 可综合 Verilog-2001 源码
│   └── al_ip/           TD IP Generator 生成的 wrapper（PLL、BRAM、FIFO），只读
├── tb/                  TestBench 源码与 include
├── sim/                 仿真脚本与产物
│   ├── run_sim.py       统一仿真入口（ModelSim / iverilog）
│   ├── modelsim/        sim.do、wave.do
│   ├── work/            ModelSim 库（可删）
│   ├── compile.log  sim.log  sim_result.json  wave.vcd / wave.wlf
├── prj/
│   ├── constr/          top.adc（引脚）、top.sdc（时钟）、pin_summary.md
│   └── td/              <name>.al、build.tcl、reports/、output/<name>.bit、<name>_Runs/
└── doc/
    ├── intake/  arch/  reg/  spec/  compile/
    └── hw/              extracted_facts.json、toolchain.json、用户上传资料副本
```

总原则：
- 源码目录只用 `rtl/` 与 `tb/`；仿真产物只进 `sim/`；约束与 TD 工程只进 `prj/`；`doc/` 只放 markdown/yaml/json。
- TD 工程文件 `.al` 里的源文件路径写成相对 `prj/td/` 的相对路径（如 `../../rtl/top.v`），与 DEMO 工程写法一致，保证整个目录可以整体拷贝。

## 路径格式规则

- 本机是 Windows + PowerShell。工具脚本用 Python；不要写 bash。
- 脚本内使用相对工程根目录的相对路径；禁止硬编码 `C:\Users\...`、`D:\...`、`/c/`、`/d/`。
- 写入 TD Tcl / ModelSim `.do` 的路径用正斜杠。
- TD 工程必须落在纯 ASCII 路径下（见 `rules/30-fpga-toolchain.md`）。当前 workspace 位于中文路径 `Desktop\安路\`，因此 `fpga-td-build` 默认把 TD 工程镜像到 `C:\anlogic_work\<name>\`，源文件用绝对路径或复制过去，并把映射写入 `doc/hw/toolchain.json`。

必须遵守：
- 不要新建 `doc/sim/`、`doc/rtl/*.v`。
- TB 必须写入 `tb/`（如 `tb/tb_top.v`、`tb/dut_inst.vh`）。
- 仿真脚本与产物必须写入 `sim/`。
- 不要手改 `rtl/al_ip/*.v`。

兼容与迁移：
- 若历史项目已有 `doc/rtl/*.v`、`doc/sim/*.v` 或散落的 `.vcd`/`.vvp`：新增/改动按本规则落位；迁移旧文件前先输出迁移计划并等待用户确认。
- 从 DEMO 拷贝的工程（源文件和 `.al` 平铺在一个目录）可以保持原样作为参考，但新工程按本布局建。

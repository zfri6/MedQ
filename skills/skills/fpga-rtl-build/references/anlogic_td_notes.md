# Anlogic TD 6.2 / EG4S20 综合注意事项

来源：比赛资料 DEMO 工程（`2_Example/DEMO`）的实际写法 + TD 通用约束。凡标注"待确认"的条目，第一次在本机 TD 上跑通后应回来修正。

## 语言子集

- 只用 Verilog-2001。TD 6.2 对 SystemVerilog 支持有限，`logic` / `always_ff` / `always_comb` / `enum` / `typedef` / `interface` / `package` 一律不用。
- `always @(*)` 可用；组合块内每个输出在所有分支都要赋值，否则 TD 会推 latch 并告警。
- `localparam` / `parameter` 正常；`$clog2` 在 TD 6.2 中可用于常量表达式（待确认，保守做法是手写位宽）。
- 不用 `initial` 给寄存器赋初值来代替复位；EG4 上电初值不保证，TD 可能忽略。所有状态元件用 `rst_n` 异步或同步复位。
- 不用 `#delay`、`$display` 等仿真语句在 RTL 里（可放在 `` `ifdef SIMULATION `` 内）。
- 多维数组/存储器：`reg [7:0] mem [0:255];` 可被推断为分布式 RAM 或 BRAM；大容量存储优先用 IP Generator 生成的 BRAM（见下）。

## 时钟与复位惯例（与 DEMO 一致）

- 板级输入时钟命名 `CLOCK` 或 `clk`，25 MHz（待硬件事实确认）。
- 复位按键低有效：`rst_n`，`always @(posedge clk or negedge rst_n)`。
- 需要更高频率或多路时钟时用 PLL IP，不要用逻辑分频输出去驱动大块逻辑的时钟（TD 会把它当普通信号，时序无法约束）。分频产生的"慢节拍"应做成使能脉冲（`tick`）而不是新时钟。

## IP 例化约定

IP 由 TD 的 **IP Generator** 生成到 `rtl/al_ip/<name>.v`，RTL 中按其端口例化。常见 IP：

| IP | DEMO 中的 wrapper 名 | 内部原语 | 典型端口 |
|---|---|---|---|
| PLL | `PLL`、`pll_gen`、`sys_pll`、`vga_clk` | `EG_PHY_PLL` | `refclk`, `reset`, `extlock`, `clk0_out..clk4_out` |
| 单口/双口 RAM | `ram`、`blk_mem_gen_0` | `EG_LOGIC_BRAM` | `dia/doa/addra/cea/clka/wea` 等 |
| ROM（初始化文件） | `rom1`、`gps_char_rom`、`ROM` | `EG_LOGIC_BRAM` + `.mif`/`.dat` | `addr`, `clk`, `q` |
| 异步 FIFO | `afifo_8i_32o_1024` | BRAM + 逻辑 | `di/do/wr_clk/rd_clk/we/re/empty/full` |

RTL 生成时：

1. 先在 `rtl/` 里写业务模块，把 IP 当黑盒例化，实例名建议 `u_pll`、`u_ram` 等。
2. 在 `behavior_spec.md` 的 `## Synthesis Notes` 写清 IP 类型、参数（输入频率、各输出频率、深度、位宽、初始化文件）。
3. 用户用 TD IP Generator 生成后把 `.v` 放到 `rtl/al_ip/`，`fpga-td-build` 会把 `rtl/al_ip/*.v` 加进工程。
4. 仿真时 ModelSim 需加载 `<TD_HOME>/sim_release/al/*.v` 与 `eg/*.v`；iverilog 不支持。

PLL 的 `create_generated_clock` 引脚路径为 `<inst>/pll_inst.clkc[i]`（见 DEMO `ph1_demo.sdc`）。

## 常见 TD 告警/错误对应的 RTL 改法

| TD 现象 | 改法 |
|---|---|
| latch inferred | 组合块补 `default` / 前置默认赋值 |
| multiple drivers | 同一 reg 只在一个 `always` 里赋值 |
| clock used as data / data used as clock | 分频信号改为使能脉冲；真正的时钟走 PLL |
| port width mismatch | 例化时逐端口显式位宽，不用隐式截断 |
| unconnected output / floating input | 顶层未用输出可不接；输入必须接常量或信号 |
| ADC 端口找不到 | 检查大小写与 `LED[0]` 位选写法 |

## 资源上限（EG4S20，用于 `Synthesis Notes` 预估）

以 `6_EG4S20` 技术手册为准；本地未解压时不要写具体数字，只写"待查手册"。做资源预估时给量级（几百 LUT / 若干 BRAM / 1 个 PLL）即可。

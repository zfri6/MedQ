# FPGA Compile-Fail Conditional Routing

## 仿真编译（iverilog / ModelSim vlog）失败

当 `fpga-compile-and-repair` 内的编译检查循环 3 轮仍未通过时：

- 不要在主对话直接尝试修复 RTL/TB
- 下一步重新调用 `fpga-compile-and-repair`，把 `sim/compile.log`、`sim/sim_result.json` 里的命令与相关源文件路径作为输入
- TB 结构问题反复失败：调用 `fpga-tb-write` 重写 TB，再回到 `fpga-compile-and-repair`
- DUT 逻辑问题：调用 `fpga-rtl-build` 修复 RTL，再回到 `fpga-compile-and-repair`
- iverilog 与 ModelSim 结论不一致时，以 ModelSim 为准；iverilog 独有的报错若是它不支持的合法 Verilog-2001 写法，记录并忽略

## TD 综合 / 布局布线失败

`fpga-td-build` 报错按类型分流，不在 TD 阶段修改 RTL：

| 现象 | 去向 |
|---|---|
| `elaborate` 语法/层次错误（但 vlog 已通过） | 多为 TD 不支持的语法（SystemVerilog、`initial` 赋初值给非寄存器、`$clog2` 在旧版本、`always @*` 内 latch）。交 `fpga-rtl-build` 改写为 Verilog-2001 等价写法 |
| 综合出 latch / 组合环 警告 | `fpga-rtl-build` 补全 `if/case` 分支默认赋值 |
| `read_adc` 报端口不存在 | `fpga-adc-gen` 重新对齐 RTL 顶层端口名（大小写、位选写法 `LED[0]`） |
| IOSTANDARD 与 Bank 电压冲突 | `fpga-hw-manual-extraction` 复核原理图 Bank 电压后 `fpga-adc-gen` 重生成 |
| 资源超限（LUT/BRAM/PLL 数量） | 回到 `fpga-architecture` 调整存储/复用策略 |
| 时序不收敛（`*_pr.timing` 中 slack < 0） | 先确认 `.sdc` 时钟约束是否真实；真实则 `fpga-rtl-build` 拆流水/降扇出；不要靠删约束"修复" |
| 找不到 `EG_PHY_PLL` 等原语 | 确认 `rtl/al_ip/*.v` 已加入工程且 `import_device` 器件正确 |

TD 侧 3 轮未过同样停止自动重试，写 `doc/compile/repair_report.md` 说明。

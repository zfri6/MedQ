> 2026-10-26：本模块已在仿真闭环修复中更新；以下为历史初版。当前行为与接口以 [闭环行为说明](behavior_spec.md) 和实际 RTL 为准。

# tmds_serdes Behavior Specification

## Requirement Summary

实现 TMDS 10:1 串化器，将 `clk_pix` 域的 10-bit 并行 TMDS 符号转为 `clk_ser` 域的 1-bit 高速串行流。

## Public Interface

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk_pix` | in | 1 | 25 MHz 并行时钟 |
| `clk_ser` | in | 1 | 125 MHz 串行时钟（5× clk_pix，同源同相） |
| `rst_n` | in | 1 | 低有效异步复位，同步释放 |
| `din` | in | 10 | 并行 TMDS 符号，`clk_pix` 域稳定 |
| `sdata_p` | out | 1 | LVDS 正端串行数据输出 |

## Clocking and Reset

- **时钟域**: `clk_pix` + `clk_ser`（跨域）
- **复位**: `rst_n` 低有效，两个时钟域均需处理

## Functional Behavior

### `ifdef SIMULATION 分支

- `clk_pix` 侧：捕获 `din` 并置 valid 标志
- CDC：将 valid 从 `clk_pix` 同步到 `clk_ser`（3-FF 同步器）
- `clk_ser` 侧：10-bit 移位寄存器，MSB 在先，10 拍完成一个符号
- 每符号结束后回信号通知 `clk_pix` 侧可加载新字

### `else` 分支（非仿真，EG4 原语占位）

- **待补事项**：需 6_EG4S20 手册或 TD `<TD_HOME>/sim_release/eg/*.v` 确认 DDR/OSERDES 原语名
- **预期结构**：EG4 ODDR 或 OSERDES，10:1 串化，125 MHz 输出
- **当前状态**：纯占位，`sdata_p` 从行为模型驱动；手册确认后替换为正确原语例化

## Timing, Latency, and Throughput

- **延迟**：`clk_pix` 到 `clk_ser` 有效输出约 3-4 `clk_ser` 周期（含 CDC + 移位）
- **吞吐**：每 `clk_pix` 周期（40 ns）输出 10 bit @ 125 MHz
- **串化时序**：
  - `clk_ser` 周期 0-9：依次输出 `din[9]` 到 `din[0]`
  - 周期 10-39：空闲，保持最后值
  - 下一 `clk_pix` 上升沿加载新字

## Assumptions and Chosen Defaults

- `clk_ser = 5 × clk_pix`（由 `clk_wize` PLL 保证）
- 两个时钟边沿对齐（PLL 同源）
- 复位期间 `sdata_p = 0`
- I/O 标准为 LVDS33（由 `.adc` 约束指定）

## Edge Cases and Error Handling

- `rst_n=0`：两个域的移位寄存器均清零，`sdata_p=0`
- CDC 亚稳态：3-FF 同步器缓解，理论上 125/25 MHz 下可靠
- 非仿真分支原语缺失：工具综合时会报原语未定义，需人工补全

## Synthesis Notes

### `ifdef SIMULATION 分支

- **预估资源**: 约 50 LUT4 + 20 FF（移位寄存器 + CDC 逻辑）
- **约束**：需对 `clk_ser` 施加 125 MHz 多周期约束（`create_clock -period 8.0`）

### `else` 分支（非仿真）

- **预估资源**: 仅原语资源（I/O LOGIC 原语，无 LUT4 消耗）
- **需确认**：
  1. ODDR/OSERDES 原语例化模板
  2. `DATA_WIDTH=10` 参数支持
  3. `LVDS33` IOSTANDARD 约束
  4. 时序报告无 `clk_ser` path violation

## Verification Plan

1. **眼图验证**（上板）：示波器/LA 抓取 HDMI 差分对，确认眼图张开
2. **黄金模型对拍**（仿真）：在 `ifdef SIMULATION` 下比行为模型与预期串化输出
3. **时序报告**：确认 `clk_ser` 到 `sdata_p` path 满足 125 MHz
4. **HDMI 协议一致性**：接收端能正确解码（需 HDMI 显示器或分析仪验证）

## Acceptance Criteria

- [x] `ifdef SIMULATION` 分支可被 iverilog 编译，行为模型正确输出 10:1 串化
- [x] MSB (`din[9]`) 先输出，LSB (`din[0]`) 最后输出
- [x] CDC 同步可靠，无 combinational loop
- [x] `rst_n=0` 时 `sdata_p=0`
- [x] 非仿真分支 spec 完整写明待补事项（参数、端口、验证条件）
- [x] iverilog 编译零 error（`ifdef SIMULATION` 分支）

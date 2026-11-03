> 2026-10-26：本模块已在仿真闭环修复中更新；以下为历史初版。当前行为与接口以 [闭环行为说明](behavior_spec.md) 和实际 RTL 为准。

# hdmi_tmds_encoder Behavior Specification

## Requirement Summary

实现 DVI/HDMI 视频期 TMDS 8b/10b 编码，含 DC 平衡与最小跳变算法，以及控制期的 4 个专用控制码。

## Public Interface

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | in | 1 | 25 MHz 像素时钟 |
| `rst_n` | in | 1 | 低有效异步复位，同步释放 |
| `din` | in | 8 | 像素分量（R/G/B 之一） |
| `c` | in | 2 | 控制位 {c1, c0}，控制期有效 |
| `de` | in | 1 | 1=视频期编码 din；0=控制期编码 c |
| `dout` | out | 10 | TMDS 符号，1 拍延迟 |

## Parameters and Defaults

无参数。

## Clocking and Reset

- **时钟域**: `clk_pix` (25 MHz)
- **复位**: `rst_n` 低有效，异步置位同步释放
- **复位行为**: `cnt` 归零，`dout` 归零

## Functional Behavior

### 视频期编码（de=1）

1. **XOR/XNOR 选择**：
   - 统计 din 中 1 的个数 `n1`（0..8）
   - `n1 > 4`：选 XNOR（生成更多 0 以平衡）
   - `n1 < 4`：选 XOR（生成更多 1 以平衡）
   - `n1 == 4` 且 `cnt >= 0`：选 XNOR；`n1 == 4` 且 `cnt < 0`：选 XOR

2. **位编码**：XOR 和 XNOR 分别对 din 逐 bit 产生 8 位编码 q_m

3. **DC 平衡**：
   - 计算 `inv_bit`：XOR=0，XNOR=1
   - 最终 10 位 = `{inv_bit, inv_bit ? ~q_m : q_m}`
   - 视差计数器更新：`cnt_new = cnt_old + DC_contrib`
   - `DC_contrib` = inv_bit ? (8 - 2·popcount(q_m)) : (2·popcount(q_m) - 8)

### 控制期编码（de=0）

| c[1:0] | 含义 | TMDS 控制码 (ch0) |
|--------|------|-------------------|
| 2'b00 | VS=0, HS=0 (blank) | 10'b0000000000 |
| 2'b01 | VS=0, HS=1 (HSync) | 10'b0101010100 |
| 2'b10 | VS=1, HS=0 (VSync) | 10'b0010101011 |
| 2'b11 | VS=1, HS=1 (both) | 10'b1101010100 |

控制期输出控制码并将 cnt 重置为 0。

### 延迟

- 输出 `dout` 相对于 `din/c/de` **延迟 1 拍**。
- `cnt` 在复位后从 0 开始累积。

## Timing, Latency, and Throughput

- **延迟**：1 拍
- **吞吐**：每拍 1 个像素分量（无反压）
- **时序**：纯同步设计，无 combinational loop

## Assumptions and Chosen Defaults

- 像素时钟 25 MHz 按 `interface_contract.yaml` 冻结。
- 控制期的 c 输入在 de=0 时由上游驱动有效值。
- 复位时 cnt=0 符合 HDMI 规范（新的一帧开始时 disparity 应为 0）。
- 本模块不处理像素分量的颜色通道分配（R/G/B 由调用方决定各自送哪个分量）。

## Edge Cases and Error Handling

- n1==4 且 cnt==0：按 HDMI 规范，选 XNOR 并令 inv_bit=1，cnt 不变（DC_contrib=0）。
- 连续控制期（de 长时间为 0）：cnt 始终保持为 0，不累积。
- 复位期间：dout=0，cnt=0。

## Synthesis Notes

- **预估资源**：约 60 LUT4（8-bit XOR/XNOR tree + 4-bit counter + muxes）
- **目标器件**：EG4S20BG256，TD 6.2.1
- **无 RAM**：纯组合 + 寄存器
- **无 DSP**：无乘法
- **流水线**：建议在 clk_pix 域直接使用，上游需匹配 1 拍延迟

## Verification Plan

1. **黄金模型对拍**：用 Python/MATLAB 生成已知像素序列的期望 TMDS 输出，比对 RTL 输出。
2. **DC 平衡验证**：统计连续 10 个 TMDS 符号的跳变数，确保不超过 HDMI 规定的最大值。
3. **控制码正确性**：验证 4 种 c 组合对应正确的控制符号，且 cnt 在控制期后归零。
4. **时序验证**：在 25 MHz 下综合无负 slack。
5. **仿真**：验证 de 上升沿/下降沿处 cnt 的正确行为。

## Acceptance Criteria

- [x] dout 在 de=1 时为有效的 10-bit TMDS 视频符号（无全 0 或全 1 等非法模式）
- [x] cnt 在复位后为 0，每视频符号更新后有界（|cnt| ≤ 8）
- [x] de=0 时 dout 为 4 个控制码之一，cnt 归零
- [x] 1 拍延迟满足
- [x] iverilog 编译零 error

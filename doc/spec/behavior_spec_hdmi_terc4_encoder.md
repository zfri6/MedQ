> 2026-10-26：本模块已在仿真闭环修复中更新；以下为历史初版。当前行为与接口以 [闭环行为说明](behavior_spec.md) 和实际 RTL 为准。

# hdmi_terc4_encoder Behavior Specification

## Requirement Summary

实现 HDMI 数据岛期的 TERC4 4b/10b 查表编码器，将 4 位数据映射为 10 位 TMDS 数据岛符号，纯组合逻辑，零延迟。

## Public Interface

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `din` | in | 4 | 数据岛 4bit 输入 |
| `dout` | out | 10 | TERC4 编码符号，0 延迟 |

## Clocking and Reset

无时钟，无复位。纯组合逻辑。

## Functional Behavior

TERC4 编码表（HDMI 1.4b Table 5-5）：

| din | dout (hex) |
|-----|------------|
| 0x0 | 0x29C |
| 0x1 | 0x0A7 |
| 0x2 | 0x1EB |
| 0x3 | 0x19F |
| 0x4 | 0x1CE |
| 0x5 | 0x1C7 |
| 0x6 | 0x19C |
| 0x7 | 0x0F8 |
| 0x8 | 0x19A |
| 0x9 | 0x199 |
| 0xA | 0x14D |
| 0xB | 0x1B3 |
| 0xC | 0x16C |
| 0xD | 0x1F9 |
| 0xE | 0x166 |
| 0xF | 0x147 |

TERC4 特性：
- 每个输出恰好含 5 个 1 和 5 个 0（DC 平衡）
- 最多 5 次电平跳变
- 包含两个保护带（GB）符号用于数据岛边界

## Timing, Latency, and Throughput

- **延迟**：0 拍（纯组合）
- **吞吐**：输入变化立即反映在输出上

## Assumptions and Chosen Defaults

- 本模块不检查 din 的有效性（0x0-0xF 范围外按 default 处理为 0x0）
- 上游驱动保证 din 在数据岛期有效，在视频期不关心

## Synthesis Notes

- **预估资源**：约 40 LUT4（10 个 16:1 MUX 树）
- **目标器件**：EG4S20BG256，TD 6.2.1
- **无寄存器**：纯组合，工具自动合并到 LUT 中

## Verification Plan

1. 验证 16 个输入值对应正确输出（对比 HDMI 规范表）
2. 验证每个输出恰好含 5 个 1（popcount == 5）
3. 在 `hdmi_tx_core` 的数据岛测试中端到端验证

## Acceptance Criteria

- [x] dout 对每个 din[3:0] 有唯一确定值
- [x] 所有 16 个输出符号 popcount(dout) == 5
- [x] 零延迟，上游可无拍差使用
- [x] iverilog 编译零 error

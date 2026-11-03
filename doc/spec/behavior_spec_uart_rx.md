> 2026-10-26：本模块已在仿真闭环修复中更新；以下为历史初版。当前行为与接口以 [闭环行为说明](behavior_spec.md) 和实际 RTL 为准。

# uart_rx Behavior Specification

## Requirement Summary

115200 8N1 UART 接收器，用于接收调试命令。50 MHz 时钟下以过采样方式在每个比特中点采样，保证稳定性。

## Public Interface

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | in | 1 | 50 MHz 系统时钟 |
| `rst_n` | in | 1 | 异步复位，低有效 |
| `rxd` | in | 1 | 串行数据输入 |
| `out_valid` | out | 1 | 接收完成脉冲，一拍 |
| `out_data[7:0]` | out | 8 | 接收字节 |
| `frame_err` | out | 1 | 帧错误（停止位错误） |

## Parameters and Defaults

| Parameter | Default | Description |
|-----------|---------|-------------|
| `CLK_HZ` | 50000000 | 系统时钟频率 |
| `BAUD` | 115200 | 波特率 |

- 按 50 MHz / 115200 计算：`BITS_PER_BAUD = 434`，`BITS_PER_BAUD_2 = 217`。

## Clocking and Reset

- **Clock**: `clk_sys` = 50 MHz
- **Reset**: `rst_n` 低有效，复位时回到空闲态，清零计数器。

## Functional Behavior

### 时序

1. **空闲**：等待 `rxd` 拉低（起始位）。
2. **起始位**：等待 1 比特时间（434 周期），确认 `rxd` 仍为低。若变高则判定为假起始位，回到空闲。
3. **数据位**：在每个比特的**中点**（第 217 拍）采样，连续接收 8 bit，LSB 先收。
4. **停止位**：等待 1 比特时间，采样 `rxd` 必须为高，否则 `frame_err=1`。
5. **完成**：输出 `out_valid=1` 脉冲一周期，`out_data` 有效，`frame_err` 记录结果。

### 关键设计决策

- **双触发同步器**：外部 `rxd` 经两级触发器同步后再使用，避免亚稳态。
- **比特中点采样**：比特的中心位置采样数据，而非边沿采样，最大化 setup/hold 余量。
- **停止位检测**：`frame_err` 只反映停止位是否正确，不代表数据校验。

### 接收时序图（关键拍）

```
rxd:   | 0 | D0 | D1 | D2 | D3 | D4 | D5 | D6 | D7 | 1 |
bit_cnt:        0   1   2   3   4   5   6   7
out_valid:            1 (当 bit_cnt==7 且 stop bit 结束)
```

## Timing, Latency, and Throughput

- 接收一帧（10 bit）需要：1(起始) + 8(数据) + 1(停止) = 10 bit × 434 = 4340 周期 ≈ 86.8 μs
- 吞吐率：最高 ~11520 字节/秒
- `out_valid` 宽度：1 时钟周期

## Assumptions and Chosen Defaults

1. 上游 `rxd` 信号已做去耦/上拉，空闲时为 1。
2. `frame_err` 置位后下一帧自动清零（因为 frame_err 只与上一帧绑定）。
3. 参数 `BAUD` 必须是 `CLK_HZ` 的整除数（115200 整除 50000000 = 434.027，误差 < 0.03%，在 UART 容差内）。

## Edge Cases and Error Handling

- 假起始位：收到低电平后确认阶段拉高 → 回到空闲，不产生 `out_valid`。
- 停止位错误：停止位为 0 → `frame_err=1`，`out_valid` 仍输出。
- 连续帧：前一帧 `out_valid` 出现后可立即接收下一帧，无空闲要求。
- 复位期间忽略输入。

## Synthesis Notes

- 估算 LUT：约 30（计数器 + 移位寄存器 + FSM）
- 估算 FF：约 25
- 无 BRAM，无乘法器
- 双触发同步器对跨时钟域输入是必要的安全措施

## Verification Plan

1. **空闲检测**：`rxd=1` 长期保持时 state=IDLE。
2. **起始位确认**：收到低后等待 1 bit 确认。
3. **数据正确性**：发送 0x55，检查 shift_reg 顺序正确（LSB 先收）。
4. **停止位错误**：`rxd` 最后一 bit 拉低时 `frame_err=1`。
5. **连续帧**：两帧间隔 0 bit 也能正确解析。
6. **过采样中心点**：验证采样发生在 timer == BITS_PER_BAUD_2。

## Acceptance Criteria

- [ ] 发送 0x55 正确接收，`out_data=8'h55`
- [ ] `frame_err` 在停止位错误时置 1
- [ ] 连续帧无漏收
- [ ] 复位期间不产生误动作
- [ ] iverilog 编译零 error

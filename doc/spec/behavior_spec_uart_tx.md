> 2026-10-26：本模块已在仿真闭环修复中更新；以下为历史初版。当前行为与接口以 [闭环行为说明](behavior_spec.md) 和实际 RTL 为准。

# uart_tx Behavior Specification

## Requirement Summary

115200 8N1 UART 发送器，接收 8 位并行数据，通过 `in_valid` / `in_ready` 同步握手发送串行数据帧。

## Public Interface

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | in | 1 | 50 MHz 系统时钟 |
| `rst_n` | in | 1 | 异步复位，低有效 |
| `in_valid` | in | 1 | 发送请求脉冲 |
| `in_ready` | out | 1 | 发送器就绪（空闲时可接收） |
| `in_data[7:0]` | in | 8 | 要发送的字节 |
| `txd` | out | 1 | 串行数据输出 |

## Parameters and Defaults

| Parameter | Default | Description |
|-----------|---------|-------------|
| `CLK_HZ` | 50000000 | 系统时钟频率 |
| `BAUD` | 115200 | 波特率 |

- 按 50 MHz / 115200 计算：`BITS_PER_BAUD = 434`。

## Clocking and Reset

- **Clock**: `clk_sys` = 50 MHz
- **Reset**: `rst_n` 低有效，复位时 `txd=1`（空闲电平），状态机回空闲。

## Functional Behavior

### 握手协议

- `in_ready = 1`：发送器空闲，可接收新数据。
- 当 `in_valid=1` 且 `in_ready=1` 时，锁存 `in_data` 并开始发送。
- 发送期间 `in_ready=0`，直到一帧发送完毕才回到高。
- 发送完成后 `in_ready` 拉高一拍（ST_DONE），之后可立即接收下一帧。

### 帧格式（8N1）

```
空闲: txd = 1
START: txd = 0  (1 bit)
D0-D7: LSB first  (8 bits)
STOP:  txd = 1  (1 bit)
```

### 发送时序

- 起始位：1 bit 时间（434 周期）
- 数据位：8 × 434 = 3472 周期
- 停止位：1 bit 时间（434 周期）
- 总计：10 × 434 = 4340 周期 ≈ 86.8 μs

### 关键设计决策

- **组合逻辑输出 `txd`**：txd 直接由组合逻辑驱动（组合路径为 1 个 LUT），保证最小延迟。
- **状态机驱动 `in_ready`**：只在 ST_DONE 拍拉高，保证发送窗口内不被抢占。
- **`in_valid` 锁存**：`in_valid` 在 ST_IDLE 且 `in_valid=1` 时锁存数据，即使 `in_valid` 只持续一拍也能正确采样。

## Timing, Latency, and Throughput

- 发送一帧：4340 周期（86.8 μs）
- 最大吞吐率：~11520 字节/秒
- `in_ready` 低脉冲宽度：4340 - 434 = 3906 周期（发送中）

## Assumptions and Chosen Defaults

1. 上游保证 `in_valid` 只在 `in_ready=1` 时拉高（单次握手），不重发。
2. `in_data` 在 `in_valid` 拍有效并被锁存。

## Edge Cases and Error Handling

- `in_valid=1` 但 `in_ready=0`（正在发送）→ 数据被丢弃，因为没有锁存。协议要求上游等待 `in_ready`。
- 复位期间 `txd=1`（空闲），`in_ready=0`。

## Synthesis Notes

- 估算 LUT：约 25（FSM + 移位）
- 估算 FF：约 20
- 无 BRAM，无乘法器

## Verification Plan

1. **空闲就绪**：`in_ready=1` 且 `txd=1`。
2. **发送正确帧**：写入 0xAA，验证串行波形（LSB 先）。
3. **in_ready 时序**：`in_ready` 在发送期间为 0，完成后拉高一拍。
4. **连续发送**：连续写入两个字节，验证中间无空闲。
5. **复位**：复位期间 `txd=1`。

## Acceptance Criteria

- [ ] `in_ready` 在发送期间为 0
- [ ] 写入 0x55，txd 产生正确的 10-bit 串行帧
- [ ] 连续发送不丢帧
- [ ] 复位后 `txd=1`
- [ ] iverilog 编译零 error

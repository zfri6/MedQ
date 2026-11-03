> 2026-10-26：本模块已在仿真闭环修复中更新；以下为历史初版。当前行为与接口以 [闭环行为说明](behavior_spec.md) 和实际 RTL 为准。

# uart_cmd Behavior Specification

## Requirement Summary

UART 调试命令解析器。接收字节流，验证帧头与 CRC8，解析 CMD 0x01-0x06 并输出对应脉冲或参数写事务。成功/失败通过 UART 回 0x06/0x15。

## Public Interface

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | in | 1 | 50 MHz 系统时钟 |
| `rst_n` | in | 1 | 异步复位，低有效 |
| `rx_valid` | in | 1 | 接收字节有效 |
| `rx_data[7:0]` | in | 8 | 接收字节 |
| `tx_valid` | out | 1 | 发送有效 |
| `tx_ready` | in | 1 | 发送就绪 |
| `tx_data[7:0]` | out | 8 | 发送字节 |
| `cmd_next` | out | 1 | 叫下一号脉冲 |
| `cmd_recall` | out | 1 | 重呼脉冲 |
| `cmd_skip` | out | 1 | 过号脉冲 |
| `cmd_arrive` | out | 1 | 取号脉冲 |
| `cmd_page` | out | 1 | 切页脉冲 |
| `cmd_param_we` | out | 1 | 参数写使能 |
| `cmd_param_sel[3:0]` | out | 4 | 参数选择 |
| `cmd_param_val[7:0]` | out | 8 | 参数值 |

## Parameters and Defaults

无参数。

## Clocking and Reset

- **Clock**: `clk_sys` = 50 MHz
- **Reset**: `rst_n` 低有效，复位时回空闲态。

## Functional Behavior

### 帧格式

```
Byte[0]: 0x55  (SOF1)
Byte[1]: 0xAA  (SOF2)
Byte[2]: CMD   (0x01-0x06)
Byte[3]: ROOM  (诊室号 1-4，或参数选择索引)
Byte[4]: TICKET_H (票号 BCD 高字节)
Byte[5]: TICKET_L (票号 BCD 低字节)
Byte[6]: PARAM  (参数值)
Byte[7]: CRC8  (CMD..PARAM 异或校验)
```

### CRC8 规范

- 多项式：`0x07`（x^8 + x^2 + x + 1）
- 初值：`0x00`
- 覆盖范围：`CMD` → `ROOM` → `TICKET_H` → `TICKET_L` → `PARAM`（共 5 字节）
- 算法：字节式 LFSR，LSB 先入

### CMD 指令

| CMD | 名称 | 输出 | 说明 |
|-----|------|------|------|
| 0x01 | 叫下一号 | `cmd_next=1` | 触发叫号 |
| 0x02 | 重呼 | `cmd_recall=1` | 重呼当前票 |
| 0x03 | 过号 | `cmd_skip=1` | 当前票作废 |
| 0x04 | 取号 | `cmd_arrive=1` | 新患者入队 |
| 0x05 | 设置参数 | `cmd_param_we=1` | 写 param_bus |
| 0x06 | 切页 | `cmd_page=1` | 切换 OSD 页面 |

### 响应

- 校验通过且 CMD 有效 → 发送 `0x06`（ACK）
- CRC 错误或 CMD 无效 → 发送 `0x15`（NAK），不执行命令

### 状态机

```
IDLE → SOF1(0x55) → SOF2(0xAA) → CMD → ROOM → TICKET_H → TICKET_L → PARAM → CRC → EXEC → SEND_ACK → IDLE
```

## Timing, Latency, and Throughput

- 帧长：8 字节
- 接收时间：8 × 86.8 μs ≈ 694 μs
- 命令执行：CRC 校验后一拍（ST_EXEC），命令脉冲持续 1 周期
- 响应发送：1 帧（8.5 bit 含停止位 ≈ 740 μs）

## Assumptions and Chosen Defaults

1. UART 参数固定 115200 8N1。
2. CRC8 函数为字节式 LFSR，实现与 Python/Java 标准 CRC-8/MPEG-2 一致。
3. 命令脉冲宽度为 1 时钟周期，上游（queue_fsm）通过边沿检测捕获。
4. 参数写（CMD 0x05）：`cmd_param_sel` 取自 ROOM 字段的低 4 位，`cmd_param_val` 取 PARAM 字段。

## Edge Cases and Error Handling

- 帧头错误：0x55/0xAA 不匹配 → 状态机回到 IDLE，不产生响应。
- CRC 错误：产生 NAK（0x15），不执行命令。
- CMD 越界：不在 0x01-0x06 → NAK。
- 响应发送期间收到新帧：忽略，因为状态机已在等待 ACK 发送完毕。
- `tx_ready=0`（UART 发送忙）：`tx_valid` 保持高，直到 `tx_ready` 拉高才清除。

## Synthesis Notes

- 估算 LUT：约 60（CRC 组合逻辑 + FSM + 字节缓冲）
- 估算 FF：约 30
- CRC8 用组合逻辑实现，延迟约 8×8=64 个 XOR，路径长但频率低（50 MHz），无问题
- 无 BRAM，无乘法器

## Verification Plan

1. **完整帧接收**：发送 0x55 0xAA 0x01 ... CRC，正确执行 `cmd_next`。
2. **CRC 错误检测**：故意写错 CRC，验证 NAK 0x15。
3. **帧头错误**：0x55 后不是 0xAA，回到 IDLE。
4. **CMD 边界**：0x00 和 0x07 应产生 NAK。
5. **参数写**：`cmd_param_sel` / `cmd_param_val` 正确映射。
6. **tx_ready=0 时阻塞**：ACK 发送期间不处理新帧。

## Acceptance Criteria

- [ ] 完整帧（0x55 0xAA CMD ROOM TICKET_H TICKET_L PARAM CRC）执行正确命令
- [ ] CRC 错误时回 0x15，不执行
- [ ] CMD 无效时回 0x15
- [ ] 命令脉冲宽度为 1 时钟周期
- [ ] 参数写：sel 和 val 字段正确映射
- [ ] iverilog 编译零 error

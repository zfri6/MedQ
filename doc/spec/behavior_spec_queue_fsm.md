> 2026-10-26：本模块已在仿真闭环修复中更新；以下为历史初版。当前行为与接口以 [闭环行为说明](behavior_spec.md) 和实际 RTL 为准。

# queue_fsm Behavior Specification

## Requirement Summary

叫号队列状态机，驱动整个 MedQ 的叫号逻辑。管理 4 个诊室、两条票号队列（普通/优先），支持叫号、重呼、过号、取号、自动叫号、Flash 持久化恢复。

## Public Interface

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | in | 1 | 50 MHz 系统时钟 |
| `rst_n` | in | 1 | 异步复位，低有效 |
| `ev_next` | in | 1 | 叫下一号（脉冲） |
| `ev_recall` | in | 1 | 重呼（脉冲） |
| `ev_skip` | in | 1 | 过号（脉冲） |
| `ev_page` | in | 1 | 切页（脉冲） |
| `ev_arrive` | in | 1 | 新患者取号（脉冲） |
| `sw_priority` | in | 1 | 取号时标记优先号 |
| `sw_auto` | in | 1 | 自动叫号模式开关 |
| `sw_access` | in | 1 | 适老化大字高对比模式 |
| `restore_req` | in | 1 | 从 Flash 恢复队列 |
| `restore_data[127:0]` | in | 128 | Flash 读取的持久化状态 |
| `persist_data[127:0]` | out | 128 | 要写入 Flash 的状态 |
| `persist_req` | out | 1 | 状态变化，请求持久化 |
| `qstate[127:0]` | out | 128 | 队列状态快照，见 qstate_bus |
| `call_pulse` | out | 1 | 叫号触发脉冲 |
| `call_ticket[15:0]` | out | 16 | 本次叫号票号 BCD |
| `call_room[3:0]` | out | 4 | 分配的诊室号 1..4 |
| `call_prio` | out | 1 | 本次叫号是否为优先号 |

## Parameters and Defaults

| Parameter | Default | Description |
|-----------|---------|-------------|
| `ROOMS` | 4 | 诊室数量 |
| `PRIO_BURST` | 2 | 连续优先叫号上限，达到后必须叫一个普通号 |
| `AUTO_PERIOD` | 250000000 | 自动叫号周期，5s @ 50MHz |

## Clocking and Reset

- **Clock**: `clk_sys` = 50 MHz
- **Reset**: `rst_n` 异步置位，同步释放。复位时清空所有队列，票号归零。
- 按 50 MHz 时钟计算，定时参数以此为准。

## Functional Behavior

### 队列模型

- 两个循环队列（普通/优先），各 128-entry，存储 16-bit BCD 票号。
- 队首叫号，队尾入队。`norm_wait` / `prio_wait` 记录等待人数。
- 普通票前缀 `'A'` = 0x41，优先票前缀 `'P'` = 0x50。

### 调度策略

1. 优先队列非空且 `prio_streak < PRIO_BURST` → 叫优先号。
2. 普通队列非空且（优先空或 `prio_streak >= PRIO_BURST`）→ 叫普通号。
3. `PRIO_BURST` 达到后强制服务一个普通号，防止普通队列饿死。

### 事件处理

- `ev_arrive`：入队。根据 `sw_priority` 写入普通或优先队列，分配下一票号。
- `ev_next`：叫下一号（手动或自动触发）。分配空闲诊室，输出叫号脉冲。
- `ev_recall`：重呼当前票，不推进队列，`repeat_cnt++`。
- `ev_skip`：当前票作废，推进队列，不分配新票。
- `ev_page`：切换显示页面（`qstate.page_id`）。

### 诊室分配

轮询分配，从诊室1开始，找第一个空诊室。无空诊室时 `cur_room = 0`（叫号屏不分配）。

### 自动模式

`sw_auto = 1` 时，`auto_timer` 每 5s 自动触发一次 `ev_next`，同时模拟一个随机患者到达（`ev_arrive` 在本模块外部驱动，或本模块内部简单递增普通队列）。

### Flash 持久化

- 每次入队/过号/叫号后 `persist_req = 1`，`persist_data` 打包队列指针、下一票号、当前叫号、开关状态。
- 上电时 `restore_req` 脉冲触发恢复：队列指针、下一票号、当前叫号、开关状态从 Flash 数据恢复。
- 注意：队列内容（已分配但未叫号的票）不持久化，上电后从下一票号继续。

### BCD 递增

BCD 逢 9 进位，9999 后归零。实现为逐位进位逻辑（`bcd_inc` 函数）。

## Timing, Latency, and Throughput

- 单周期状态更新，所有事件在单周期内处理完成。
- `call_pulse` 宽度为 1 时钟周期，伴随数据 `call_ticket/call_room/call_prio` 在同一拍有效。
- 自动定时器精度为 1 时钟周期，超时精度无特殊要求。

## Assumptions and Chosen Defaults

1. 事件输入为单周期脉冲，外部门控去抖产生。
2. Flash 控制器（`spi_flash_store`）负责管理擦写时序，`persist_req` 只表示"数据已准备好"。
3. 诊室忙闲状态（`room_busy`）无硬件输入，qstate 中填 0。
4. 若 4 个诊室全满，新叫号 `cur_room = 0`，画面仍显示票号但无诊室分配。

## Edge Cases and Error Handling

- 队列空时 `ev_next` 无效，跳过。
- 无人叫号时 `ev_recall` 无效。
- 优先队列和普通队列都空时拒绝叫号。
- BCD 递增在 9999 时归零，不上溢。

## Synthesis Notes

- 队列使用分布式 BRAM（`reg [15:0] queue [0:127]`），占用 128 × 16 = 2 Kbit 存储。
- 估算 LUT：~400（FSM + BCD + 调度），FF：~200。
- 无乘法器，无 BRAM 原语，时序路径与 50 MHz 轻松满足。

## Verification Plan

1. **空队列叫号**：验证 ev_next 在空队列时无响应。
2. **优先插入**：验证优先号在普通号之前被叫。
3. **PRIO_BURST 公平性**：连续叫 2 个优先号后，下一个必须是普通号。
4. **重呼不推进**：重呼后队列长度不变，`repeat_cnt` 递增。
5. **过号推进**：过号后队列头推进，`repeat_cnt` 清零。
6. **Flash 循环**：写入后恢复，队列指针与下一票号一致。
7. **自动模式定时**：`AUTO_PERIOD` 计数满后自动触发。
8. **BCD 边界**：0001→0002，0099→0100，9999→0000。

## Acceptance Criteria

- [ ] 空队列时叫号不产生 `call_pulse`
- [ ] 优先号先于普通号被叫
- [ ] `PRIO_BURST=2` 后强制叫普通号
- [ ] 重呼后 `repeat_cnt` 递增，队列不变
- [ ] 过号后队列推进，新票号进入
- [ ] `persist_req` 在每次状态变化后置高
- [ ] `restore_req` 脉冲后队列恢复到正确状态
- [ ] BCD 递增正确处理进位
- [ ] iverilog 编译零 error

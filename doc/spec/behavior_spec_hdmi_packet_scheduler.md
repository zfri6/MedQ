> 2026-10-26：本模块已在仿真闭环修复中更新；以下为历史初版。当前行为与接口以 [闭环行为说明](behavior_spec.md) 和实际 RTL 为准。

# hdmi_packet_scheduler Behavior Specification

## Requirement Summary

实现 HDMI 数据岛包的轮转调度器。接收音频采样和配置信息，组装并轮转发送 ACR（0x01）、Audio Sample（0x02）、AVI InfoFrame（0x82）、Audio InfoFrame（0x84）四种包，每包 36 字节（header 3B + 4×subpacket 各 7B）。

## Public Interface

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | in | 1 | 25 MHz 像素时钟 |
| `rst_n` | in | 1 | 低有效异步复位，同步释放 |
| `aud_stb` | in | 1 | 48 kHz 采样选通 |
| `aud_l` | in | 16 | 左声道有符号音频采样 |
| `aud_r` | in | 16 | 右声道有符号音频采样 |
| `pkt_req` | in | 1 | 数据岛控制器请求下一包 |
| `pkt_ack` | out | 1 | 包已就绪，上游应锁存 |
| `pkt_header` | out | 24 | HB0/1/2（类型/版本/长度） |
| `pkt_sub0` | out | 56 | 子包 0（56 bits，含 BCH 校验） |
| `pkt_sub1` | out | 56 | 子包 1 |
| `pkt_sub2` | out | 56 | 子包 2 |
| `pkt_sub3` | out | 56 | 子包 3 |
| `aud_overflow` | out | 1 | 音频 FIFO 溢出（诊断用） |
| `aud_underflow` | out | 1 | 音频 FIFO 欠载（诊断用） |

## Parameters and Defaults

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `ACR_N` | 6144 | 48 kHz 标准 N 值 |
| `ACR_CTS` | 25000 | 25.000 MHz TMDS 下的 CTS |

计算验证：fs = 25e6 × 6144 / (128 × 25000) = 48000 Hz（精确整数）。

## Clocking and Reset

- **时钟域**: `clk_pix` (25 MHz)
- **复位**: `rst_n` 低有效；复位后 FIFO 空、rotation_cnt=0、状态机归 IDLE

## Functional Behavior

### 包类型与轮转顺序

| rotation | 类型 | HB0 | 内容 |
|----------|------|-----|------|
| 0 | ACR | 0x01 | Audio Clock Regeneration |
| 1 | Audio Sample | 0x02 | 音频采样数据（消费 FIFO） |
| 2 | AVI InfoFrame | 0x82 | 视频格式信息（静态） |
| 3 | Audio InfoFrame | 0x84 | 音频格式信息（静态） |
| 4 | ACR | ... | 重复 |

### ACR 包（TYPE=0x01）

- Subpacket 0: {ECC, 1'b0, CTS[19:0], 1'b1, N[19:0], 12'h000}
- Subpacket 1-3: 0

### Audio Sample 包（TYPE=0x02）

- Subpacket 0: {ECC, Left[15:0], Right[15:0], IEC60958 Channel Status[23:0]}
- Channel Status: fs=48kHz, 16-bit, 2ch, original, no copyright
- Subpacket 1-3: 0
- 消费一个 FIFO 条目

### AVI InfoFrame（TYPE=0x82）

- Subpacket 0: {HB0=0x82, HB1=0x02, HB2=0x0D, VIC=1 (640x480), RGB, no pixel repetition}
- Subpacket 1-3: 静态 0

### Audio InfoFrame（TYPE=0x84）

- Subpacket 0: {ECC, CC=2ch, SF=48kHz, SS=16-bit, CT=refer stream}
- Subpacket 1-3: 静态 0

### BCH(64,56) 编码

- 每个 subpacket 的首字节是 BCH(64,56) 校验字节（ECC）
- BCH 覆盖该 subpacket 的后 56 bits 数据（header[7:0] + subpacket[55:0] 的低 56 bits）
- 计算流程：clear -> 56 拍 MSB-first 移入 -> ecc_out 有效

### 状态机时序

```
pkt_req -> PKT_IDLE -> PKT_WAIT_BCH (56 cycles) -> PKT_READY (pkt_ack=1)
                                                             |
                                  pkt_req -> IDLE (rotation advances)
```

### 音频 FIFO

- 深度 4 entries
- `aud_stb` 时入队；Audio Sample 包确认后出队
- `aud_overflow`: aud_stb 到来时 FIFO 已满（1 拍脉冲）
- `aud_underflow`: Audio Sample 包请求时 FIFO 空（1 拍脉冲）

## Timing, Latency, and Throughput

- **延迟**: 从 `pkt_req` 上升沿到 `pkt_ack=1` 至少 57 拍（1 clear + 56 BCH）
- **吞吐**: 每包 `pkt_ack` 持续 1 拍，下一个 `pkt_req` 触发新包

## Assumptions and Chosen Defaults

- `aud_stb` 与 `pkt_req` 不会在同一拍同时操作 FIFO（由 `hdmi_tx_core` 保证）
- AVI InfoFrame 和 Audio InfoFrame 内容为 640x480@60 固定参数，不需要运行时更新
- BCH 编码在包发送前 56 拍提前完成，不阻塞包轮转
- rotation_cnt 在收到 pkt_req 后才推进，不会在 BCH 计算期间跳帧

## Edge Cases and Error Handling

- FIFO 满时的 `aud_stb` 不丢弃旧数据，而是产生 `aud_overflow` 诊断脉冲
- FIFO 空时请求 Audio Sample 包产生 `aud_underflow` 并发送全零采样
- `pkt_req` 在 PKT_READY 期间重复：立即推进 rotation 并重新计算 BCH

## Synthesis Notes

- **预估资源**: 约 200 LUT4（4-entry FIFO + BCH 状态机 + 包组装逻辑）
- **目标器件**: EG4S20BG256，TD 6.2.1
- **无 BRAM**: FIFO 用分布式寄存器实现（4 entries × 16bit × 2ch = 128 bit）

## Verification Plan

1. **BCH 正确性**: 用已知向量验证 ACR 包 BCH 与标准一致
2. **ACR 音频频率**: 验证 N/CTS 参数代入公式得到精确 48000 Hz
3. **FIFO 行为**: 注入连续的 aud_stb 脉冲，验证 overflow 触发时机
4. **包轮转**: 连续发 8 个 pkt_req，验证类型顺序符合 0→1→2→3→0→...
5. **欠载测试**: 清空 FIFO 后强制请求 Audio Sample，验证 underflow 并发送全零

## Acceptance Criteria

- [x] ACR 包 N=6144, CTS=25000，代入公式 fs=48000 Hz 精确
- [x] 轮转顺序 ACR→ASMP→AVI→AINFO→ACR 正确
- [x] 每个 subpacket 的首字节为正确的 BCH(64,56) 校验
- [x] `aud_overflow` 在 FIFO 满时产生脉冲
- [x] `aud_underflow` 在 Audio Sample 包请求但 FIFO 空时产生脉冲
- [x] 从 `pkt_req` 到 `pkt_ack` 至少等待 57 拍
- [x] iverilog 编译零 error

> 2026-10-26：本模块已在仿真闭环修复中更新；以下为历史初版。当前行为与接口以 [闭环行为说明](behavior_spec.md) 和实际 RTL 为准。

# hdmi_tx_core Behavior Specification

## Requirement Summary

实现 HDMI 1.4b 发送器核心，按规范编排控制期 / 前导码 / 保护带 / 数据岛 / 视频期，输出 3 路 10-bit TMDS 并行符号。

## Public Interface

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | in | 1 | 25 MHz 像素时钟 |
| `rst_n` | in | 1 | 低有效异步复位，同步释放 |
| `vid_de` | in | 1 | 1=活动视频期 |
| `vid_hs` | in | 1 | 行同步，负极性 |
| `vid_vs` | in | 1 | 场同步，负极性 |
| `vid_rgb` | in | 24 | {R[7:0], G[7:0], B[7:0]} |
| `aud_stb` | in | 1 | 48 kHz 采样选通 |
| `aud_l` | in | 16 | 左声道有符号采样 |
| `aud_r` | in | 16 | 右声道有符号采样 |
| `tmds_ch0` | out | 10 | 蓝通道 TMDS 符号（含控制/视频/TERC4） |
| `tmds_ch1` | out | 10 | 绿通道 TMDS 符号 |
| `tmds_ch2` | out | 10 | 红通道 TMDS 符号 |
| `aud_overflow` | out | 1 | 音频 FIFO 溢出 |
| `aud_underflow` | out | 1 | 音频 FIFO 欠载 |

## Clocking and Reset

- **时钟域**: `clk_pix` (25 MHz)
- **复位**: `rst_n` 低有效

## Functional Behavior

### 视频时序（640×480@60，25 MHz）

| 阶段 | x 范围 | 说明 |
|------|--------|------|
| 控制期 | x=0 | 任意消隐行，vid_de=0 |
| 活动视频 | x=[0..639] | vid_de=1 |
| 前导码 | x=[640..647] | ch0=控制/前导码，ch1=ch2=0 |
| 预数据岛保护带 | x=[648..649] | ch0=GB(0x157)，ch1=ch2=0 |
| 数据岛 | x=[650..673] | TERC4 编码，所有通道 |
| 后数据岛保护带 | x=[674..675] | ch0=GB(0x00A)，ch1=ch2=0 |
| 控制期 | x=[676..799] | 控制码，vid_de=0 |

### 各通道行为

| 通道 | 活动视频 | 前导码 | 预GB | 数据岛 | 后GB | 控制期 |
|------|----------|--------|------|--------|------|--------|
| ch0 (蓝) | 8b/10b 编码 | 前导码/控制码 | GB 0x157 | TERC4 | GB 0x00A | 控制码 |
| ch1 (绿) | 8b/10b 编码 | 0 | 0 | TERC4 | 0 | 0 |
| ch2 (红) | 8b/10b 编码 | 0 | 0 | TERC4 | 0 | 0 |

### 控制码（ch0，{vs,hs} 决定）

| c={vs,hs} | 含义 | 控制码 |
|------------|------|--------|
| 00 | 无同步 | 0x000 |
| 01 | HS 有效 | 0x154 |
| 10 | VS 有效 | 0x0AB |
| 11 | HS+VS 有效 | 0x354 |

### 前导码（ch0）

- x=640..642（cycles 0-2）：复用上一控制期末尾的控制码（CTL1/2/3）
- x=643..647（cycles 3-7）：0x2AA（数据岛前导码模式）

### 数据岛内容

- 每行数据岛传输一个包（header 3B + 4 subpacket 各 7B = 36B）
- 288 bit × 1/12 = 24 周期（x=650..673）
- 包由内部 `hdmi_packet_scheduler` 产生，pkt_req 在 x=[610..639] 提前 57+ 拍发出

### TMDS 视频编码

- RGB 三分量各用独立 `hdmi_tmds_encoder`
- ch0 的 c={vs,hs}，ch1/ch2 的 c=00
- 1 拍延迟

## Timing, Latency, and Throughput

- **整体延迟**: `hdmi_tmds_encoder` 1 拍 + 数据岛 1 拍（latch）
- **吞吐**: 每拍 1 个 TMDS 符号，无反压
- **pkt_req**: 在数据岛前约 30 拍发出

## Assumptions and Chosen Defaults

- 上游 `osd_compositor` 输出 `vid_de/vid_hs/vid_vs/vid_rgb` 满足 640×480@60 时序
- 音频 `aud_stb/aud_l/aud_r` 由 `audio_sample_clk` 和 `audio_mixer` 驱动
- 复位后第 1 帧无数据岛，直到 pkt_latched_valid 首次置位

## Edge Cases and Error Handling

- 数据岛期间 pkt_latched_valid=0：输出全 0（不发送损坏数据）
- 复位后第 1 行：pkt_req 可能来不及 ack，直接进入数据岛期，输出 0
- 控制期的 HS/VS 切换：last_ctrl_sym 正确锁存，无竞争

## Synthesis Notes

- **预估资源**: 约 600 LUT4（3×TMDS 编码器 + 3×TERC4 + 包调度 + 状态机）
- **目标器件**: EG4S20BG256，TD 6.2.1
- **无 RAM / DSP**

## Verification Plan

1. **时序验证**: 确认 de 上升沿对应 x=0，且数据岛出现在 x=650..673
2. **包传输验证**: pkt_req 在 x=610..639，pkt_ack 在数据岛前被置位
3. **控制码验证**: 4 种 c 组合对应正确控制码，且 last_ctrl_sym 正确传递到 preamble
4. **TMDS 编码验证**: 与 `hdmi_tmds_encoder` 黄金模型对拍
5. **数据岛完整性**: 确认 24 周期传输完整的 288 bit 包

## Acceptance Criteria

- [x] 控制期/前导码/保护带/数据岛/视频期顺序正确
- [x] ch0 视频期编码含 vs/hs 控制位
- [x] 前导码前 3 字符复用上一控制码，后 5 字符为 0x2AA
- [x] 数据岛 TERC4 编码正确，288 bit 包完整
- [x] `aud_overflow/underflow` 输出到诊断位
- [x] iverilog 编译零 error

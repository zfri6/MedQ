# param_ctrl Behavior Specification

## Requirement Summary

实时参数调节模块。接收按键（KEY0/1/2）和拨码（SW）输入，实现 7 项参数的实时调节，支持长按连续增减。参数输出到 `param[63:0]`，同时产生 OSD 提示，3 秒后自动隐藏。

## Public Interface

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | in | 1 | 50 MHz 系统时钟 |
| `rst_n` | in | 1 | 异步复位，低有效 |
| `key_press[3:0]` | in | 4 | 按下沿脉冲（消抖后）|
| `key_hold[3:0]` | in | 4 | 长按电平（>1 秒持续高）|
| `sw[3:0]` | in | 4 | 拨码，选择当前调节项 |
| `ext_we` | in | 1 | 外部写使能（uart_cmd）|
| `ext_sel[3:0]` | in | 4 | 外部参数选择 |
| `ext_val[7:0]` | in | 8 | 外部参数值 |
| `param[63:0]` | out | 64 | 参数总线 |
| `osd_hint_id[3:0]` | out | 4 | 当前调节项 0=无 |
| `osd_hint_val[7:0]` | out | 8 | 当前值 |
| `osd_hint_vis` | out | 1 | 提示可见 |

## Parameters and Defaults

无顶层参数。

## Clocking and Reset

- **Clock**: `clk_sys` = 50 MHz
- **Reset**: `rst_n` 低有效，复位时参数回默认值。

## Functional Behavior

### 参数项

| ID | 参数名 | 位域 | 范围 | 类型 |
|----|--------|------|------|------|
| 0 | 亮度 | `param[7:0]` | 0..255 | 连续 |
| 1 | 对比度 | `param[15:8]` | 0..255 | 连续 |
| 2 | 音量 | `param[23:16]` | 0..255 | 连续 |
| 3 | 字幕速度 | `param[31:24]` | 0..255 | 连续 |
| 4 | 转场模式 | `param[35:32]` | 0..4 | 离散 |
| 5 | 频谱模式 | `param[39:36]` | 0..3 | 离散 |
| 6 | OSD 层使能 | `param[43:40]` | 0..F | 离散 |

### 操作方式

- **SW 拨码**：选择当前调节项（0..6）
- **KEY0**：递增（+1）
- **KEY1**：递减（-1）
- **KEY2**：确认，显示当前参数值到 OSD
- **长按**：KEY0/1 长按时，计时后产生连续增减脉冲

### 长按连续增减

- 慢速阶段（前 2 秒）：每 2 秒增减 1
- 快速阶段（2 秒后）：每 0.1 秒增减 1
- 适用于亮度、对比度、音量、字幕速度（连续参数）
- 转场模式、频谱模式、OSD 层使能为离散参数，每次按键只变化 1

### OSD 提示

- 每次参数变化或 KEY2 确认时，显示当前参数 ID 和值
- 3 秒后自动隐藏（`osd_hint_vis` 清零）

### 外部写入（uart_cmd）

- `ext_we=1` 时，直接写入指定参数，跳过按键逻辑
- 常用于调试时通过串口改参数

## Timing, Latency, and Throughput

- 参数更新：一个时钟周期生效
- OSD 提示超时：3 秒精确计时

## Assumptions and Chosen Defaults

1. `key_press` 和 `key_hold` 由 `key_debounce` 消抖后提供。
2. 连续参数（亮度/对比度/音量/字幕速度）使用饱和加减，边界值（0/255）停止变化。
3. 离散参数（转场/频谱/OSD层）使用循环加减，有上下界。
4. `sw` 拨码直接决定 `cur_sel`，无需额外确认。

## Edge Cases and Error Handling

- 连续参数边界：0 不再减，255 不再加。
- 离散参数边界：各自有上下界，到边界后停止变化。
- 外部写入与按键同时到达：外部写入优先。
- 参数变化和 KEY2 同时到达：都触发 OSD 提示（结果相同）。
- 复位：参数回默认值，OSD 提示关闭。

## Synthesis Notes

- 估算 LUT：约 80（参数 mux + 增减逻辑 + 定时器）
- 估算 FF：约 60
- 无 BRAM，无乘法器
- 定时参数均基于 50 MHz 时钟

## Verification Plan

1. **默认值**：复位后 brightness/contrast=128，volume=200。
2. **SW 选择**：切换 SW，cur_sel 跟随变化。
3. **KEY0 递增**：按一次加 1，边界 255 不越界。
4. **KEY1 递减**：按一次减 1，边界 0 不越界。
5. **长按连续**：KEY0 长按，慢速阶段 2s 加一次，快速阶段 0.1s 加一次。
6. **离散参数边界**：转场模式 0..4 循环。
7. **OSD 提示超时**：参数变化后 3s 隐藏。
8. **外部写入**：ext_we 写入立即生效。

## Acceptance Criteria

- [ ] 7 项参数全部可调
- [ ] 连续参数饱和不越界
- [ ] 长按连续增减（2s 慢速 + 0.1s 快速）
- [ ] OSD 提示 3 秒后自动隐藏
- [ ] 外部写入（uart_cmd）正常生效
- [ ] 复位后参数回默认值
- [ ] iverilog 编译零 error

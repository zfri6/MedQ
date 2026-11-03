# buzzer Behavior Specification

## Requirement Summary

蜂鸣器提示音模块，支持三种音型：普通叫号（双响）、重呼（三响）、优先号（长响）。接收 `trig` 脉冲触发，输出 `beep` 方波信号，`busy` 标志播放状态。

## Public Interface

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | in | 1 | 50 MHz 系统时钟 |
| `rst_n` | in | 1 | 异步复位，低有效 |
| `trig` | in | 1 | 触发脉冲 |
| `pattern[1:0]` | in | 2 | 音型：0=普通 1=重呼 2=优先 |
| `mute` | in | 1 | 静音 |
| `beep` | out | 1 | 蜂鸣器输出方波 |
| `busy` | out | 1 | 音型播放中 |

## Parameters and Defaults

| Parameter | Default | Description |
|-----------|---------|-------------|
| `CLK_HZ` | 50000000 | 系统时钟频率 |

## Clocking and Reset

- **Clock**: `clk_sys` = 50 MHz
- **Reset**: `rst_n` 低有效，复位时 `beep=0`，`busy=0`。

## Functional Behavior

### 音型定义

| 音型 | `pattern` | 频率 | 时序 |
|------|-----------|------|------|
| 普通叫号 | `2'b00` | 500 Hz | 响 200ms → 停 200ms → 响 200ms |
| 重呼 | `2'b01` | 800 Hz | 响 200ms → 停 100ms → 响 200ms → 停 100ms → 响 200ms |
| 优先号 | `2'b10` | 1000 Hz | 响 800ms |

**注意**：`pattern[1]=1`（优先）时忽略 `pattern[0]`；`pattern[1:0]=2'b10` 优先，`2'b01` 重呼。

### beep 波形

- 方波占空比 50%
- 优先：1000 Hz
- 普通：500 Hz
- 重呼：800 Hz

### 时序

- `trig` 脉冲触发一次完整音型播放。
- 播放期间 `busy=1`。
- 播放完毕自动回到空闲，可接受新的 `trig`。
- `mute=1` 时 `beep=0`，但 `busy` 仍保持（音型逻辑继续运行）。

### 参数精度

| 频率 | 周期 (clocks) | 实际频率 | 误差 |
|------|---------------|----------|------|
| 1000 Hz | 50000 | 1000.00 Hz | 0% |
| 800 Hz | 62500 | 800.00 Hz | 0% |
| 500 Hz | 100000 | 500.00 Hz | 0% |

## Assumptions and Chosen Defaults

1. 蜂鸣器为有源蜂鸣器（需要外部振荡），本模块输出 50% 占空比方波作为驱动。
2. `trig` 脉冲宽度为 1 周期，不要求持续电平。
3. 音型播放期间忽略新的 `trig`（`busy` 阻塞）。
4. `mute` 为异步静音，立即生效。

## Edge Cases and Error Handling

- `trig` 在 `busy=1` 时到达：忽略，等待当前音型结束。
- `mute` 在播放中途拉高：立即停止 beep。
- `pattern` 在播放期间切换：不影响当前播放，下一次 `trig` 时生效。
- 复位：`beep=0`，`busy=0`。

## Synthesis Notes

- 估算 LUT：约 40（状态机 + 方波振荡器）
- 估算 FF：约 50
- 无 BRAM，无乘法器
- 频率参数（周期计数器）均为 50 MHz 的整除数，无频率误差

## Verification Plan

1. **普通音型**：验证 500 Hz 方波，200ms-on/200ms-off/200ms-on。
2. **重呼音型**：验证 800 Hz 方波，三响两间隔。
3. **优先音型**：验证 1000 Hz 方波，800ms。
4. **静音**：`mute=1` 时 beep=0。
5. **忙标志**：`busy` 在播放期间为 1，结束后清零。
6. **屏蔽重复触发**：播放期间再给 trig 不重启。

## Acceptance Criteria

- [ ] 普通叫号产生 500 Hz 双响（200ms-200ms-200ms）
- [ ] 重呼产生 800 Hz 三响（200ms-100ms-200ms-100ms-200ms）
- [ ] 优先号产生 1000 Hz 长响（800ms）
- [ ] `mute=1` 立即停止 beep
- [ ] `busy` 在播放期间为 1
- [ ] iverilog 编译零 error

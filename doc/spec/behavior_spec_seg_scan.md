# seg_scan Behavior Specification

## Requirement Summary

8 位数码管动态扫描，刷新率 1 kHz（每 digit 125 Hz）。接收 8 个 BCD digit 输入，产生共阳/共阴兼容的段码和位选输出。

## Public Interface

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | in | 1 | 50 MHz 系统时钟 |
| `rst_n` | in | 1 | 异步复位，低有效 |
| `digits[31:0]` | in | 32 | 8 个 4-bit BCD，digit0 在低位 |
| `dp[7:0]` | in | 8 | bit[n]=1 显示 digit[n] 的小数点 |
| `blank[7:0]` | in | 8 | bit[n]=1 熄灭 digit[n] |
| `seg_data[7:0]` | out | 8 | `{dp,g,f,e,d,c,b,a}` |
| `seg_sel[7:0]` | out | 8 | 位选，低有效 |

## Parameters and Defaults

| Parameter | Default | Description |
|-----------|---------|-------------|
| `CLK_HZ` | 50000000 | 系统时钟 |
| `SCAN_HZ` | 1000 | 扫描频率（总刷新率）|
| `SEG_ACTIVE_LOW` | 1 | 1=共阳数码管（段低点亮），0=共阴（段高点亮）|
| `SEL_ACTIVE_LOW` | 1 | 1=位选低有效，0=位选高有效 |

- 按 50 MHz / 1 kHz / 8 位：`DIV = 6250`

## Clocking and Reset

- **Clock**: `clk_sys` = 50 MHz
- **Reset**: `rst_n` 低有效，复位时熄灭全部数码管。

## Functional Behavior

### 动态扫描原理

8 个数码管共用同一套段选线（`seg_data`），通过快速循环点亮各 digit 实现"同时显示"的视觉效果。

- **总刷新率**：`SCAN_HZ = 1000 Hz`
- **每位刷新率**：`SCAN_HZ / 8 = 125 Hz`（> 60 Hz，无闪烁）
- **每位持续时间**：`1 / 1000 = 1 ms`

### 分频

计数器从 0 计数到 `DIV_M1`（6249），溢出时切换位选。8 位循环。

### BCD 译码

输入 4-bit BCD → 7 段驱动码（段位 = gfedcba），熄灭时全 0。

### 有效电平

- `SEG_ACTIVE_LOW=1`（共阳）：段码取反 → 某段=0 时点亮，=1 时熄灭
- `SEL_ACTIVE_LOW=1`：位码低有效 → `sel_onehot=11111110` 时选通 digit[0]

### 熄灭处理

`blank[n]=1` 时该位所有段输出高（SEG_ACTIVE_LOW=1 时 0xFF），无论 digit 值。

## Timing, Latency, and Throughput

- 分频器精度：整数分频（6250）
- 段码/位选切换：每个扫描周期更新一次（每 1 ms）
- 无流水线延迟

## Assumptions and Chosen Defaults

1. 数码管为共阳（SEG_ACTIVE_LOW=1），常见于多数 8 段数码管模块。
2. 位选低有效（SEL_ACTIVE_LOW=1），匹配常用三极管/译码器驱动电路。
3. `digits` 的低 16 位保留给 4 位候诊票号（来自 `qstate.cur_ticket_bcd`），高 16 位用于其他信息。

## Edge Cases and Error Handling

- BCD 值 > 9：显示空白（全部段熄灭），避免错误显示。
- `blank=0xFF`：全部熄灭，适用于省电场景。
- 复位期间：全部熄灭。

## Synthesis Notes

- 估算 LUT：约 50（BCD 译码 + 分频 + 位选）
- 估算 FF：约 20
- 无 BRAM，无乘法器
- 关键是：分频计数器宽度足够（14-bit 可容纳 6250）

## Verification Plan

1. **扫描频率**：测量 `seg_sel` 周期 ≈ 8 ms（1 kHz / 8）。
2. **BCD 正确性**：输入 `digits=0x12345678`，验证各 digit 段码正确。
3. **熄灭**：设置 `blank=8'hFF`，验证全部熄灭。
4. **小数点**：设置 `dp=8'h01`，验证 digit[0] 小数点亮。
5. **极性参数**：切换 SEG_ACTIVE_LOW/SEL_ACTIVE_LOW，验证行为正确。

## Acceptance Criteria

- [ ] `seg_sel` 以 125 Hz 切换各 digit
- [ ] 0-9 BCD 正确显示
- [ ] `blank` 控制熄灭正确
- [ ] `dp` 显示小数点正确
- [ ] `SEG_ACTIVE_LOW` 参数切换共阳/共阴行为
- [ ] iverilog 编译零 error

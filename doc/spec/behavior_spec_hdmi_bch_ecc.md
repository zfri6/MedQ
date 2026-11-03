> 2026-10-26：本模块已在仿真闭环修复中更新；以下为历史初版。当前行为与接口以 [闭环行为说明](behavior_spec.md) 和实际 RTL 为准。

# hdmi_bch_ecc Behavior Specification

## Requirement Summary

实现 HDMI 数据岛的 BCH(64,56) 纠错码生成器，对数据岛包头（3B）和子包（7B）共 80bit 做串行 LFSR 校验，生成 8bit 校验字节。

## Public Interface

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | in | 1 | 25 MHz 像素时钟 |
| `rst_n` | in | 1 | 低有效异步复位，同步释放 |
| `clear` | in | 1 | 1：复位 LFSR 为全 1，开始新包 |
| `shift_en` | in | 1 | 1：本拍将 bit_in 移入 LFSR |
| `bit_in` | in | 1 | 串行数据位（MSB 在先） |
| `ecc_out` | out | 8 | 当前 LFSR 状态（即校验字节） |

## Parameters and Defaults

无参数。

## Clocking and Reset

- **时钟域**: `clk_pix` (25 MHz)
- **复位**: `rst_n` 低有效；`clear=1` 或 `rst_n=0` 时 LFSR 复位为 8'hFF

## Functional Behavior

### BCH(64,56) 编码原理

- **生成多项式**: g(x) = x⁸ + x⁷ + x⁶ + x⁴ + x² + 1 （二进制 0b11010101 = 0xD5）
- **信息字段**: 56 bit（数据岛 header 24bit + subpacket 32bit = 56bit）
- **校验字段**: 8 bit（LFSR 最终状态）
- **总码字**: 64 bit（56 data + 8 parity）

### LFSR 操作流程

1. **初始化**: `clear=1` 或复位时，LFSR = 8'hFF（全 1）
2. **移入数据**: 每拍 `shift_en=1` 时，将 `bit_in` 与当前 LFSR 按生成多项式做除法
   - 反馈 = `bit_in ^ lfsr[7] ^ lfsr[6] ^ lfsr[5] ^ lfsr[3] ^ lfsr[1]`
   - 移位：`lfsr <= {feedback, lfsr[7:1]}`
3. **数据结束**: 移入 56 bit 数据后，再继续移入 8 个 0（padding，lfsr 不再受 bit_in 影响但继续移位）
4. **读取结果**: 在第 64 拍 `shift_en=1` 后，`ecc_out` 即为 BCH 校验字节

### 注意事项

- `clear` 与 `shift_en` 同时为 1 时，`clear` 优先（LFSR 先清零再移位）
- `shift_en=0` 时 LFSR 保持不变
- `bit_in` 在 `shift_en=0` 时不关心

## Timing, Latency, and Throughput

- **延迟**: 0 拍（组合输出，`ecc_out` 跟随 LFSR 当前状态）
- **吞吐**: 每拍最多移入 1 bit
- **完整包耗时**: 64 拍（含 8 拍 padding）

## Assumptions and Chosen Defaults

- 上游保证 `bit_in` 符合 HDMI 数据岛格式：header 先 MSB，然后各 subpacket 先 MSB
- 连续包的第二 subpacket 需重新 `clear` 后再移入
- BCH 是缩短码，实际处理的是 56 bit 信息（不是标准的完整 64 bit 块）

## Edge Cases and Error Handling

- `rst_n=0` 时 LFSR = 8'hFF，等效于一次 `clear`
- `shift_en=0` 期间 `ecc_out` 保持不变，无毛刺

## Synthesis Notes

- **预估资源**: 约 12 FF + 5 LUT4（XOR chain）
- **目标器件**: EG4S20BG256，TD 6.2.1
- **无 RAM / DSP**

## Verification Plan

1. **已知向量验证**: 用 Python 生成已知信息的 BCH 校验码，比对 RTL 输出
2. **零填充验证**: 56 bit 数据后跟 8 bit 0，确认 ecc_out 与标准一致
3. **与 hdmi_tx_core 集成测试**: 数据岛包在仿真中发送，BCH 校验码可被 HDMI 接收器验证
4. **自检**: 同一数据做两次（先算 ecc，再把 ecc 作为 bit_in 移入）应得到 0

## Acceptance Criteria

- [x] `clear` 置 1 后 LFSR = 8'hFF
- [x] `shift_en=1` 时 LFSR 正确移位，XOR 反馈符合 g(x)=x⁸+x⁷+x⁶+x⁴+x²+1
- [x] 64 拍后 ecc_out 为稳定的 BCH 校验字节
- [x] `shift_en=0` 时 ecc_out 保持不变
- [x] iverilog 编译零 error

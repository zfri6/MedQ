# STA 边界与 I/O 预算

本次签核同时报告 slow/fast 的 max/min、所有时钟路径组、时序例外和约束健康检查。
没有显式 false path 或异步时钟分组，也没有内部多周期。TD会将下面I/O专用的 `-datapath_only` 最大延迟预算展开为同一I/O边界的 hold 排除；签核脚本逐条列出原生 ignored 报告中的这些路径，并拒绝任何内部寄存器到寄存器或 SDRAM SIP 被排除。所有内部路径，包括 Gray 同步器、握手总线、复位恢复/撤销、pixel/serial 和 SDRAM 读写，继续由实际派生时钟检查。

原生覆盖率不是仅靠添加端口约束就能变成 100% 的指标。按键、UART 的第一采样级允许亚稳态，没有与外部发送端建立同步 hold 的依据；LED 等输出没有片外捕获时钟。下面明确给出本 FPGA 内部的最大传播预算，而不假造外部捕获相位。

| 接口 | FPGA 内部预算 | 对应实现与边界 |
|---|---:|---|
| KEY/SW/UART_RX 到第一采样级 | 最大 8 ns | 输入级和后续同步级分开；后续级仍检查完整 setup/hold。外部按键/UART 的相位没有被声明为同步。 |
| SD_MISO 到 SPI 接收寄存器 | 最大 8 ns | 模式 0，DATA_CLK_DIV=1 时 SCLK=12.5MHz、低半周期40ns；更慢初始化只增加预算。 |
| SPI 时钟/数据/片选到管脚 | 最大 8 ns | 外部卡的 DO 最大延迟预算14ns、外部走线/建立时间合计预算10ns，则8+14+8+10=40ns。该外部预算是接口使用条件，未实测卡或板级走线。 |
| LED/数码管/蜂鸣器/UART_TX | 最大 20 ns | 一次50MHz更新内送达输出端口；不假设片外存在同步采样寄存器。 |
| HDMI 四路 LVDS 输出 | 最大 4 ns | DDR 半周期内 FPGA 本地管脚传播预算；串行化寄存器由125MHz和实际DDR边沿检查。接收端眼图、板级偏斜和线缆质量仍属实板验证。 |

上述最大延迟只作用于列出的端口路径，不影响 SDRAM SIP 或任一内部寄存器间路径。

SDRAM 使用 TD 的内建 SIP 时序模型，保留更保守的 max 输入5ns/min输入1ns、max输出5ns。原始数据手册 DS301 表4-1 给出 tAC<=4.5ns、tOH>=2ns、tIS>=1.5ns、tIH>=1ns。对正1ns的器件输入 hold 要求，SDC output-delay 必须为 min=-1ns；因此本次显式将原生 min=+1ns 改成 -1ns，把写侧 hold 检查收紧2ns，所有PAD快/慢角延迟仍由TD计算。没有把max延迟改小制造正余量。
SIP 的 S1...S89 为工具自动绑定的内部管脚，不是顶层用户IO。`set_sippin_assignment` 仅支持物理延时档位和驱动强度，不能按顶层IO修改电压标准，不能将 INDEL/OUTDEL 当作纳秒约束。本次没有修改SIP物理属性。

PLL 使用本机支持的 `NOCOMP`/`VCO_PHASE_0` 内反馈，保持1GHz VCO与输出分频；原先外反馈在约束健康检查中产生 USR-6135（补偿不可预测）。相应反馈倍频改为 memory=20/1、video=40/2。旧 `CLKC0_INT` 虽存在于功能模型，但本机TD明确拒绝，因此没有用于交付。内部反馈不依赖该局部反馈走线。SDRAM 转发时钟到 SIP 输出PAD的一条局部连线由原生STA计入，不是内部寄存器的局部时钟树。

资料：本机 TD SWUG200/SWUG105；DS301_2.6 SDRAM AC表（厂商原文镜像）
https://www.mikrocontroller.net/attachment/520610/EG4S20_integrated_SDRAM.pdf

本文件是设计约束合同与电脑端签核范围，不能替代下载、长时间实板显示/音频、存储器校验或电气测量。

2026-11-01签核器核对补充：TD可能合并并重命名SD_MISO第一采样寄存器的物理实例。
签核器不按实例名猜测边界，而同时要求原生路径严格为net/PAD/net/LUT2(reg)、
PAD脚与End Point逐一一致、末端net精确为u_asset_loader/u_sd_card_ctrl/u_spi/rx_shift[0]，
且RTL来源为sd_spi_master.v。KEY/SW/UART同样逐条核对net/PAD(reg)与第一同步级net。
插入组合逻辑、后级寄存器、错误PAD或来源均拒绝。此核对不改变SDC或任何时序排除范围。

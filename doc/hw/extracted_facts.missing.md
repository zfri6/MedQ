> 最新实测：授权已恢复；medq_pll 已由 TD 生成（50 -> 125/25/100 MHz，extlock 导出）并通过模型测试。仍缺真实 SDRAM 控制器、最终时序/资源闭环及扩展资料。下文相应旧状态已被本条与 td_report.md 更新。

# 硬件事实缺口清单

2026-10-26 实测增补优先于下文旧处置：TD 已安装但综合授权过期；已找到 EG_PHY_SDRAM_2M_32，仍缺控制器。
40 个实际顶层端口已按同型 DEMO 原属性生成 top.adc，通过静态比对；原理图用于具体冲突和扩展缺口，不是所有主链路映射的前提。
EG_LOGIC_ODDR 已完成真实模型串化自检，原语名称不再是未知项。SDC、PLL lock/存储 PLL、SDRAM、Flash 与第二屏仍未闭环。
以 doc/compile/td_report.md、prj/constr/pin_summary.md 为准；不能沿用下文 virtualIO 占位作为可下载位流。

状态：`partial`。已确认的事实见 `doc/hw/extracted_facts.json`。本文件列出仍需补齐的内容、当前最佳候选值，以及去哪里找。

## 一、阻塞级缺口（影响架构或基础要求）

### 1. 片内 SDRAM 的访问方式 —— 最高优先级

EG4S20BG256 封装内集成 2M×32 bit SDRAM，但**本地资料包没有任何一个 DEMO 使用它**，也没有对应的参考设计或手册。

- 缺什么：SDRAM 的访问原语名（是否为 `EG_PHY_SDRAM_2M32` 之类的硬核接口）、或安路 SDRAM 控制器 IP 的端口定义与时序。
- 影响：直接卡基础要求 1（BMP 写入 SDRAM 帧缓存）。这是当前唯一的架构级未知数。
- 去哪找（按优先级）：
  1. `6_EG4S20` 目录下的 EG4 系列技术手册
  2. 安路参考设计 `sdram_read_write_with_local_bus_reference_design_V1.1` + 手册 `APUG010_Local bus总线的SDRAM读写v1.1.pdf`
  3. 安路参考设计 `high_performance_sdram_read_write_reference_design_v1.2` + 手册 `APUG011_基于ERAM接口实现的高性能SDRAM读写v1.2.pdf`
  4. `7_lab_ex_2026_nosoft` 里的 lab_ex_4（它必然用到了 SDRAM 帧缓存）
  5. TD 6.2.1 安装后的 IP Generator 目录与 `<TD_HOME>/sim_release/eg/*.v` 原语列表
- 当前处置：架构阶段把 SDRAM 控制器定义为黑盒 `sdram_ctrl_wrap`，冻结面向内部的 Local-Bus 风格接口（见 `doc/arch/interface_contract.yaml`）。所有上游模块只依赖这个接口，实现可替换。TB 用 `tb/sdram_model.v` 行为级模型验证。

### 2. Bank 电压 / IOSTANDARD

同一物理引脚在不同 DEMO 里出现两种电平标准，不可能都对：

- R7（时钟）：`0_cnt1s`、`10_PLL_TEST`、`HX_CESHI_EG4S_BORD`、`18_sd_card_audio` 用 `LVCMOS33`；`33_HX4S20_Ethernet_test/.../ph1_demo.adc` 用 `LVCMOS25`
- B2（KEY[1]）：同上两种
- E7 / F7（VGA 同步）：同上两种

- 缺什么：各 Bank 的 VCCIO 供电电压。
- 去哪找：`3_原理图`（唯一能定性的来源），或 `9_康芯HX4S20使用手册及实验平台介绍`。
- 当前处置：`extracted_facts.json` 里所有非 HDMI 信号记为 `io_standard_candidate` + `evidence_kind: fallback`，**不写死 `io_standard`**。生成 `.adc` 之前必须解决，否则可能出现 TD 报 "IOSTANDARD 与 Bank 电压冲突"。
- 最佳候选：`LVCMOS33`（非以太网 DEMO 一致使用，且板卡 5V/3.3V/2.5V/1.2V 多路供电，以太网那一组很可能在独立的 2.5V Bank）。

### 3. 第二路 HDMI 的引脚

板卡规格明确写「双 HDMI 接口」，但本地所有 `.adc` 只出现一组：`HDMI_CLK_P=C3, D0_P=G5, D1_P=F1, D2_P=E1`。

- 缺什么：第二组 HDMI 差分对的 P 端引脚编号。
- 影响：差异化特性「双 HDMI 同源双视图」无法生成约束。不影响基础要求。
- 去哪找：`3_原理图` 或 `9_使用手册`。
- 当前处置：架构里保留第二路的端口与合成通路（`hdmi_b_*`），约束阶段若仍缺，先用 `LOCATION = virtualIO` 占位或整支剪掉，不阻塞主线。

## 二、非阻塞缺口（有候选值，可先推进）

### 4. 数码管与双色 LED 的复用关系

板卡规格列有「1 组切换数码管和双色 LED 开关」，`8_key_sw` 里 `led[0..7]` 绑的正是数码管段码引脚 C15/C16/B6/A5/B5/A8/A7/A6。

- 推断：8 位数码管与 8 组双色 LED **共用同一组段码与位选引脚**，由板上一个物理拨动开关切换，二者不能同时使用。
- 影响：原构想里「数码管显示票号 + 双色 LED 显示诊室状态」同时工作不成立，必须二选一。
- 当前处置：设计里以数码管为主（显示当前票号），诊室忙闲状态改用 4 个独立 LED（A4/A3/C10/B12）+ HDMI 画面表达。
- 待确认来源：`3_原理图`。

### 5. 板载 64 MB SPI Flash 的引脚

规格表列有「SPI Flash 64MB」（与 16 MB 配置用 QSPI Flash 是两颗）。没有任何 DEMO 使用它。

- 影响：差异化特性「队列状态持久化」无法落地。不影响基础要求。
- 去哪找：`3_原理图`、`9_使用手册`。
- 当前处置：`spi_flash_store` 模块按标准 SPI NOR 命令集（0x03 读 / 0x02 页编程 / 0x20 扇区擦除 / 0x05 读状态）实现并可仿真，引脚待补。若最终拿不到，退化为「掉电不保存」，去掉该特性。

### 6. PLL 的 `extlock` 输出

可复用的 `clk_wize.v` 把 `extlock` 接到了 `open`，拿不到锁定指示。

- 影响：复位序列希望「PLL 锁定前全局保持复位」。
- 当前处置：`rst_sync` 支持两种模式——有 `pll_locked` 时用它，没有时用一个足够长的上电计数器（默认 1 ms @ 50 MHz）兜底。TD 装好后重新生成一版导出 `extlock` 的 PLL 即可切换，接口不变。

### 7. EG4 的 DDR 输出 / LVDS 串化原语名

自研 HDMI 发送器需要 10:1 串化，得知道 EG4 有哪些可用原语（`EG_PHY_OSERDES`? `EG_LOGIC_ODDR`?）。

- 去哪找：`6_EG4S20` 手册；TD 安装后的 `<TD_HOME>/sim_release/eg/*.v`。
- 当前处置：`tmds_serdes.v` 做成薄封装，内部用 `ifdef` 切换；仿真时用行为级模型，上板时换成原语实现。**边界之上（TMDS 符号生成）完全不受影响，现在就能全部仿真验证。**

## 三、缺失的资料目录（整体）

本地 `HX4S20_Contest_202606/` 只有 `1_安路工具和软件`、`2_Example`、`4_芯片手册`、`资料指引.docx`。

| 目录 | 内容 | 用途 | 紧急度 |
|---|---|---|---|
| `6_EG4S20` | EG4 系列技术手册 | SDRAM 访问、串化原语、IOSTANDARD 合法值、资源上限 | 高 |
| `7_lab_ex_2026_nosoft` | lab_ex_4 / lab_ex_5 参考例程 | TF→SDRAM→HDMI 全链路、HDMI 音频测试音 | 高 |
| `3_原理图` | 开发板原理图 | Bank 电压、第二路 HDMI、SPI Flash、数码管复用 | 高 |
| `9_康芯HX4S20使用手册及实验平台介绍` | 使用手册 + 引脚说明 | 权威引脚表，交叉校验以上全部 | 中 |
| 安路参考设计 | APUG010 / APUG011 / APUG092 / IPUG012 | SDRAM 读写、HDMI 1.4b 发送器（含音频）、Soft FIFO | 高 |

获取途径：竞赛 QQ 群 1050628457，或百度网盘 `HX4S20_Contest_202606`（链接见 `安路官方资料百度网盘链接.txt`，注意该 txt 里是 2025 版链接，2026 版链接在选题指南 markdown 里）。

## 四、板级顶层缺口

`rtl/top.v` 尚未生成（架构阶段先出 `rtl/top_skeleton.v`）。生成 `.adc` 需要两个前提同时满足：

1. `rtl/top.v` 存在且端口用板级信号名
2. 本文件第一节的 Bank 电压问题已解决

两者缺一不可，缺时补信息，不猜。

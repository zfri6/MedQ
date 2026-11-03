> 最新验证：ModelSim22/22 PASS、95项哈希一致；新增像素/波形等价、FAT地址和独立Goertzel数值自检。20张UI帧SHA相同，原语模型证据另存；TD资源与限制见resource_optimization_report.md。下文旧回归统计对应冻结快照。

> 最新快照：新 PLL / FAT32 BRAM 优化后的 ModelSim 18/18 再次通过，FAT_BOUNDARY 单独通过。TD 综合已运行，资源与限制以 td_report.md 为准；旧 80 项哈希和授权过期说明属于此前快照。

> 2026-10-26 TD 接续增补：当前源码 80 项哈希匹配，ModelSim 18/18 重新通过，Verilog-2001 门禁通过。
> 真实 EG4 ODDR 串化模型另行通过；40 bit ADC 静态覆盖通过。完整 top 的 TD 展开仍被 pll_mem 黑盒阻塞，综合探针授权过期。
> 详见 td_report.md。下文旧双工具统计对应原冻结快照，不代表当前源码完成了全套双工具或实板验证。

# MedQ（医序）仿真闭环验收记录

## 当前界面更新版本

2026-10-26：医疗风格界面、2 bit 抗锯齿字模及 16 帧缓出动画已接入真实 OSD。
当前源码 **ModelSim 18/18 PASS**，Verilog-2001 门禁通过；78 个源码/数据 SHA256 在回归期间保持一致。
Icarus 另通过原 OSD 配置与视频时序两项检查；未对新版完整源码重复全套双工具验收。
整机仍从板级输入完成三次叫号/重呼、27 段 PCM、完整图像捕获，无显示/音频欠载。

[新版界面验收说明](ui_refresh_report.md) · [当前回归结果](../../sim/regression_result.json) · [实际动画](../../sim/ui/medq_call_animation.gif)

## 界面更新前的历史记录

以下 34/34、74 文件及渐变图像参考比对对应更新前源码；原证据保存在 `sim/medq_simulation_closure_20261026.zip`。
当前逐测试目录已由新版回归更新，当前行为与结果以上面的界面验收说明为准。

日期：2026-10-26。主工程：`C:/Users/zhang/Desktop/安路`。

**结果：主业务行为仿真通过。17 项用例分别在 ModelSim 和 Icarus 执行，共 34/34 PASS。**
源码与测试数据共 74 个文件的 SHA256 在两次工具回归、Icarus 长场景补跑及最终汇总时一致。
根 `rtl/` 共 47 个 Verilog 文件（42 个原契约功能模块、3 个辅助模块、实际/参考顶层）；两个厂商 wrapper 的字节与接续前快照一致。

## 复现

在工程根目录 PowerShell 执行：

```powershell
python sim/run_regression.py --sim modelsim
```

双工具交叉检查：

```powershell
python sim/run_regression.py --sim both --timeout 600
```

单独运行整机：

```powershell
python sim/run_sim.py --sim modelsim --run --tb-top tb_top --output-dir sim/tests/modelsim/tb_top
```

ModelSim 10.4 不能直接处理当前中文路径。入口自动复制仿真源到临时 ASCII 目录，按 TB 隔离工作库，再把日志与帧捕获复制回工程。
未安装/使用安路原语仿真库；默认 profile 为 `behavioral`。真实厂商模型必须另选 `--anlogic-lib`，缺库时明确失败。

## 工具与门禁

- Icarus Verilog 12.0 (devel)；ModelSim SE-64 10.4。
- `sim/rtl_2001_compile.log`：`-g2001 -Wall -DSIMULATION -tnull -s top -s top_skeleton`，退出 0。
  自研 RTL 全部参与；真实 `clk_wize` wrapper 由行为时钟模型替代，未用本门禁证明安路原语可用。
- ModelSim 的 RTL 按普通 Verilog 编译，TB 单独以 `-sv` 编译；34 次运行都实际结束且无 ERROR/FAIL/Fatal/超时。
- Icarus 的数组敏感列表提示属于组合逻辑展开信息；没有保留原先的数值常量截断、端口方向冲突、隐式网线或多驱动错误。

Icarus 整机首次运行触及 240 秒墙钟限制，该次失败记录保存在 `sim/regression_iverilog_attempt1.json`。
相同源码以 600 秒上限复测通过，最终汇总采用成功复测；历史超时没有伪装成 PASS。

## 逐项结果

| 测试 | 实际检查 | ModelSim | Icarus |
|---|---|---|---|
| tb_rst_sync | 真正 POR 到期、锁定时外部复位、PLL 失锁、两拍释放 | PASS | PASS |
| tb_key_debounce | 消抖、按下/释放与长按 | PASS | PASS |
| tb_cdc_bus_handshake | 宽总线握手与状态传递 | PASS | PASS |
| tb_cdc_pulse | 12 次应答事件，包含请求两种翻转方向 | PASS | PASS |
| tb_queue_fsm | 公平调度、重呼、过号、满队列、BCD 进位/0000、恢复、自动模式 | PASS | PASS |
| tb_sdram_arbiter | 256 字突发、四主竞争、请求/数据反压、内容与高地址不别名 | PASS | PASS |
| tb_bmp_parser | 连续字节、24/32bpp、padding、方向、偏移与错误头 | PASS | PASS |
| tb_fat32_reader | 根目录簇链、高 28 位簇号、碎片化 700 字节、反压、SD 错误和 BPB 错误 | PASS | PASS |
| tb_asset_loader | SPI SDHC 初始化、1 BMP/19 PCM、完整缩放图与 FB1 重载 | PASS | PASS |
| tb_storage_errors | 无卡有限超时及错误向上层传播 | PASS | PASS |
| tb_osd_renderer | 字段配置、同步字模延迟、颜色、放大、透明边界和层关闭 | PASS | PASS |
| tb_video_pipeline | 两个完整 800×525 帧、640×480 活动区、HS/VS、alpha 和饱和 | PASS | PASS |
| tb_audio_pipeline | 精确采样间隔、完整四位票号、两轮 18 段播放、有符号插值、末字与空片段 | PASS | PASS |
| tb_hdmi_tmds_encoder | 四种控制码、8193 个视频符号回译与视差界限 | PASS | PASS |
| tb_hdmi_tx_core | 307200 视频像素、1608 包回译、五块 BCH、InfoFrame checksum、824 组有序音频 | PASS | PASS |
| tb_tmds_serdes | 128 个连续 10 位字、DDR 比例、LSB 先发 | PASS | PASS |
| tb_top | 板级输入驱动完整业务与媒体链路，见下文 | PASS | PASS |

## 整机证据

`tb_top` 实例化实际 `rtl/top.v`，从板级端口驱动时钟、UART、开关、带抖动按键和 SD SPI 卡模型。
没有强制内部状态、计数器、总线握手或替换叫号/素材处理模块来制造完成信号。

- 卡模型通过真实 SCLK/MOSI/MISO/CS 命令交换提供合成 FAT32 介质；加载 1 张 2×2 BMP、19 段三样本 PCM。
- BMP 放大到 640×480，素材单测对全部 307200 个存储字逐一比对，并检查 19 段 PCM 的内容、地址及样本数。
- 整机通过 UART 115200 8N1 取号、叫号、重呼、设参数；损坏 CRC 回 NAK 且不改变队列。
- 按键使用实际 10 ms 消抖参数，再取一号并叫出 A0002/诊室 2。
- 3 次叫号事件完整跨域，播完 27 段 PCM；板级输出无未知值，活动期间无显示/PCM 欠载。
- 运行约 39.6255 ms，经过 3 次帧开始，产生 1902 次音频采样选通；捕获一整幅合成后 VGA 图像。

两仿真器捕获的 PPM 完全相同，SHA256：
`cd6281ff7201dd826374840c0a42b0d90d227f566b43a4161698977fc110b5e9`。
各自 296448 个非文字背景像素与独立双线性插值参考值比较，差异为 0。

![ModelSim 捕获的 MedQ 合成像素](../../sim/tests/modelsim/tb_top/top_frame.png)

这张图来自仿真像素流，不是实板截图，也不是另行绘制的设计稿。

## 主要修复

- 补齐缺失对象、生成 FIFO 端口错误、多驱动、Verilog-2001 语法和常量截断。
- 修复会卡死的叫号状态机、错位 QSTATE、BCD 进位、重呼消耗队列、诊室分配和满队列处理。
- 修复 SDRAM 读方向及顶层连线；整笔突发锁定仲裁归属，地址和数据按握手推进。
- 重建有反压的 SD→FAT32→BMP→双线性缩放→SDRAM 链路，避免漏字节、旧红色数据、行覆盖及提前完成。
- 修复脉冲 CDC 丢失第二次翻转、总线 CDC 读取活动源、叫号脉冲与伴随数据不同步。
- 修复音频选通长时间为高、重复播放卡死、缺少票号最低位、插值符号和末尾补齐。
- 修复 TMDS 控制码/编码、TERC4 表、BCH 初值/多项式、错误包长及声道包布局；首行同步后才发数据岛。
- 补齐字模文件及中文标题，统一 ROM 地址与像素流水对齐；更正亮度、alpha 运算和视频帧起点。

当前语义及必要接口增补详见 `doc/spec/behavior_spec.md`。旧逐模块文档已标注历史状态。

## 仍未证明的内容

此结果是**主业务行为仿真闭环**，不能解释为全套赛题功能或实板交付已经完成。

- 安路 TD 工程、真实 SDRAM 控制器、真实 EG4 串化器/PLL 原语模型、约束、综合资源、时序、位流与实板均未验收。
- Flash 引脚未进入板级端口，物理 Flash 擦写/掉电恢复没有本轮端到端证据；只验证了队列快照字段恢复。
- 第二屏、全部页面/诊断 UI、各转场模式、频谱算法与仪表指标仍需专项验收；顶层默认路径运行不等于这些模式正确。
- 特别是现有 `av_sync_monitor` 仍以 60 Hz/800 样本为基准，与本设计 25 MHz/800/525 的 59.5238 Hz、806.4 样本/帧不一致，不能据其输出宣称音画同步测量通过。
- SDHC 是本轮实际覆盖卡型；SDSC、更多 BMP 尺寸/位深组合、真实卡与全部文件系统变体未穷举。

## 可复核产物

- `sim/regression_result.json`：34 项结果、74 个源/数据文件指纹及工具记录。
- `sim/tests/{modelsim,iverilog}/<tb>/`：逐项编译日志、运行日志和结果 JSON。
- `sim/frame_verification.json`：两工具帧指纹及独立背景像素比较。
- `doc/compile/change_manifest.json`、`sim/source_changes.patch`：接续前后源文件变化。
- `sim/baseline/20261026_170442/`：修改前的源码/文档快照与 SHA256。
- `sim/compile.log`、`sim/sim.log`、`sim/sim_result.json`：最终 ModelSim 整机运行的兼容副本。

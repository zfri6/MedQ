# MedQ 对现有 DEMO 的复用核对

2026-10-26，按用户指出的 `HX4S20_Contest_202606/2_Example/DEMO` 重新逐项核对。
现有同器件示例足以推进主链路硬件基线；不应把补齐全部原理图/资料当作所有离线工作的共同前提。

已据此实际生成 prj/constr/top.adc，40/40 个实际 top 端口 bit 静态检查通过，无 virtualIO。
pin_map 里另外两项 VGA 同步不属于本顶层。逐源映射见 prj/constr/pin_summary.md，SDC 仍是草案。
TMDS 已基于本机 EG4 ODDR 完成功能模型验证，见最新 td_report.md。

| MedQ 所需部分 | 已有参考 | 已核对内容 | 后续动作 |
|---|---|---|---|
| 基础板级 IO | HX_CESHI_EG4S_BORD/SONG.al、a.adc | 器件 EG4S20BG256；50MHz@R7，KEY/SW、LED、数码管、蜂鸣器逐引脚与 LVCMOS33 配置 | 优先作为基础引脚/电气配置基线，记录端口重命名 |
| HDMI 单屏 | 31_hdmi_tx_display_B/source_code/adc_sdc/hdmi.adc、prj/al_ip/clk_wize.v | 四根 HDMI P 端，LVDS33；50 -> 125/25MHz 厂商 PLL | 复用原约束、频率配置及硬件串化资料，补 lock 与 MedQ 符号流适配 |
| SD SPI | 18_sd_card_audio/sd_card_audido.adc | SCLK=A14、MISO=B14、MOSI=A13、CS=A12，LVCMOS33 | 按 MedQ 端口名映射，保留原始参考 |
| UART | 16_uart_rs232/uart_test.adc | 与已有 extracted_facts 引脚来源一致 | 原约束映射后验证实际串口通信 |
| TD 真实器件选择 | 0_cnt1s 和 31_hdmi_tx_display_B 的 *_Runs/syn_1/settings.cfg | device_name=eagle_s20.db；package_name=EG4S20BG256 | 已据此完成本机导入验证 |

`31_hdmi_tx_display_A/B` 带有已有 `.bit`，可在连接板卡后用于独立验证匹配示例的下载/显示链路；这类结果须标为 DEMO 实板结果，不能算 MedQ 实板验收。

## 示例没有补齐的部分

- 对目录中 `.v/.vhd/.sv/.ipc/.tcl/.md` 检查 `EG_PHY_SDRAM|sdram|ras_n|cas_n|refresh_cmd`，没有找到可复用的 SDRAM 控制器实现。
  这表示本地这些未加密文本中没有发现；不能排除未随包提供的工程或加密设计内部另有实现。
- TD 安装内能找到 `EG_PHY_SDRAM_2M_32`，但其接口是 SDRAM 命令/数据管脚，仍需上层初始化、刷新与突发控制。
- 两套 HDMI 示例的现有约束仍仅覆盖当前这一组 HDMI P 端；未由它们确认第二物理接口的可用引脚与方向。
- 没有找到本项目用户数据 Flash 的芯片型号和引脚配置。

因此，原理图/额外参考工程用于补这几项具体缺口和解决少数冲突，不要求用户重复提供已有 DEMO 能证明的内容。

## 当前真正先阻塞 TD 综合的事项

本机实际执行真实 audio_sample_clk 模块综合，在 optimize_rtl 报 `RUN-8008 ERROR: License expired!`。
先解决有效 TD 授权；同时可继续进行基于 DEMO 的源文件、约束映射与硬件适配准备。
原始记录见 `prj/td/preflight/synth_probe.log`，推进顺序见 `doc/compile/td_bringup_plan.md`。

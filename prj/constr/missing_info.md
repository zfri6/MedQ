# MedQ 约束进度与剩余缺口（2026-10-26）

已按同型 DEMO 原属性生成 top.adc：实际 top 的 40 个端口 bit 全覆盖，静态检查 40/40、0 问题，无 virtualIO/重复位置。
旧 pin_map 的 42 项包含未使用的两根 VGA 同步信号。原始来源、端口重命名与 SHA256 见 pin_summary.md 和 extracted_facts.json:main_port_baseline。

SDC 仍为草案：50 MHz 输入和现有视频 PLL 的时钟推导已写入，真实存储 PLL、完整 CDC/复位例外和外部 IO 时序尚需核对。
未用全局 false path 或互斥时钟组屏蔽工作路径。

真实 medq_pll 已由 TD 生成，三路 125/25/100 MHz、共同 extlock；SDC 对新层次使用 derive_clocks，实际解析通过。
剩余事项：结合真实 SDRAM 复查最终时钟/CDC/IO 关系；经 TD 检查实际差分输出、Bank、全部 IO 和 setup/hold。
沿用匹配 DEMO 的电气配置不等于独立测量 Bank VCCIO，若出现具体冲突再依据本板原理图/引脚表解决。
第二 HDMI 的方向/管脚、用户 Flash 型号/管脚/可擦写区仍未由现有 DEMO 覆盖。

ADC 静态覆盖通过不等于可下载位流；实施门禁见 prj/td/hardware_readiness.json，当前位流/实板均未验收。

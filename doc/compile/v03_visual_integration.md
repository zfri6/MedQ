> 历史修订记录。当前双室独立开关/姓名占位以 independent_switch_delivery.json 和当前 README 为准。

> 此为上一视觉修订的历史记录。当前SW1/C-D修订以sw1_cd_integration.md、sw1_cd_delivery.json及v03_report.md为准；旧暂停帧身份约束已按新需求迁移。

# V0.3 视觉修订集成记录

2026-10-31 接收 HANDOFF 后，冻结视觉交接输入、旧版交付指针及旧 ZIP/位流校验。原 V0.2、2026-10-30 密封包与位流保持不变。

## 审查与修复

- 字体恢复原生 2bit 四级覆盖度，生产字库 4096 字，全窗口与完整 HEX 一致；图集中 1/3、2/3 覆盖分别为 5173、5207 像素。12288 个窗口外字不变。
- 业务、音频、CDC、存储、PLL、引脚和时序约束未改；源边界审查见 v03_visual_source_audit.json。原冻结行为规格保留，视觉差异写入 doc/spec/visual_amendment_20261031.md。
- 首轮 39/39 ModelSim 和真实控制器仿真通过，但原生像素域 12 条 setup 端点不满足，WNS -1.801ns。拒绝生成交付位流。原始失败报告已复制到 visual_timing_rejected_20261031/，失败 run 完整保留。
- 根因是过程化圆角背景的多级平均与几何/字模选择链。按已知底色独立混色、互斥面板分支、12bit 有符号精灵坐标修复；不改变时钟、约束、像素流水、图集、布局或配色。
- 新增 tb_dual_ui_visual_equivalence：将视觉代理交接的原场景和原布局冻结为独立 reference，逐拍比较六个场景输出；五个完整 640×480 扫描、全部 912 个字幕位置、呼吸/闪烁、最大计数和服务状态通过。两张单元 PPM 与修复前逐字节相同。
- 自检参考模型初次编译遇到 ModelSim 对 TB 本地 include 路径解析差异，改为内嵌冻结布局；不修改生产布局或工具搜索路径。随后自检通过。
- tb_dual_ui 额外断言两个部分覆盖度等级、生产图集地址/列范围，以及全部动画寄存器暂停。

## 当前权威结果

最终结果以 v03_report.md、v03_status.json 和 deliverables/latest_v03.json 为准；本记录不替代最后同源完整回归、双角 STA、fresh bitgen 与封装校验。

board_test: not_tested；没有进行下载或实板验收。

## 最终本机签核

40/40 ModelSim、三项真实控制器整机、控制器/真实PLL/带宽和串行器全部通过；修复后 12 张整机 PNG 与修复前的视觉设计逐字节一致。

严格原生双角 setup WNS +0.217ns、hold WNS +0.030ns，TNS 均 0、违例端点 0；LUT 15338/19600、BRAM9K 42/64、DSP 20/29、Slice 89.11%。STA 覆盖率 99.83%；42 项本地 I/O hold 边界沿用既有合同，内部/SIP 检查保留，55 个 SDRAM 绑定不变。

本轮严格签核 `doc/compile/timing_closure/20261030T182644Z_9114b49b/signoff.json`；fresh STA 后新位流 `MedQ_v0.3_UI_20261030T183319Z.bit`，SHA256 `873cd18c39ab687babdaef70420280419598f6836a7dcce8872f2291b8d80249`。原生实现驱动保留 REVIEW_REQUIRED 状态；独立严格签核与 fresh bitgen 均 PASS，没有改写原始运行结果。封装与校验以 deliverables/latest_v03.json 和 ZIP 内 DELIVERY_MANIFEST.json 为准。

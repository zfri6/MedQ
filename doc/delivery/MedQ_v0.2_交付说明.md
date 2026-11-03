> 2026-10-27 时序闭环已另行完成，以下保留为原交付历史记录；当前结论见 `doc/compile/timing_closure/summary.md`。

# MedQ v0.2 交付说明

完整新版工程位于MedQ_v0.2，可独立运行。压缩包在deliverables/MedQ_v0.2_20261027.zip，相邻.sha256；包内DELIVERY_MANIFEST.json逐项记录源码和证据哈希。baseline/v0.1保留原版压缩包，打包脚本还核对父目录原v0.1未被修改。

30/30 ModelSim通过；带原SDRAM控制器的正常业务及无卡基础叫号通过。六种状态画面和16帧叫号动画见sim/ui/MedQ_v02_preview.html，关怀模式间隔30帧图像一致。

gate LUT76.13%、REG44.40%、BRAM90.62%、DSP86.21%、PLL50%；实际布局布线完成，物理Slice94.78%。setup/hold有负slack，所以没有可下载位流，没有实板结论。

使用方式与复现命令见README.md，技术设计、原生TD报告和后续路径见doc/compile/v02_report.md。固件不依赖电脑界面运行，预览HTML只用于查看真实RTL捕获，不是产品控制台。

未完成项：STA与完整约束、真实TF素材编号清单、Flash持久化、双屏、完整诊断、实板下载。项目TD技能“同一问题最多3轮”的三次新版本实现已保留；不能用仿真代替这些验收。

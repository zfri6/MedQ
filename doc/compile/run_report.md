# MedQ 仿真运行报告

2026-10-26：主业务行为仿真验收通过，ModelSim 与 Icarus 各 17 项，共 34/34 PASS。

推荐复现：`python sim/run_regression.py --sim modelsim`。
两工具复现：`python sim/run_regression.py --sim both --timeout 600`。

完整场景、历史墙钟超时、工具版本、逐项结果和未验收范围见 [验收记录](check_report.md)。
机器结果见 `sim/regression_result.json`；逐项日志见 `sim/tests/`；图像比对见 `sim/frame_verification.json`。
没有生成 VCD；整机像素捕获保存在 `sim/tests/modelsim/tb_top/top_frame.png`。

这些结果不构成真实安路 IP、TD 时序/资源、位流或上板成功证据。

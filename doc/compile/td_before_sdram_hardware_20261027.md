# MedQ 当前 TD 状态（2026-10-26）

**授权有效，当前顶层完成综合；尚未生成MedQ.bit，未布局布线或下载实板。**

| TD gate资源 | 当前使用 | 器件容量 | 占比 |
|---|---:|---:|---:|
| LUT | 13753 | 19600 | 70.17% |
| REG | 7536 | 19600 | 38.45% |
| BRAM9K | 31 | 64 | 48.44% |
| BRAM32K | 0 | 16 | 0% |
| DSP | 19 | 29 | 65.52% |
| PLL | 1 | 4 | 25% |

原始结果：prj/td/runs/20261026T125128Z_208d57fe/result.json；该目录保留日志、输入SHA256、面积和门级DB。
当前RTL/VH/HEX/IPC与该次综合输入哈希一致。

资源优化前为LUT19487（99.42%）、DSP29（100%）；本轮保留UI/时序/端口，优化像素运算、投影历史、FAT地址并实现共享Goertzel。
详细改动、三轮面积对比和验证边界见 [resource_optimization_report.md](resource_optimization_report.md)。
ModelSim当前22/22 PASS，95项源码/数据哈希匹配，20张UI完整帧与优化前SHA256一致。

## 硬件缺口

- SDRAM仍为硬件占位，init_done/ready为0，部分缓存/显示/音频数据路径会被裁掉；当前资源不是最终完整硬件用量。
- 异步FIFO实际RAM映射、字体初始化内容、CDC/复位/外部IO时序还需审查。
- 尚无setup/hold、未约束路径与布局布线验收，不能由gate综合PASS推断时序通过。
- 板卡此前确认暂未连接，本轮未进行下载、Flash擦写或实板观察。

当前implement/bitgen仍由prj/td/hardware_readiness.json的真实缺口阻止。

## 已通过的前置检查

- TD授权探针：prj/td/runs/20261026T114453Z_f664e707/。
- TD GUI已打开同格式ASCII MedQ.al；新medq_pll由实际IP Generator生成，50 -> 125/25/100 MHz，extlock统一控制复位。
- PLL原语模型：sim/vendor_pll/20261026T120411Z/；DDR串化模型：sim/vendor_serdes/20261026T112656Z/。
- 40bit ADC按同型DEMO映射；新SDC derive_clocks实际解析通过，完整约束仍为草案。
- 构建判定13项检查包括错误/缺报告/崩溃/资源超限与未知面积格式；退出码0不直接代表成功。

授权复测和首次综合的原始记录已保留，前一轮说明在td_before_resource_optimization.md。
复现入口：prj/td/README.md，主命令为python prj/td/medq_td.py --mode synth --run --timeout 300。

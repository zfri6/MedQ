# MedQ TD 授权复测与综合进展（2026-10-26）

**授权已生效；当前真实顶层已完成综合。尚无 MedQ.bit，未布局布线或实板下载。**
当前 SDRAM 硬件分支仍是 ready/init_done=0 的占位，因此部分数据路径会被优化掉；以下面积只是当前源码基线，不能当最终硬件用量。

| 项目 | 实测结果 | 证据 |
|---|---|---|
| 授权复测 | 真实 audio_sample_clk 完成 optimize_rtl / optimize_gate，有面积报告和门级 DB | prj/td/runs/20261026T114453Z_f664e707/result.json |
| 新 PLL | TD IP Generator 6.2.168116 实际生成 medq_pll.v/.ipc，50 -> 125/25/100 MHz，导出 extlock | rtl/al_ip/medq_pll.v、prj/td/pll_generation.json |
| PLL 模型 | 原始 EG4 模型，频率/锁定/复位/重锁 PASS | sim/vendor_pll/20261026T120411Z/result.json |
| GUI 工程 | TD 已打开同格式 ASCII MedQ.al，显示 EG4S20BG256、源层次、两份约束 | 本轮实际界面观察；完整实现流程未验收 |
| 优化前综合 | 完成，但 LUT 37341/19600=190.52%，容量不合格 | prj/td/runs/20261026T120149Z_735bbdbb/reports/MedQ_gate.area、capacity_review.json |
| 优化后综合 | 完成，LUT 19487/19600=99.42% | prj/td/runs/20261026T121030Z_e2309814/result.json |
| FAT32 边界 | 第 127 个 FAT 项、碎片跨簇、最后字节与 done 同拍、反压等 PASS | sim/tests/fat32_bram/boundary/sim.log |
| 主业务回归 | 当前 ModelSim 18/18 PASS，Verilog-2001 门禁通过 | sim/regression_result.json |
| SDC 解析 | derive_clocks 替代弃用命令后，实际 top/ADC/SDC 解析 PASS；完整约束仍未验收 | prj/td/runs/20261026T121539Z_945cc06d/result.json |
| 构建判定测试 | 13 项 PASS，含容量超限/未知面积格式处理；不是 FPGA 综合证明 | prj/td/preflight/flow_unit_tests_after_license.log |

## 当前真实资源报告

| TD gate 资源 | 使用 | 器件容量 | 占比 |
|---|---:|---:|---:|
| LUT（Utilization Statistics） | 19487 | 19600 | 99.42% |
| REG | 10182 | 19600 | 51.95% |
| BRAM9K | 31 | 64 | 48.44% |
| BRAM32K | 0 | 16 | 0% |
| DSP | 29 | 29 | 100% |
| PLL | 1 | 4 | 25% |

没有面积溢出不等于能成功放置、布线或时序收敛。LUT 只剩 113，DSP 无余量；真实 SDRAM/缓存通路接入后必须再次优化和评估。
当前不能把综合成功标为可下载版本。

## 本轮具体改动

- 由本机 TD GUI 的 IP Catalog / PLL 向导实际生成新 wrapper 与 ipc，原字节复制到 rtl/al_ip。
  同颗 PLL 输出 125/25/100 MHz、相位配置均为 0 deg，共同 extlock 控制各域复位。
  SIMULATION 保留原行为时钟配置；旧 clk_wize 与 FIFO 厂商 wrapper 均未改动。
- 原语模型验证测量每路至少 100 个周期、两次锁定轮次和复位失锁/重锁。
  原始 wrapper/model 的 load_reg 位宽产生两条警告，动态功能关闭且接常量零；保留原文件，不把警告隐藏。
  第一轮因脚本遗漏 BUFG 模型而失败，日志保留在 sim/vendor_pll/20261026T120336Z；补载原始 eg_logic_clk.v 后通过。
- FAT32 原缓冲存在大量并行可变索引读口，使该模块消耗约 19093 LUT。
  改为四 byte lane 的 128x8 同步 RAM，TD 确认映射 4 块 BRAM；目录项先读 8 个 word，再解析。
  MBR/BPB 在 SD 字节流上捕获所需标量字段。字节输出含预取间隙，valid/ready、内容、顺序、长度和错误语义保持。
  该模块报告 LUT 列降到 1256，整机利用率从 190.52% 降到 99.42%。
- 原素材 TB 的错误打印仍引用旧 sector_buf 层次，导致一次加载失败；已更新诊断引用，原日志保存在 sim/baseline/td_fat32_20261026。
  随后完整素材、缩放、19 PCM、队列、UI、HDMI、串化和整机 18 项回归通过。
- ADC 仍是按同型号 DEMO 映射的 40 个实际顶层 IO，静态覆盖已通过，无 virtualIO。
  SDC 改为新 PLL 层次和 TD 当前 derive_clocks 命令，解析通过；CDC、复位与外部 IO 时序仍需逐路径审查。

## 继续推进的真实缺口

1. SDRAM 控制器：已有 EG_PHY_SDRAM_2M_32 物理原语，但 wrapper 的硬件分支仍未绑定初始化、刷新、读写控制。
2. 资源余量：补入 SDRAM 与实际缓冲通路前后继续优化；不能用当前常量占位裁掉的逻辑换取最终资源通过。
3. 完整 SDC、RAM/初始化内容、CDC、布局布线后的 setup/hold 和未约束路径审查。
4. 完整链路真实 IP 仿真、MedQ.bit 生成及校验，随后连接实板做 SRAM 下载、显示/音频/存储自检。
5. 配置 Flash 冷启动、用户数据 Flash、双屏与完整诊断按独立阶段验收。

前置项见 prj/td/hardware_readiness.json。当前 implement/bitgen 仍被这些实际缺口阻止，未用授权成功或行为仿真代替硬件验收。

## 复现入口

```powershell
python prj/td/medq_td.py --mode synth --run --timeout 300
python sim/run_vendor_pll.py
python sim/run_vendor_serdes.py
python sim/run_sim.py --sim modelsim --run --tb-top tb_fat32_reader --define FAT_BOUNDARY --output-dir sim/tests/fat32_bram/boundary
python sim/run_regression.py --sim modelsim --timeout 300
```

资源报告对应不变的当前 RTL；其后只更新了 SDC 的派生时钟命令，并以独立 analyze 运行验证。
门级优化成功无路由时序报告；不能引用这些 gate 面积报告声称最终 timing PASS。
旧授权过期、PLL 黑盒、容量超限、模型缺失等原始失败记录均保留，没有被改写成成功。

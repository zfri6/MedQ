# MedQ v0.2 时序闭环交付（2026-10-27）

**电脑端签核完成，位流已生成；未进行实板下载或实板验证。**

原始112个违例端点（91 setup、21 hold）已逐条归档并按根因修复。最终原生TD报告为 Routed，slow/fast两角均检查max/min，当前所有分析路径的setup/hold违例端点均为0。

| 项目 | 原v0.2 | 本次签核 |
|---|---:|---:|
| Setup WNS / ns | -5.565 | +0.604 |
| Setup TNS / ns | -248.083 | 0.000 |
| Hold WNS / ns | -1.528 | +0.023 |
| Hold TNS / ns | -22.742 | 0.000 |
| 物理LUT | 15210 | 13584 |
| 物理REG | 8853 | 8778 |
| 物理Slice利用率 | 94.78% | 82.58% |
| BRAM9K / DSP / PLL | 58 / 25 / 2 | 58 / 25 / 2 |

原生覆盖率为 **99.78%**，没有声称100%。所有内部寄存器与SDRAM的setup/hold保留；外部异步输入第一采样级和没有外部捕获时钟的输出，单独采用I/O本地最大延迟合同。TD将这些datapath_only预算展开为42条I/O边界hold排除，已逐条列入签核JSON；内部/SIP被排除时脚本会拒绝签核。没有显式false path、异步时钟组或内部多周期。完整边界见 [I/O合同](io_contract.md)。

## 根因及修复

- 50MHz系统时钟改由PLL全局输出驱动；PLL使用本机支持的原生VCO内反馈，消除外反馈补偿不确定性。
- 实际存储时钟改为50MHz，SDRAM转发时钟为+8ns/144°；像素25MHz、串行125MHz、音频48kHz及16kHz PCM三倍插值保留。初始化等周期等待变得更保守，刷新按50MHz重新计算为781周期。没有只修改SDC频率。
- SDRAM仍保留5ns的保守max输入/输出模型；写侧output-delay min=-1ns，修正正1ns器件hold的符号，较原生默认收紧2ns。55个内部SIP管脚的位置/电气属性与原始TD绑定逐项一致。
- 锁存原尺寸判定，拆开FIFO可用量/行长比较、地址合法性到ready的长组合链；采用area_prior/high pack/routability和原生fix_hold。
- 按真实控制器延迟修复启动预充：加载期显示确定底色，帧FIFO预充后在帧边界开取图；低水位显示读请求之间的周转拍也保留带宽；PCM起播预充期间静音，运行后的真实缺粮继续报错。

逐路径清单：[112条CSV](baseline_112_paths.csv)、[根因说明](path_repairs.md)、[完整原始负路径](baseline_full_negative.timing)。失败的诊断构建和旧交付包均保留；中间正slack候选不作为最终位流的验收证据。

## 验证

- 最终源码ModelSim全回归 **31/31 PASS**，含Verilog-2001语法门禁；新增PCM用例同时检查起播等待和真正的运行中欠载。
- 完整MedQ顶层使用原始加密SDRAM控制器、独立BL4/CL3存储体模型，完成SD SPI装载、UART ACK/NAK/CRC、按键消抖、三次叫号/CDC、27段PCM及完整画面捕获。
- 厂商真实PLL模型驱动的两帧压力测试：614400个像素逐点一致，同时处理3264个音频字和134070个持续积压写字；没有画面欠载。另有1311字的边界/掩码/背压/复位测试，以及无卡叫号/有限提示音/空闲静音测试。
- 独立SDRAM模型检查tAC=4.5ns、命令setup/hold、tRCD/tRP/tRAS/tRFC与初始化后刷新期限。它不是厂商存储体时序模型；安装包里的SDRAM模型为空壳，不能拿它当作物理存储验证。
- 厂商PLL频率/相位/复位重锁、厂商串行器模型通过；静态ADC检查40端口/40分配/0问题。21项工具负控制测试通过，不把这些单元测试当作STA证据。
- 最终数据库签核后重新导入同一SHA256的布线数据库，重报STA；bitgen前的进程内门禁再次检查SWNS/HWNS非负。

## 位流与复现

位流：`deliverables/MedQ_v0.2_timing_20261027.bit`（663380字节）。

SHA256：`bc9b6e628df321c344e34b44f0f3acb3987256946ebbc01230a91912ae2c9ceb`。

原生构建：`prj/td/runs/20261027T010053Z_86c0e883/result.json`。签核：`doc/compile/timing_closure/20261027T010053Z_86c0e883/signoff.json`。位流日志/新STA：`prj/td/runs/bitgen_20261027T010637Z_5b1c4c20/result.json`。

```powershell
python sim/run_regression.py --sim modelsim --timeout 300
python sim/run_vendor_sdram.py --system --timeout 300
python sim/run_vendor_sdram.py --system --system-tb tb_basic_calling --timeout 180
python sim/run_vendor_sdram.py --real-pll --timeout 300
python sim/run_vendor_sdram.py --bandwidth --real-pll --timeout 600
python sim/run_vendor_pll.py
python sim/run_vendor_serdes.py
python prj/td/medq_td.py --name MedQv02 --mode implement --run --timeout 1200
# 使用上一步新生成且通过检查的result路径；不续跑旧结果。
python prj/td/signoff_timing.py --result prj/td/runs/20261027T010053Z_86c0e883/result.json --bitgen
python sim/package_release.py --timing
python prj/td/seal_timing_release.py
```

交付包保留当前源文件、仿真/STA报告、最终布线数据库、位流、源码与产物哈希，并内含旧v0.2包和v0.1基线。冻结包禁止覆盖；再次发布须换新包名。

## 实板状态与功能边界

**实板未验证。** 本次没有下载、实测存储器、测量HDMI眼图/音频或执行长时间板测。I/O合同中的卡端延迟/走线预算属于外设使用条件。PLL组合功能测试显式施加启动复位，不能替代实板上电启动验证。

现有按键、UART、叫号、关怀模式、语音/缺卡提示、VGA/OSD等功能由上述回归覆盖。KEY2仍保留原状态计数，主界面仍单页；Flash持久化、第二屏、SD热插拔恢复和完整诊断不是本版完成项。TF真实素材映射的原有边界不变。

最终完整证据包：`deliverables/MedQ_v0.2_timing_closed_20261027_r1.zip`，另附同名SHA256和manifest。中间冻结包保留，不覆盖。

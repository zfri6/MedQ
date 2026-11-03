> v0.2当前状态请以根README与doc/compile/v02_report.md为准；以下旧日期内容为历史/原计划。新增UI改变了部分像素，不要求与v0.1的20帧全等。

> 历史报告：下文是2026-10-26的SDRAM占位基线，不代表当前用量。2026-10-27真实存储接入、RAM重构和打包失败见td_report.md与v0.1交付说明。

# MedQ 资源优化与验证（2026-10-26）

当前实际 TD gate 资源：LUT **13753/19600（70.17%）**、REG **7536/19600（38.45%）**、
DSP **19/29（65.52%）**、BRAM9K **31/64（48.44%）**、PLL **1/4**。
ModelSim 默认全回归 **22/22 PASS**、Verilog-2001 门禁退出0；当前源码/数据哈希全部匹配。
20张完整UI帧与修改前SHA256相同。

这仍是未接入真实SDRAM的顶层综合基线。SDRAM占位会裁掉部分数据路径；尚无布局布线、时序、MedQ.bit或实板验收。

## TD 实测对比

| 阶段 | LUT利用量 | REG | DSP | BRAM9K | 原始运行 |
|---|---:|---:|---:|---:|---|
| 本轮修改前 | 19487（99.42%） | 10182 | 29 | 31 | 20261026T121030Z_e2309814 |
| 等价位宽/显示/地址计算优化 | 14520（74.08%） | 6914 | 29 | 31 | 20261026T123711Z_46707acc |
| 加入共享Goertzel | 13753（70.17%） | 7536 | 19 | 31 | 20261026T125128Z_208d57fe |

本轮净减少5734 LUT、2646 REG、10个DSP；LUT余量由113增至5847，DSP余量由0增至10。
上表采用TD Utilization Statistics的#lut口径；不是另一个#Total_luts表，也不是放置后的最终物理资源。
各模块DSP会随可用资源重新映射，局部节省不能简单相加成整机节省。

机器结果：`sim/resource_optimization/benchmark.json`。
原始面积：`prj/td/runs/20261026T125128Z_208d57fe/reports/MedQ_gate.area`，同目录保存日志、输入SHA256和门级DB。

## 具体改动

1. **像素数学保持精确。** 混色总和范围0..65152，用`(v+1+(v>>8))>>8`精确替代除255。
   AA覆盖率、透明度、BC与中间乘加位宽按值域收窄，未用近似颜色换资源；输出流水拍数不变。
2. **UI减少重复算术。** easing的lift/进度宽度使用原公式逐值等价查表，坐标/atlas/数字索引收窄。
   原字体ROM、字号、圆角、呼吸和转场外观保留。20张640×480 RTL捕获逐字节一致。
3. **历史缓冲存储投影坐标。** 波形原始16-bit样本改为保存旧公式算出的显示位置，避免历史读端重复计算。
   spectrum_render序列寄存器从3602降到274；所有采样码及模式输出与冻结RTL对照。
4. **低频控制计算移出永久乘法器。** FAT32每簇扇区数已被BPB限制为2的幂，改用移位；
   FAT数量×大小只在挂载阶段用8拍shift/add。该模块DSP由4降至0，mount_done增加8拍，公开LBA相同。
5. **频谱真正分时复用。** 原模块文字写“单乘法器”，TD实际占17DSP，且状态复位、系数和功率流水未正确实现。
   现在共享一个注册32×32乘法运算，TD映射为4个DSP block；不能将“一次乘法运算”误写成“一个DSP”。
   signed32状态支持满幅16-bit PCM，修正系数表/符号/复位/块清空/功率及包络。数值不是与旧未验收算法的等价替换。

## 验证证据

| 检查 | 激励/依据 | 结果 |
|---|---|---|
| UI完整帧 | 修改前快照中的20张原始PPM，与当前捕获逐SHA256比较 | 20/20相同 |
| 像素数学 | 完整除255输入域、coverage/opacity、混色与BC边界；冻结旧函数作参考 | 917121次通过 |
| 波形历史 | 全65536采样码、环绕、复位、所有原模式，逐拍冻结RTL对照 | 通过 |
| FAT地址 | spc=1..128、FAT数量1/2/3/255、32bit乘积模溢出；比较公开SD请求和字节 | 32组通过 |
| Goertzel | Python独立整块定点数学参考，3072采样/192bin | 12块通过 |
| Goertzel边界 | 静音、满幅正负DC、三种单频、多频、噪声、脉冲、部分块复位、忙时额外stb、包络与输出间隔 | 通过，无X |
| 主业务回归 | 原18项加4项新自检，含素材/完整缩放/19PCM/队列/CDC/UI/HDMI/整机 | ModelSim22/22 |

UI帧证据：`sim/resource_optimization/ui_equivalence.json`；数学参考：`spectrum_reference.json`。
冻结参考RTL仅改模块名，原始来源与SHA记录在`sim/baseline/resource_20261026/reference_manifest.json`。
修改前源码、面积报告和20张帧保存在同目录`before_optimization.zip`及SHA256；旧Goertzel另存为`goertzel_before_tdm.v`。
逐测试日志与当前源哈希在`sim/tests/modelsim/`、`sim/regression_result.json`。

## 处理预算与公开接口

Goertzel默认16bin，每次递推32个clk_pix，块末输出128个clk_pix，总共最坏160拍=6.4us。
正常48kHz样本间隔约520/521拍，处理预算充足；忙时多余stb按契约忽略并已测试。
输出bin依次0..15，间隔8拍；每256采样输出一组，块结束清空内部状态。
参数/公式和能量归一化见`doc/spec/behavior_spec.md`。主音频播放和公开端口不变。

## 仍未关闭的范围

- 当前波形历史优化有意保留旧RTL投影的位宽/符号语义。对照通过不代表旧文档所写的±40px投影或柱图坐标已正确实现；完整诊断显示另行验收。
- 真正SDRAM控制器、异步FIFO的实际RAM映射、初始化内容与完整数据路径资源仍需闭环。
- 下一步在真实SDRAM/FIFO接入后重测资源，并做CDC/SDC、布局布线和setup/hold检查；不以本报告代替实板验收。

## 复现

```powershell
python sim/run_regression.py --sim modelsim --timeout 300
python sim/check_ui_resource_equivalence.py
python prj/td/medq_td.py --mode synth --run --timeout 300
```

数学夹具可由`python sim/build_spectrum_vectors.py`重建；该脚本不读取RTL结果作为期望值。

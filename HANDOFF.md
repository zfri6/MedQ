> 当前交付：2026-11-01事件字幕，详见doc/compile/marquee_events_delivery.json与最新deliverables/latest_v03.json。先前各节为历史。

> 当前版本：2026-10-31 双室独立开关/三星号姓名占位修订。当前证据见 doc/compile/independent_switch_delivery.json；先前各节为历史交接。

> 当前交付已加入SW1仅控叫号与C/D回诊票修订，见第8节及doc/compile/sw1_cd_delivery.json；原视觉代理交接和第7节为此前修订记录。

# MedQ V0.3 前端视觉重设计 HANDOFF（2026-10-30）

本轮只改前端视觉，不涉及业务逻辑。**没有运行 TD，没有生成位流，也没有上板**；资源、时序和实板效果都没有验证。V0.2 目录未改动。

## 1. 改动文件
| 文件 | 改动 |
|---|---|
| `rtl/medq_dual_ui_scene.v` | 重写 640×480 页面：顶栏、A/B 双字幕、两张诊室卡、导诊图；圆角带半覆盖度边缘；新增按帧更新的动画寄存器（呼吸、新呼叫闪烁、颜色插值） |
| `rtl/medq_dual_layout.vh` | 由脚本生成：精灵表、比例字宽表、圆角切边表 |
| `rtl/osd_renderer.v` | 删掉 V0.3 的 1 bit 单色分支（`scene_mono_q`），两种场景都走原有的 `covered()` 四级覆盖度混合；端口和两拍延迟不变 |
| `rtl/font_v03.hex`、`rtl/font_rom.hex` | 虚拟地址 3584..7679 窗口换成 256×256、2 bit 覆盖度图集；`font_rom.hex` 的 0..3583 和 7680..16383 逐字未变（已比对） |
| `sim/build_dual_font.py` | 重写成图集生成器：Noto Sans SC Medium/Bold 和 Bahnschrift SemiBold，4× 超采样，伽马 0.8 量化到四级，用天际线算法装箱 |
| `tb/tb_dual_ui.v` | 参考模型从单色比较改成四级覆盖度混合；新增断言：部分覆盖像素数必须 ≥1000（防止被二值化） |
| `sim/ui/v03_font.json`、`sim/ui/v03_font_atlas.png` | 由脚本生成的图集说明和可视化 |
| `sim/ui/v03_redesign/` | 视觉规格 `VISUAL_SPEC.md`、预览 harness `ui_preview_tb.v`（不在 `tb/` 下，不会被回归收录）、出图脚本 `make_figures.py`、预览图和放大图 |

没有改动：`top.v`（4K 窗口寻址照旧 `font_addr-3584`）、`font_rom.v`、队列/医生/暂停/音频/CDC/存储/时序相关的所有模块和约束。

## 2. 设计理由
- **原来难看的根本原因**：V0.3 把中文二值化成 16×20 的 1 bit 字模（阈值 112），大号码复用的是 Consolas 32×48 的 1 bit 等宽字，所以边缘有锯齿、字距松散、“0”带斜杠、“1”两边空。
- **在零新增 BRAM 的前提下恢复抗锯齿**：生产 ROM 仍是原来那块 4096 字的窗口，整块改成和 V0.2 同格式的 2 bit 图集（每字 16 像素、MSB 在左）。旧的大号字形和单色中文都不再需要。
- **两室用两种主色**（A 青绿、B 蓝）：远处只看颜色就能分清诊室；导诊图用同样的颜色，并显示正在呼叫的诊室的路线。
- **层级**：号码字高从 48px 等宽字变成约 47px 的 SemiBold 比例字；状态改用胶囊，配色为语义色；计数做成统计块。卡片底部空白缩到 16px 的边距。
- **修正了一个文案问题**：原来诊室空闲时字幕一律显示“暂无候诊”，即使队列里有人。现在队列非空时显示“即将叫号”（依据 `QSTATE` 的计数字段，只是显示层面的判断）。

## 3. 字体与抗锯齿方式
- 2 bit，四级覆盖度 0/⅓/⅔/1，由 `osd_renderer.covered()` 和背景色做精确混合（`medq_div255`）。字模没有任何 1 bit 化。
- 原生尺寸栅格化，像素路径上不做放大。号码字体先 4× 超采样，再用盒式滤波缩小。
- 字形先按墨迹裁切，再用显式字距排比例字宽；混排时按基线对齐。A01/A09/A10/A99/B01/B99 的实际渲染见 `preview_states.png`。
- 字号和字重表见 `sim/ui/v03_redesign/VISUAL_SPEC.md` 第 3 节。

## 4. 已做的检查（本机 Icarus Verilog 12，不是 ModelSim 回归）
- `tb_dual_ui`：PASS。614400 像素和独立的覆盖度混合参考逐一一致，其中 8466 个是部分覆盖像素；滚动速度为 1px/2 帧且两室独立；回绕在 0..911 内；x=23 和 x=616 不出字；暂停期间 `frame_state`、`scroll_a/b`、`frame_service` 不变。
- `tb_font_window`：PASS。4096 字和完整 ROM 的窗口逐字一致。
- RTL 语法：`iverilog -g2001 -Wall` 没有新增告警。
- **没有跑**：完整的 39 项 ModelSim 回归、`tb_top` 和 vendor SDRAM 系统仿真、TD 综合/布局布线/STA/bitgen。

## 5. 预览与放大图（都是 RTL 实际像素经 PPM 转 PNG，不是实板照片）
- `sim/ui/v03_redesign/preview_640x480.png`：主预览（A01 呼叫中，B01 就诊中）。
- `preview_states.png`：5 个场景（空闲/加载中、A01+B01、A09+B99 且 B 取号拒绝、A10 重呼+B 即将叫号、A99+B01 新呼叫闪烁且存储异常）。
- `font_edge_zoom.png`：改前和改后同一区域最近邻放大对比；`font_edge_zoom_12x.png` 是 12 倍单字边缘。
- 重新出图的步骤：在临时目录里用 iverilog 编译 `sim/ui/v03_redesign/ui_preview_tb.v`、`rtl/osd_renderer.v`、`rtl/medq_ui_scene.v`、`rtl/medq_dual_ui_scene.v`、`rtl/font_rom.v`（`-I rtl`，并把 `font_v03.hex` 复制过去），然后运行 `python sim/ui/v03_redesign/make_figures.py <ppm目录> <改前ppm> sim/ui/v03_redesign`。

## 6. 已知限制和需要负责人确认的事项
1. **资源和时序没有验证**：像素路径上的组合逻辑比原来多（约 40 个精灵的比较器、圆角判断、字幕分段加法链），但去掉了原来的 `/10 %10 /32` 除法。LUT 和 25MHz 时序都要由下一轮 TD 实测确认。BRAM 预期不变（仍是那块 4K 窗口）。
2. **冻结文档中有几处描述已经过时，但我没有改**（这些文件受 sha256 或契约冻结保护）：`doc/spec/behavior_spec.md` 里“5504..8191 存中文单色字模、复用大字”，以及 `doc/arch/interface_contract.yaml` 里 `osd_renderer_amendment: …dual_scene_uses_mono_MSB_left`。实际实现现在是 2 bit 覆盖度图集，需要负责人决定是否修订契约。
3. **旧证据失效**：`doc/compile/v03_font_window_equivalence.json` 和 `sim/ui/v03_rtl/` 里记录的帧 SHA256 对应旧页面，下次系统仿真后需要重新采集。
4. 字幕复位位置从 592 改为 572（新文字起点从 x=24 移到 x=44，避开新增的边缘渐隐区）。速度、0..911 范围、x24..615 窗口和暂停冻结都不变；`tb_top` 只比较暂停前后的滚动值是否相等，不受影响。
5. `font_rom.hex` 的 3584..5503（原来 legacy OSD 字段用的 32×48 大字）已被覆盖。生产顶层不用这段，单元测试 `tb_osd_renderer` 用的是自带的假字模；如果以后要在完整 ROM 上用 legacy 的配置字段显示大字，需要另外规划地址。
6. 图集已经用满 256/256 行，新增文案需要先删短别的标签，或者扩大窗口（窗口扩大会改 BRAM 和 `top.v`）。
7. 字体依赖本机的 Noto Sans SC 和 Bahnschrift（脚本里是 Windows 字体路径）；日常仿真只用已保存的 HEX，不需要这些字体。
8. 导诊图仍是示意，不代表真实医院布局。

## 7. 接收方完成本机集成（2026-10-31）

接收方已完成 40/40 ModelSim、真实控制器整机/长音频/无卡、PLL/带宽/串行器验证。修复像素混色链的真实时序问题，1542408 次独立场景输出比较和 12 张整机帧确认视觉不变。

双角原生 STA：setup +0.217ns、hold +0.030ns，TNS=0；LUT 15338/19600、BRAM9K 42/64、DSP 20/29。新位流 `MedQ_v0.3_UI_20261030T183319Z.bit` 已通过 fresh STA 后生成。

第 6 节的时序、契约与旧截图限制已由本轮签核、视觉补充契约和新整机截图处理；完整证据见 doc/compile/v03_visual_integration.md、v03_report.md。交付包及位流以 deliverables/latest_v03.json 为准。board_test: not_tested，未下载。

## 8. SW1/C-D修订最终交付（2026-10-31）

- SW1关闭仍可四类取号、办理到位/离开，人数和两条顶部字幕继续更新；停止首次/重呼、等待计时和播放进度，静音。
- A/B普通与C/D回诊四类分别01..99；C到A诊室、D到B诊室，严格回诊优先不变，完整事务键带类别。
- 4K四级覆盖度图集新增C/D字形，原字号和A/B像素覆盖度保留；21段PCM必须同步部署到空FAT32根目录，CLIP00..20按序复制。
- 41/41完整ModelSim、真实控制器三类整机、最终两角STA与fresh bitgen均通过。Setup +0.166ns / hold +0.024ns，TNS=0。旧包与旧位流保持原字节。
- 新位流：MedQ_v0.3_SW1_CD_20261031T072250Z.bit；交付包及SHA见deliverables/latest_v03.json。board_test: not_tested，未下载。


## 9. 双室独立开关与姓名占位最终交付（2026-10-31）

SW1/SW2分别低有效允许A/B叫号，SW3/SW4分别为A/B医生双边沿到位/离开；取号和画面始终实时。
停止当前语句会安全排空并让另一室继续，重开同患者重播不计新次数；医生取消使旧语句失效。
字幕请A01***到A诊室就诊 / 请B01***到B诊室就诊，C/D回诊目标仍为A/B。
原21段PCM和其余74个sprite覆盖度字节不变。当前操作见doc/spec/operation_v03.md。

完整ModelSim 43/43，Verilog-2001门禁、真实控制器三种顶层模式、28项签核工具测试均通过。
原生slow/fast setup/hold WNS +0.272/+0.030 ns，TNS为0，全部组违例端点为0。
新位流：deliverables/MedQ_v0.3_AB_SWITCH_NAME_20261031T091534Z.bit；SHA256 da1bc43623414b449c781c6385f55a8c9c68840aea28a1e9fff83aee9722b392。
签核：doc/compile/timing_closure/20261031T090319Z_eda3774b/signoff.json；详细结果：doc/compile/independent_switch_delivery.json。
封包和真实解压逐文件校验由deliverables/latest_v03.json及seal_summary.json记录。board_test: not_tested。


## 10. 事件字幕最终交付（2026-11-01）

用户确认每次操作显示对应提示。A/B独立字幕在下一帧从x24显示，分别重置滚动相位；
取号、回诊取号、拒绝、启停、叫号/重呼/实际恢复开播、到位、离开、过号均有对应内容。
同室帧间多事件显示最新操作，另一室不重置；离开/过号保留原患者号，三个星号为姓名。
原75个sprite与完整legacy字体字节不变，8个新增AA sprite使用第二页；生产ROM8192字。
开关映射、队列和21段语音素材保持前版。

ModelSim 45/45、Verilog-2001、真实SDRAM三种整机模式、36项签核工具测试通过。
原生slow/fast setup/hold +0.180/+0.030 ns，TNS0、全部组违例端点0。
位流：deliverables/MedQ_v0.3_EVENT_SUBTITLES_20261101T154133Z.bit；SHA256 4a3cf25b692f34a617f1ff273073e50a5a16554dc327706ead0fcca473fa1362。
签核：doc/compile/timing_closure/20261031T165816Z_53136168/signoff.json；当前详细结果：doc/compile/marquee_events_delivery.json。
封包以deliverables/latest_v03.json为准。board_test: not_tested。


## 11. 全名语音与姓氏显示（2026-11-02）

# MedQ V0.3 全名语音与姓氏显示（2026-11-02）

电脑端签核通过；未上板。ModelSim完整46/46，另有2项源绑定专项仿真及36项签核器测试。
全部30名患者按assets/patients.json映射；保留A/B初诊、C/D回诊的独立01..99号。C01=张伟民、A01=赵敏华、D01=马宁远、B01=杨帆宇；名单外为“患者”。
语音播完整姓名与当前实际号码；屏幕仅显示姓氏，例如“请C01张到A诊室就诊”。396种01..99呼叫的3564片段、32076个实际PCM输出样本比对通过；30个姓氏的2012800个像素比对通过。
原语音按FAT目录出现顺序索引，复制顺序会错配。新版本按CLIPnn.PCM精确定位，已验证逆序、多根簇、缺失、未知、重复ID；未读取用户实卡，不能断言旧板固定数字的唯一原因。
54段PCM总计2797778字节，原21段字节不变；新增30个姓名与号/到/患者。必须与新位流配套更新卡。音频经HDMI；蜂鸣器仍仅有限降级提示音。

## 操作与素材
K1/K2/K3/K4分别A初诊/B初诊/A回诊/B回诊；SW1/SW2低有效允许A/B叫号，SW3/SW4医生双边沿到位/离开。队列、严格回诊优先、三次叫号、暂停计时/安全排空、恢复同患者重播、两条事件字幕下一帧x24刷新均保留。无卡/素材不全降级；旧21段卡不播全名。
把deliverables/TF_CARD_PATIENT_NAMES_20261102/SD_ROOT内54个PCM复制到FAT32卡根目录，顺序任意；不要复制WAV。已有BMP可保留。首次加载时间增加；服务准备超时后的提示音模式不阻止后台继续加载，完成后恢复语音模式。
患者名单：assets/patients.json；完整素材校验：assets/voice_manifest.json；实音拼接试听：assets/speech_previews/。

## 资源与图片方案
相对前一封包：LUT 16560 -> 15284，REG 8191 -> 5977，BRAM 52 -> 64/64，DSP仍20/29；Slice 95.18% -> 79.44%。
节省来自PCM元数据改为同步无复位RAM+有效位图，增加名单后仍减少LUT/寄存器；这是以BRAM换逻辑，BRAM余量为0块，不能称为所有资源都下降。
整页640x480 RGB888文件921600字节；现有SDRAM实际32bit/像素每页1228800字节，每秒约73.14MB读流量（59.5238fps）。现有显示读取已存在，换静态底图不必重复读取，但动态姓名、计数、提示、动画仍需OSD/状态逻辑，且整页状态枚举不能代替实时字幕。新TF卡语音已接近音频专用区容量，不可混占该地址区。
本版保留实时页面，未把动态功能固化为图片。另导出12张实际RTL页面BMP与字幕裁剪图供审阅：sim/ui/patient_names/；这些图片未被伪装成新的硬件渲染证据。后续静态底图合入需像素等价、显示/PCM带宽、输入切换和STA重新闭环。

## 构建验证
最终slow/fast setup/hold +0.195/+0.030 ns，TNS0、所有路径组违例端点0；SDRAM/PLL/HDMI/约束及播放器等23个保护文件字节不变。未添加全局false path/内部多周期或降频。
签核：doc/compile/timing_closure/20261101T163820Z_5bfe0d34/signoff.json；全证据：doc/compile/patient_names_delivery.json；原包和V0.2保留。
位流：deliverables/MedQ_v0.3_PATIENT_NAMES_20261101T164208Z.bit；SHA256 4b051d0d92c6389fad5453f85daa45f6abf9ff7de38a7c352652f57c26e1538e。当前封包以deliverables/latest_v03.json为准。

```powershell
python sim/run_regression.py --sim modelsim --timeout 600
python prj/td/verify_patient_paths.py tb_named_pcm tb_patient_pcm_path
python sim/run_vendor_sdram.py --system --timeout 600
python sim/run_vendor_sdram.py --system --system-tb tb_v03_top_audio --timeout 300
python sim/run_vendor_sdram.py --system --system-tb tb_basic_calling --timeout 180
python prj/td/medq_td.py --name MedQv03 --mode synth --run --timeout 300
python prj/td/route_seed.py --parent-result <new-synth-result.json> --seed 61 --timeout 1800
python prj/td/signoff_timing.py --result <new-route-result.json> --bitgen
python sim/capture_v03.py --source <new-real-system-directory>
python prj/td/finalize_patient_release.py
python prj/td/package_patient_release.py --timing
python prj/td/seal_timing_release.py
```

board_test: not_tested。未下载、未验证用户实卡或实板音频。已知原先无热插拔/持久化/第二HDMI等限制保留。As of 2026-11-02。


## 12. 姓名遮罩与流畅语音（2026-11-02）

# MedQ V0.3 姓名遮罩与流畅语音（2026-11-02）

屏幕显示首字+单个星号+末字：例如请C01张*民到A诊室就诊；语音仍播完整姓名张伟民。全部30人、原独立A/B初诊与C/D回诊号段、匿名兜底不变。
54段语音统一Huihui Rate=1（原=-1）；移除各段首尾静音，12ms保护垫+2ms淡入淡出，词内声音不裁切。16kHz/16bit单声道与播放器48kHz/插值时序未改。C01整句PCM由12.840s降至3.438s；素材拼接处静音上限24ms，未将该数值冒充实板测量。全部54段活动样本逐一保留检查通过。

## 更新方式
必须更新位流并替换全部54段PCM。deliverables/TF_CARD_MASKED_SMOOTH_20261102/SD_ROOT中只有CLIP00..53.PCM，可按任意顺序复制到FAT32根目录，原BMP可保留；不要复制WAV。旧的54段素材仍是原慢速播报。
音频经HDMI，蜂鸣器仅为降级提示音。名单/姓名遮罩：assets/patients.json；生成与波形统计：assets/voice_manifest.json；新旧试听：assets/speech_previews/；C01_张伟民.wav是新版，previous_C01_张伟民.wav是旧版。

## 保留与验证
SW1/SW2独立A/B叫号、SW3/SW4医生双边沿、回诊优先、暂停安全排空/同患者重播、0/30/60秒、每操作下一帧x24字幕刷新、抗锯齿和动态人数保持。
ModelSim完整46/46、2项源绑定专项、36项签核器测试通过。34例覆盖30人的遮罩像素共2012800点；18类事件1065600点；396种01..99语句全链路32076个PCM输出样本均匹配。
真实加密SDRAM控制器三类整机模式通过；12连续RTL帧见sim/ui/v03_rtl/，字幕裁剪和页面BMP见sim/ui/masked_smooth/。

## 资源和时序
两角setup/hold +0.230/+0.021ns，TNS0、全部组违例端点0。LUT 15284->15180，REG 5977->5973，BRAM 64->62/64，DSP仍20/29；Slice 79.44%->78.73%。
新增遮罩字形没有缩字/降色；附加字库无损从240行压到180行，115个sprite的101958像素逐一相同，原首4K字模和legacy ROM字节不变。布局证据doc/compile/masked_smooth/lossless_font_packing.json。
SDRAM/PLL/HDMI/播放器/约束等23个保护文件不变；旧位流、旧包与V0.2冻结保留。没有假路径掩盖或降频。
签核：doc/compile/timing_closure/20261101T170304Z_1e892d47/signoff.json；详细结果doc/compile/masked_smooth_delivery.json。位流：deliverables/MedQ_v0.3_MASKED_SMOOTH_20261101T170544Z.bit；SHA256 47def329d4c9244ce70e57cd857325a17bffc1d7175cb336cf785effc32f483d。

## 复现
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File sim/build_voice.ps1
python sim/build_dual_font.py
python sim/build_marquee_reference.py
python sim/build_event_reference.py
python prj/td/verify_smooth_audio.py
python sim/run_regression.py --sim modelsim --timeout 600
python prj/td/verify_patient_paths.py tb_named_pcm tb_patient_pcm_path
python sim/run_vendor_sdram.py --system --timeout 600
python sim/run_vendor_sdram.py --system --system-tb tb_v03_top_audio --timeout 300
python sim/run_vendor_sdram.py --system --system-tb tb_basic_calling --timeout 180
python prj/td/medq_td.py --name MedQv03 --mode synth --run --timeout 300
python prj/td/route_seed.py --parent-result <new-synth-result.json> --seed 61 --timeout 1800
python prj/td/signoff_timing.py --result <new-route-result.json> --bitgen
python sim/capture_v03.py --source <new-real-system-directory>
python prj/td/finalize_masked_release.py
python prj/td/package_masked_release.py --timing
python prj/td/seal_timing_release.py
```
生产前的无损字库比对是本次冻结旧布局到新布局的证据，日常复现无需重新生成该历史比较。所有最终文件按deliverables/latest_v03.json与ZIP内DELIVERY_MANIFEST.json校验。
board_test: not_tested。未下载、未做实板声学/电气测试。As of 2026-11-02。


## 13. 居中连续字幕（2026-11-02）

# MedQ V0.3 居中刷新、连续循环字幕（2026-11-02）

A/B新操作仍在下一帧立即刷新，整句按实际字形宽度居中，然后按原速每两帧向左一像素（约29.76px/s）。x24..615为592像素环，左侧移出的像素在同一步从右侧进入，没有等整句退出的空白阶段。取消字幕窗口水平渐隐，原四级抗锯齿保持。

屏幕仍为“请C01张*民到A诊室就诊”；语音仍播完整姓名，保持上一版提速、去边缘静音后的54段PCM。SW1/SW2独立叫号、SW3/SW4医生功能、取号/回诊/计数/优先级/暂停排空与重播均保留。本次RTL只修改medq_dual_ui_scene.v，所有字体、患者表、音频素材、底层RTL及约束与上一封版逐文件一致。

## 更新
仅更新新版位流：deliverables/MedQ_v0.3_SEAMLESS_MARQUEE_20261101T175917Z.bit。SHA256：66bb8cf4f790a212fa2695be2bab9977f4f3afded3d5507f11b7a69f1d44c1eb。
已使用MASKED_SMOOTH版54段PCM的TF卡无需重拷。完整配套音频仍在deliverables/TF_CARD_MASKED_SMOOTH_20261102/SD_ROOT；更旧的慢速TF卡应更新这54段，音频经HDMI输出。

## 验证
ModelSim完整47/47通过，另2项实际FAT/SDRAM/PCM链路专项通过。独立名单像素2012800点、18类事件1065600点；新增全环14042240点、双室592个位置、23680次左出右入边缘交换和零空帧检查通过。字模、遮罩与颜色精确比较，不使用DUT计算作为像素期望。整机真实SDRAM、长语音和无卡降级均通过，原完整业务与外设回归保留。
真实整机12帧见sim/ui/v03_rtl；592步全环38帧字幕见sim/ui/seamless_marquee/，continuous.gif/APNG按实际速度播放，无软件重画文字。36项工具负向与签核测试通过。

## 时序与资源
原生slow/fast全部组setup/hold WNS +0.155/+0.020ns，TNS0、违例端点0；fresh bitgen重新导入已审计路由库并通过STA。
LUT 15180->15294，REG 5973->5941，BRAM 62/64，DSP 20/29；Slice 79.50%。不增加字库、帧缓存或放宽约束。
签核：doc/compile/timing_closure/20261101T175412Z_0e861ccb/signoff.json；详细结果：doc/compile/seamless_marquee_delivery.json。旧封包、旧位流和V0.2冻结保留。

## 复现
```powershell
python sim/build_marquee_reference.py
python sim/build_event_reference.py
python sim/run_regression.py --sim modelsim --timeout 600
python prj/td/verify_patient_paths.py tb_named_pcm tb_patient_pcm_path
python sim/run_vendor_sdram.py --system --timeout 600
python sim/run_vendor_sdram.py --system --system-tb tb_v03_top_audio --timeout 300
python sim/run_vendor_sdram.py --system --system-tb tb_basic_calling --timeout 180
python prj/td/medq_td.py --name MedQv03 --mode synth --run --timeout 300
python prj/td/route_seed.py --parent-result <new-synth-result.json> --seed 23 --timeout 1800
python prj/td/signoff_timing.py --result <new-route-result.json> --bitgen
python sim/capture_v03.py --source <new-real-system-directory>
python sim/capture_seamless.py
python prj/td/finalize_seamless_release.py
python prj/td/package_seamless_release.py --timing
python prj/td/seal_timing_release.py
```
board_test: not_tested。没有执行实板下载或声学/电气验收。As of 2026-11-02。


## 14. SD封面、医生轮播和音频波形（2026-11-03）

# MedQ V0.3 SD封面、医生轮播和音频波形版（2026-11-03）

上电从TF卡读取用户提供的封面；K1..K4任意键进入诊室系统。进入键被单独消费，全部按键稳定松开后才重新初始化诊室按键/开关，封面操作不会取号或触发医生事件。SW1/SW2独立A/B叫号、SW3/SW4医生、四路初诊/回诊取号及所有原队列规则保留。

右侧地图缩为152x100区域；下方显示一名医生，男/女两张照片自动轮播。照片显示152x128，保持约4秒，采用逐帧smoothstep淡出/淡入（每方向约0.55秒），零透明度换图，隐藏3帧等待现有读取FIFO和CDC稳定；不会同时叠放两位医生。男医生选用较大PNG，另一张男医生原图完整保留。

右下角波形取最终HDMI有符号音频，做32点帧快照、线性插值及边缘覆盖度；静音平线，封面隐藏。独立测试发现旧混音器将负采样零扩展且未正确做Q0.8缩放，负1000/音量128错误输出32767；本版修正为-500，4105项数值对照通过。全部54段PCM、全名语音提速、名单、屏幕张*民隐私遮罩、四级抗锯齿字体和居中连续循环字幕素材保持原字节。

## 直接部署

- 位流：deliverables/MedQ_v0.3_MEDIA_COVER_20261103T063042Z.bit
- SHA256：a1392a908f4533d4cdcd7019dabec5a65c87a96945e0e0033ee2fcedc7298567
- TF卡：deliverables/TF_CARD_MEDIA_20261103/SD_ROOT，共57个文件。把里面的文件直接复制到FAT32根目录。包含3张BMP和原54段PCM，按文件名定位，不依赖复制顺序。
- BMP是电脑端Lanczos缩放的640x480/24bit无压缩文件；JPG/PNG原图放assets/media_source，运行时不使用JPEG/PNG解码或片内图片ROM。
- 旧TF卡必须增加3张BMP；建议使用本包完整SD_ROOT。声音仍经HDMI屏幕/接收设备输出。

## 本机证据

ModelSim完整55/55通过，另2项命名PCM/396整句语音链路专项通过；Verilog-2001检查通过。SD卡多簇读取与跨时钟/反压写入对照921600个实际图片像素；独立封面307200像素、18种照片混合350208像素、4320000个原叫号/字幕区像素对照通过。原14042240点字幕全环回归继续通过。

整机使用原加密SDRAM控制器及独立物理器件模型：图片未全加载前封面已先显示；进入键不误取号；3张图片、54段PCM加载完整；A/B并发18段播放；最终307200封面像素和19456照片像素逐一一致；无显示/音频欠载。原整机业务、长语音取消/暂停、无卡降级和PLL/串行器/带宽证据也通过当前源码哈希核验。36项工具/负向签核测试通过。

实际RTL预览：sim/ui/media_real_system（整机实际SD读取）、sim/ui/media_rtl（独立像素对照）。sim/ui/media_assets是输入素材转换预览，不是RTL或实板证据。

## 时序与资源

原生slow/fast所有setup/hold组通过：WNS +0.225/+0.021ns，TNS0，违例端点0；fresh bitgen重新导入同一路由库并检查STA。
LUT 15268/19600，REG 5927/19600，BRAM 56/64（上一版62），DSP 17/29（上一版20）。板级管脚、PLL频率、SDRAM相位和所有约束保持字节一致，没有增加false path或放宽时序。

签核：doc/compile/timing_closure/20261103T061423Z_c18a20e8/signoff.json。版本权威为deliverables/latest_v03.json，详细结果doc/compile/media_carousel_delivery.json。旧封包、位流、V0.2及修改前源码快照保留。

## 复现

    python sim/build_media_assets.py
    python sim/build_media_fixtures.py
    python sim/run_regression.py --sim modelsim --timeout 1200
    python prj/td/verify_patient_paths.py tb_named_pcm tb_patient_pcm_path
    python sim/run_vendor_sdram.py --system --system-tb tb_media_top --timeout 1200
    python sim/run_vendor_sdram.py --system --timeout 400
    python sim/run_vendor_sdram.py --system --system-tb tb_v03_top_audio --timeout 400
    python sim/run_vendor_sdram.py --system --system-tb tb_basic_calling --timeout 120
    python prj/td/medq_td.py --mode synth --run
    python prj/td/route_seed.py --parent-result <new-synth-result.json> --seed 23
    python prj/td/signoff_timing.py --result <new-route-result.json> --bitgen
    python prj/td/finalize_media_release.py
    python prj/td/package_media_release.py
    python prj/td/seal_timing_release.py

board_test: not_tested。未进行实板下载、HDMI屏幕/扬声器验收或真实TF卡速度测量。

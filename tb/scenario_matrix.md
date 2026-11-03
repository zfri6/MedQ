# MedQ 主业务仿真场景（2026-10-26）

当前规则见 `doc/spec/behavior_spec.md`；旧逐模块规格中的冲突描述已标记为历史版本。
测试输入不使用随机系统种子；伪随机 TMDS 测试使用固定初值。

| 测试入口 | 刺激与边界 | 必须观察的结果 |
|---|---|---|
| tb_rst_sync | POR=8、外部复位、PLL 丢锁 | 实际计满再释放，异步断言，两级释放 |
| tb_key_debounce | 抖动、保持、释放、长按 | 单拍 press/release、稳定 level/hold |
| tb_cdc_bus_handshake | 跨独立时钟传递总线 | 快照与握手符合规格 |
| tb_cdc_pulse | 12 次事件，每次等待 ack | 两种翻转均传递，目的脉冲恰好一拍 |
| tb_queue_fsm | 双普通/三优先、重呼、过号、满 128、0099/9999、恢复、自动模式 | 公平出队，重呼不消费，0000 合法，QSTATE 与伴随数据一致 |
| tb_sdram_arbiter | 256 拍写、四主同时请求、读写停顿、高地址 | 归属不变、恰好 len 拍、数据正确、不别名 |
| tb_bmp_parser | 无间隔字节、24/32bpp、padding、正反高度、坏格式/偏移/尺寸 | 正确 RGB/坐标/结束信号，错误只报失败 |
| tb_fat32_reader | 目录簇链、0x10003 高簇号、700 字节碎片文件、反压、SD/BPB 错误 | 精确字节序和长度，不截簇号，失败可见 |
| tb_asset_loader | SPI 卡初始化重试、两扇区根目录、2×2 图片、19 PCM、FB1 重载 | 全部 307200 像素逐字匹配、PCM 地址内容与长度一致 |
| tb_storage_errors | SD MISO 始终为高 | 初始化有限超时，加载器失败且 assets_ok=0 |
| tb_osd_renderer | 字符/字段/颜色配置、1×/2×、边界扫描、关闭图层 | 同步字模相位、正确 RGBA、边界透明 |
| tb_medq_ui | 帧快照、16 帧动画、重呼、呼吸、2 bit 字模、20 张原始画面 | 无帧内状态变化、缓出单调、四档覆盖度、同步读口与画面完整性 |
| tb_video_pipeline | 两个完整帧、HS/VS、亮度与多组 alpha | 800×525/640×480，精确混合与饱和 |
| tb_audio_pipeline | 四位票号、两轮播报、三样本奇数 PCM、空片段 | 18 段、正确有符号插值、520/521 拍选通、能再次启动 |
| tb_hdmi_tmds_encoder | 四控制码、全字节/长重复/固定伪随机序列 | 8193 符号可逆，运行视差有界 |
| tb_hdmi_tx_core | 标准视频和有序立体声音频 | 完整视频、32 拍包、五块 BCH、checksum、N/CTS、音频顺序 |
| tb_tmds_serdes | 128 个连续变化并行字，5× 串行时钟 | 每像素 10 个 DDR 边沿，LSB 先发，无掉字 |
| tb_top | 板级 SD 卡模型、真实 UART/CRC、10ms 按键、取号/叫号/重呼 | 三次跨域事件、27 段播放、无未知板级输出/欠载、完整 RGB 帧 |

最终结果见 `sim/regression_result.json`；逐项日志见 `sim/tests/<simulator>/<tb>/`。
整机帧的完整性与位置/颜色抽查保存在 `sim/frame_verification.json`；新版 UI 的四档字模检查见 `sim/ui/preview_verification.json`。
Flash、第二屏、全部转场/频谱/诊断页面与真实 TD 原语不属于本矩阵已通过的范围。

独立厂商模型场景（不计入上述 18 项行为回归）：tb/vendor/tb_tmds_serdes_eg4.v，
不定义 SIMULATION，加载未修改的 EG4 IO/glbl 模型；四 lane、同相/半周期偏移、每相位 1200 字、
全部 1024 输入码、双沿逐 bit 比对、复位中断/重新对齐。此项不等于 PLL/SDRAM/整机原语仿真。

另有 tb/vendor/tb_medq_pll_eg4.v：加载 TD 新生成 medq_pll 与原始 EG4 模型，检查 50 -> 125/25/100 MHz，
每次锁定后各输出至少 100 个实测周期，复位/失锁/重新锁定两个轮次。原模型/生成 wrapper 的 load_reg 位宽警告保留。
tb_fat32_reader 定义 FAT_BOUNDARY 时改用 0x1007f/0x10080 簇，并让扇区最后字节和 done 同拍，验证同步 RAM 边界。


资源优化新增自检：

| 测试 | 具体激励 | 验收 |
|---|---|---|
| tb_pixel_math_equivalence | 全部65153个/255输入、全部coverage/opacity、混色及BC边界 | 917121次旧RTL函数/独立算术对照 |
| tb_spectrum_render_equivalence | 全65536采样码、环绕、所有旧模式、复位 | 投影与冻结RTL每拍输出相同 |
| tb_fat32_address_math | spc=1..128、FAT数1/2/3/255、32bit乘积模溢出 | 32组公开SD LBA/数据事务正确 |
| tb_goertzel_spectrum | 12块/3072采样，静音/满幅DC/单频/噪声/多频/脉冲，部分块复位、忙时额外stb | 对照独立Python的192bin，索引/8拍输出间隔/包络正确、无X |

当前完整默认ModelSim矩阵为22项；独立原语模型和FAT_BOUNDARY仍另行保存。
20张UI完整帧与优化前SHA256相同，见sim/resource_optimization/ui_equivalence.json。

## 2026-10-31 视觉时序等价补充

|场景|激励|独立期望|规则|
|---|---|---|---|
|tb_dual_ui_visual_equivalence|五个完整 VGA 页面、912 个字幕位置、呼吸/闪烁、计数16、暂停|冻结视觉交接场景的六个输出逐拍一致|R08/R11/R14|

## 2026-11-02 连续字幕

|场景|激励|独立期望|规则|
|---|---|---|---|
|tb_marquee_name / event_pixels|30人及18种A/B操作，5个位置|独立字模实际宽度居中、环折返、无遮边渐隐、AA和颜色精确|R11|
|tb_marquee_seamless|592个位置双室逐像素移动和边缘交换|592像素环保守移位，左缘像素同一步进入右缘，无空帧，单室刷新互不干扰|R08/R11|

## media_carousel_20261103

| Test | Stimulus and independent acceptance |
|---|---|
| tb_cover_isolation | Four entry keys, boot-held/bounce/multi-key cases, cover switch changes, release baseline, fresh clinic events, frame-only fade/hidden base swap, missing media |
| tb_named_bmp | Shuffled named images, unrelated BMP, duplicate rejection and sparse stable IDs |
| tb_media_invalid | Named2x2 cover rejected by native profile, no partial valid publication |
| tb_media_assets | Actual SD BMP bytes, multi-cluster files, asynchronous/backpressured writes,921600 exact RGB beats, all54 PCM metadata/payloads |
| tb_media_pixels | Actual BMP reference, exact cover,18 independent fade raster cases, clinic/subtitle preservation,19 actual RTL full frames |
| tb_audio_wave | Signed audio/saturation/silence, per-frame history, exact interpolation/AA and cover suppression |
| tb_audio_mixer_signed |4105 integer signed gain/saturation/strobe checks, independently reproduced original defect |
| tb_media_top | Actual board pins + full delivered image fixture, early cover, consumed return-entry key, full preload, concurrent A/B audio and display, exact final framebuffer pixels; run behavioral and encrypted physical-controller profiles |

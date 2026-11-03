> 最新字幕按整句居中刷新并在592像素环内连续左移，左出右入同一步；见seamless_marquee_20261102.md。

> 当前屏幕为首字*末字，语音全名提速并去首尾静音；见masked_smooth_20261102.md。原控制/队列/字幕刷新规则保留。

> 2026-11-02：6bit PCM ID按CLIPnn文件名定位；64项同步元数据RAM；全名语音与仅姓氏字幕。见patient_names_20261102.md及接口amendment。

> 2026-11-01字幕链路：room_service操作描述 -> dual_service QSTATE -> subtitle_notify（含实际重播通知）-> dual_ui_scene帧快照/独立左端重置 -> 原OSD/8K同步字体/HDMI。完整契约：doc/spec/marquee_events_20261101.md。

> V0.3 当前业务接口以 interface_contract.yaml 的 v03_interfaces 及 doc/spec/independent_switch_name_20261031.md 为准。SW1/SW2=独立A/B叫号，SW3/SW4=A/B医生；底层连接和管脚不变。

# V0.3 architecture

KEY/SW -> existing medq_board_inputs (pix two flops) -> v03_inputs -> dual_service -> dual_announcer (ready/grant same edge) -> controlled PCM -> existing arbiter/controller. qstate_pix -> dual UI and held CDC -> sys seg. service_status -> announcer/UI. font scene addr -> existing synchronous ROM -> OSD 2-cycle output -> existing video align/compositor/HDMI.

## media_carousel_20261103

KEY -> board two-flop synchronizer -> cover control -> frame-committed clinic visibility -> all-key release -> reset release of v03_inputs -> unchanged dual service. No cover key is forwarded as an enqueue. SW1..4 are freshly baselined by v03_inputs after entry.

SD SPI -> FAT named COVER/DOC01/DOC02 scan -> native BMP pixels -> existing asynchronous word FIFO -> SDRAM images0/1/2. Each image validity crosses sys->pix after acknowledged final write. Media control holds pix framebuffer base -> W22 coherent handshake -> frame_reader memory-domain frame boundary latch -> original two-register base pixel path. Photo alpha and cover flags take the same two-cycle OSD pipeline; audio wave one-cycle output takes existing extra alignment cycle. Final compositor/HDMI unchanged.

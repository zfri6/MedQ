

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

完整需求、同拍优先级和QSTATE描述见doc/spec/marquee_events_20261101.md。字形/素材/硬件保护见marquee_source_asset_audit.json。原单色/历史暂停约定以本次明确修订为准；底层HDMI/SDRAM/PCM/PLL/约束未修改。

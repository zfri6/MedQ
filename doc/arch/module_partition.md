# V0.3 architecture

medq_v03_inputs: synchronized/debounced pins in pix; medq_room_service: one room FIFOs/ticket/state/timer; medq_dual_service: two instances and QSTATE; medq_dual_announcer: fair serial admission/cancel; controlled audio_pcm_player: pause and safe abort drain; medq_dual_ui_scene: frame snapshot/scroll and ROM addressing. Existing storage/HDMI/PLL preserved.

## media_carousel_20261103

`medq_media_control` owns cover key debounce/release, page/clinic arming, chosen portrait and fade state. `asset_loader MEDIA_PROFILE=1` owns named image metadata, native parser path, three SDRAM image commits and existing PCM preload. `medq_audio_wave` owns32-point signed audio history and frame snapshots; it consumes final HDMI samples and never controls audio. `osd_renderer MEDIA_LAYOUT=1` owns media transparency, `medq_dual_ui_scene COMPACT_MAP=1` owns the compressed map. The existing frame_reader, arbiter, physical SDRAM controller and HDMI pipeline are reused. The default legacy module profiles retain their historical tests.

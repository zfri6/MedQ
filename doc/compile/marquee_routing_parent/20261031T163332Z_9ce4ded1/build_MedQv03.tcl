# Run from the ASCII workspace root with td_commands_prompt.exe.
import_device eagle_s20.db -package EG4S20BG256
analyze -file {rtl/al_ip/afifo_8i_32o_1024.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/al_ip/clk_wize.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/al_ip/medq_pll.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/al_ip/sdram.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/al_ip/sdram_vendor/global_def.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/al_ip/sdram_vendor/sdr_as_ram.enc.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/al_ip/sdram_vendor/sdr_init_ref.enc.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/al_ip/sdram_vendor/sdr_wrrd.enc.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/al_ip/sys_pll.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/asset_loader.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/audio_announcer.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/audio_mixer.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/audio_pcm_player.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/audio_sample_clk.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/audio_tone_gen.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/av_sync_monitor.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/bilinear_scaler.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/bmp_parser.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/buzzer.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/cdc_bus_handshake.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/cdc_pulse.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/cdc_sync_bit.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/fat32_reader.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/font_rom.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/frame_reader.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/goertzel_spectrum.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/hdmi_bch_ecc.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/hdmi_packet_scheduler.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/hdmi_terc4_encoder.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/hdmi_tmds_encoder.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/hdmi_tx_core.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/key_debounce.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/latency_probe.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/medq_async_fifo.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/medq_board_inputs.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/medq_call_cdc.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/medq_call_feedback.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/medq_dual_announcer.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/medq_dual_service.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/medq_dual_ui_scene.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/medq_room_service.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/medq_sdram_adapter.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/medq_service_guard.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/medq_subtitle_notify.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/medq_ui_scene.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/medq_v03_inputs.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/medq_video_align.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/osd_compositor.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/osd_renderer.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/param_ctrl.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/queue_fsm.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/rst_sync.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/sd_card_ctrl.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/sd_spi_master.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/sdram_arbiter.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/sdram_ctrl_wrap.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/seg_scan.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/spectrum_render.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/spi_flash_store.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/tmds_serdes.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/top.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/transition_engine.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/uart_cmd.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/uart_rx.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/uart_tx.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
analyze -file {rtl/video_timing.v} -include_dir {rtl rtl/al_ip/sdram_vendor compat}
elaborate -top top
puts "MEDQ_STAGE_ELABORATED"
read_adc {prj/constr/top.adc}
read_sdc {prj/constr/top.sdc}
optimize_rtl
report_area -file prj/td/reports/MedQv03_rtl.area
set_param gate map_mode area_prior
set_param gate pack_effort high
optimize_gate -packarea prj/td/reports/MedQv03_gate.area
export_db prj/td/output/MedQv03_gate.db
puts "MEDQ_STAGE_SYNTHESIZED"
legalize_phy_inst
update_timing
set_param route effort routability
place
route
fix_hold
report_area -io_info -file prj/td/reports/MedQv03_phy.area
update_timing -mode final
report_timing_status -file prj/td/reports/MedQv03_phy.ts
report_timing_summary -ep_num 500 -file prj/td/reports/MedQv03_pr.timing
report_timing_exception -file prj/td/reports/MedQv03_exception.timing
report_timing_ignored -ep_num 500 -file prj/td/reports/MedQv03_ignored.timing
check_timing -verbose -file prj/td/reports/MedQv03_constraint_health.rpt
export_db prj/td/output/MedQv03_pr.db
puts "MEDQ_STAGE_IMPLEMENTED"
puts "MEDQ_FLOW_DONE_IMPLEMENT"
exit

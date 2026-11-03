//============================================================================
// MedQ - HDMI outpatient queue-calling terminal
// Top-level SKELETON (architecture stage artifact)
//
// Board  : HX4S20C        Device : EG4S20BG256 (Anlogic EG4)
// Clock  : clk50mhz @ R7, 50 MHz  (see doc/hw/extracted_facts.json)
// Video  : 640x480@60, pixel 25.000 MHz, TMDS serial 125 MHz
// Audio  : 48 kHz over HDMI data islands, ACR N=6144 CTS=25000 (exact)
//
// This file contains ONLY instantiation and wiring. No business logic.
// Port names and widths are frozen by doc/arch/interface_contract.yaml.
// The implemented top lives in rtl/top.v and is generated from this skeleton.
//============================================================================
`timescale 1ns / 1ps

module top_skeleton (
    // ---- clock ----
    input  wire        clk50mhz,    // R7,  50 MHz

    // ---- user input (all active low, pulled up) ----
    input  wire [3:0]  KEY,         // A2, B2, B1, C1
    input  wire [3:0]  SW,          // C8, C7, C6, C5

    // ---- user output ----
    output wire [3:0]  LED,         // A4, A3, C10, B12
    output wire [7:0]  SEG_DATA,    // C15,C16,B6,A5,B5,A8,A7,A6  {dp,g,f,e,d,c,b,a}
    output wire [7:0]  SEG_SEL,     // D11,E11,F10,C13,E10,E12,E16,F16
    output wire        BUZZER,      // H11

    // ---- debug UART (not required for standalone operation) ----
    input  wire        UART_RX,     // F12
    output wire        UART_TX,     // D12

    // ---- TF card, SPI mode ----
    output wire        SD_SCLK,     // A14
    output wire        SD_MOSI,     // A13
    input  wire        SD_MISO,     // B14
    output wire        SD_nCS,      // A12

    // ---- HDMI, LVDS33 true differential (only _P is constrained) ----
    output wire        HDMI_CLK_P,  // C3
    output wire        HDMI_D0_P,   // G5
    output wire        HDMI_D1_P,   // F1
    output wire        HDMI_D2_P    // E1
);

    //========================================================================
    // Clocks and resets
    //========================================================================
    wire clk_sys = clk50mhz;                 // 50 MHz, no PLL
    wire clk_pix;                            // 25 MHz
    wire clk_ser;                            // 125 MHz
    wire clk_mem;                            // 100 MHz
    wire pll_locked;

    wire rst_n_sys, rst_n_pix, rst_n_mem;

    // generate with TD IP Generator -> rtl/al_ip/clk_wize.v  (ALREADY PRESENT, reused from DEMO 31)
    // 50 MHz -> C0 125 MHz (clk_ser), C1 25 MHz (clk_pix)
    clk_wize u_clk_wize (
        .refclk   (clk50mhz),
        .reset    (1'b0),
        .clk0_out (clk_ser),
        .clk1_out (clk_pix)
    );

    // generate with TD IP Generator -> rtl/al_ip/pll_mem.v   (NOT YET GENERATED, needs TD)
    // 50 MHz -> 100 MHz for the SDRAM domain, must export extlock
    pll_mem u_pll_mem (
        .refclk   (clk50mhz),
        .reset    (1'b0),
        .extlock  (pll_locked),
        .clk0_out (clk_mem)
    );

    rst_sync #(.POR_CYCLES(50000)) u_rst_sys (
        .clk(clk_sys), .ext_rst_n(1'b1), .pll_locked(1'b1),       .rst_n_out(rst_n_sys));
    rst_sync #(.POR_CYCLES(25000)) u_rst_pix (
        .clk(clk_pix), .ext_rst_n(1'b1), .pll_locked(pll_locked), .rst_n_out(rst_n_pix));
    rst_sync #(.POR_CYCLES(50000)) u_rst_mem (
        .clk(clk_mem), .ext_rst_n(1'b1), .pll_locked(pll_locked), .rst_n_out(rst_n_mem));

    //========================================================================
    // Control plane (clk_sys)
    //========================================================================
    wire [3:0] key_level, key_press, key_release, key_hold;
    key_debounce #(.N(4)) u_key_debounce (
        .clk(clk_sys), .rst_n(rst_n_sys), .key_in_n(KEY),
        .key_level(key_level), .key_press(key_press),
        .key_release(key_release), .key_hold(key_hold));

    wire        urx_valid;  wire [7:0] urx_data;
    wire        utx_valid, utx_ready; wire [7:0] utx_data;
    uart_rx u_uart_rx (.clk(clk_sys), .rst_n(rst_n_sys), .rxd(UART_RX),
                       .out_valid(urx_valid), .out_data(urx_data), .frame_err());
    uart_tx u_uart_tx (.clk(clk_sys), .rst_n(rst_n_sys), .in_valid(utx_valid),
                       .in_ready(utx_ready), .in_data(utx_data), .txd(UART_TX));

    wire cmd_next, cmd_recall, cmd_skip, cmd_arrive, cmd_page;
    wire cmd_param_we; wire [3:0] cmd_param_sel; wire [7:0] cmd_param_val;
    uart_cmd u_uart_cmd (
        .clk(clk_sys), .rst_n(rst_n_sys),
        .rx_valid(urx_valid), .rx_data(urx_data),
        .tx_valid(utx_valid), .tx_ready(utx_ready), .tx_data(utx_data),
        .cmd_next(cmd_next), .cmd_recall(cmd_recall), .cmd_skip(cmd_skip),
        .cmd_arrive(cmd_arrive), .cmd_page(cmd_page),
        .cmd_param_we(cmd_param_we), .cmd_param_sel(cmd_param_sel),
        .cmd_param_val(cmd_param_val));

    wire [127:0] qstate_sys, persist_data, restore_data;
    wire         persist_req, restore_req, call_pulse_sys;
    wire [15:0]  call_ticket;  wire [3:0] call_room;  wire call_prio;

    queue_fsm u_queue_fsm (
        .clk(clk_sys), .rst_n(rst_n_sys),
        .ev_next  (key_press[0] | cmd_next),
        .ev_recall(key_press[1] | cmd_recall),
        .ev_page  (key_press[2] | cmd_page),
        .ev_arrive(key_press[3] | cmd_arrive),
        .ev_skip  (cmd_skip),
        .sw_priority(~SW[0]), .sw_auto(~SW[1]), .sw_access(~SW[3]),
        .restore_req(restore_req), .restore_data(restore_data),
        .persist_data(persist_data), .persist_req(persist_req),
        .qstate(qstate_sys), .call_pulse(call_pulse_sys),
        .call_ticket(call_ticket), .call_room(call_room), .call_prio(call_prio));

    wire [63:0] param_sys;
    param_ctrl u_param_ctrl (
        .clk(clk_sys), .rst_n(rst_n_sys),
        .key_press(key_press), .key_hold(key_hold), .sw(SW),
        .ext_we(cmd_param_we), .ext_sel(cmd_param_sel), .ext_val(cmd_param_val),
        .param(param_sys), .osd_hint_id(), .osd_hint_val(), .osd_hint_vis());

    seg_scan u_seg_scan (
        .clk(clk_sys), .rst_n(rst_n_sys),
        .digits({16'h0, qstate_sys[15:0]}), .dp(8'h00), .blank(8'h00),
        .seg_data(SEG_DATA), .seg_sel(SEG_SEL));

    buzzer u_buzzer (
        .clk(clk_sys), .rst_n(rst_n_sys), .trig(call_pulse_sys),
        .pattern({call_prio, qstate_sys[33]}), .mute(1'b0),
        .beep(BUZZER), .busy());

    spi_flash_store u_spi_flash_store (
        .clk(clk_sys), .rst_n(rst_n_sys),
        .save_req(persist_req), .save_data(persist_data),
        .save_busy(), .save_done(),
        .load_req(1'b0), .load_data(restore_data),
        .load_valid(restore_req), .load_fail(),
        .fl_sclk(), .fl_mosi(), .fl_miso(1'b1), .fl_cs_n());

    //========================================================================
    // Storage chain (clk_sys) -> SDRAM write master (clk_mem)
    //========================================================================
    wire        wr_req_valid, wr_req_ready, wr_req_we, wr_wr_valid, wr_wr_ready;
    wire        wr_rd_valid,  wr_rd_ready;
    wire [21:0] wr_req_addr;  wire [8:0] wr_req_len;
    wire [31:0] wr_wr_data,   wr_rd_data;
    wire        assets_ok;    wire [3:0] load_progress;
    wire [5:0] img_count; wire [6:0] pcm_count;
    wire [5:0]  clip_sel;     wire [21:0] clip_base, clip_samples;

    asset_loader u_asset_loader (
        .clk_sys(clk_sys), .rst_n_sys(rst_n_sys),
        .clk_mem(clk_mem), .rst_n_mem(rst_n_mem),
        .load_req(1'b0), .img_sel(5'd0), .fb_sel(2'd0),
        .load_busy(), .load_done(), .load_err(),
        .img_count(img_count), .pcm_count(pcm_count),
        .assets_ok(assets_ok), .progress(load_progress),
        .clip_sel(clip_sel), .clip_base(clip_base), .clip_samples(clip_samples),
        .sd_spi_sclk(SD_SCLK), .sd_spi_mosi(SD_MOSI),
        .sd_spi_miso(SD_MISO), .sd_spi_cs_n(SD_nCS),
        .wr_req_valid(wr_req_valid), .wr_req_ready(wr_req_ready),
        .wr_req_addr(wr_req_addr),   .wr_req_we(wr_req_we), .wr_req_len(wr_req_len),
        .wr_wr_valid(wr_wr_valid),   .wr_wr_ready(wr_wr_ready), .wr_wr_data(wr_wr_data),
        .wr_rd_valid(wr_rd_valid),   .wr_rd_ready(wr_rd_ready), .wr_rd_data(wr_rd_data));

    //========================================================================
    // SDRAM arbiter + controller (clk_mem)
    //========================================================================
    wire        disp_req_valid, disp_req_ready, disp_req_we, disp_wr_valid, disp_wr_ready;
    wire        disp_rd_valid,  disp_rd_ready;
    wire [21:0] disp_req_addr;  wire [8:0] disp_req_len;
    wire [31:0] disp_wr_data,   disp_rd_data;

    wire        tr_req_valid, tr_req_ready, tr_req_we, tr_wr_valid, tr_wr_ready;
    wire        tr_rd_valid,  tr_rd_ready;
    wire [21:0] tr_req_addr;  wire [8:0] tr_req_len;
    wire [31:0] tr_wr_data,   tr_rd_data;

    wire        aud_req_valid, aud_req_ready, aud_req_we, aud_wr_valid, aud_wr_ready;
    wire        aud_rd_valid,  aud_rd_ready;
    wire [21:0] aud_req_addr;  wire [8:0] aud_req_len;
    wire [31:0] aud_wr_data,   aud_rd_data;

    wire        mem_req_valid, mem_req_ready, mem_req_we, mem_wr_valid, mem_wr_ready;
    wire        mem_rd_valid,  mem_rd_ready;
    wire [21:0] mem_req_addr;  wire [8:0] mem_req_len;
    wire [31:0] mem_wr_data,   mem_rd_data;
    wire        sdram_init_done;

    sdram_arbiter u_sdram_arbiter (
        .clk(clk_mem), .rst_n(rst_n_mem),
        .aud_req_valid(aud_req_valid),  .aud_req_ready(aud_req_ready),
        .aud_req_addr(aud_req_addr),    .aud_req_we(aud_req_we), .aud_req_len(aud_req_len),
        .aud_wr_valid(aud_wr_valid),    .aud_wr_ready(aud_wr_ready), .aud_wr_data(aud_wr_data),
        .aud_rd_valid(aud_rd_valid),    .aud_rd_ready(aud_rd_ready), .aud_rd_data(aud_rd_data),
        .disp_req_valid(disp_req_valid),.disp_urgent(1'b0),.disp_req_ready(disp_req_ready),
        .disp_req_addr(disp_req_addr),  .disp_req_we(disp_req_we), .disp_req_len(disp_req_len),
        .disp_wr_valid(disp_wr_valid),  .disp_wr_ready(disp_wr_ready), .disp_wr_data(disp_wr_data),
        .disp_rd_valid(disp_rd_valid),  .disp_rd_ready(disp_rd_ready), .disp_rd_data(disp_rd_data),
        .tr_req_valid(tr_req_valid),    .tr_req_ready(tr_req_ready),
        .tr_req_addr(tr_req_addr),      .tr_req_we(tr_req_we), .tr_req_len(tr_req_len),
        .tr_wr_valid(tr_wr_valid),      .tr_wr_ready(tr_wr_ready), .tr_wr_data(tr_wr_data),
        .tr_rd_valid(tr_rd_valid),      .tr_rd_ready(tr_rd_ready), .tr_rd_data(tr_rd_data),
        .wr_req_valid(wr_req_valid),    .wr_req_ready(wr_req_ready),
        .wr_req_addr(wr_req_addr),      .wr_req_we(wr_req_we), .wr_req_len(wr_req_len),
        .wr_wr_valid(wr_wr_valid),      .wr_wr_ready(wr_wr_ready), .wr_wr_data(wr_wr_data),
        .wr_rd_valid(wr_rd_valid),      .wr_rd_ready(wr_rd_ready), .wr_rd_data(wr_rd_data),
        .mem_req_valid(mem_req_valid),  .mem_req_ready(mem_req_ready),
        .mem_req_addr(mem_req_addr),    .mem_req_we(mem_req_we), .mem_req_len(mem_req_len),
        .mem_wr_valid(mem_wr_valid),    .mem_wr_ready(mem_wr_ready), .mem_wr_data(mem_wr_data),
        .mem_rd_valid(mem_rd_valid),    .mem_rd_ready(mem_rd_ready), .mem_rd_data(mem_rd_data));

    // Black box: real Anlogic SDRAM controller behind `ifdef; behavioural model in simulation.
    sdram_ctrl_wrap u_sdram_ctrl_wrap (
        .clk(clk_mem), .rst_n(rst_n_mem),
        .mem_req_valid(mem_req_valid),  .mem_req_ready(mem_req_ready),
        .mem_req_addr(mem_req_addr),    .mem_req_we(mem_req_we), .mem_req_len(mem_req_len),
        .mem_wr_valid(mem_wr_valid),    .mem_wr_ready(mem_wr_ready), .mem_wr_data(mem_wr_data),
        .mem_rd_valid(mem_rd_valid),    .mem_rd_ready(mem_rd_ready), .mem_rd_data(mem_rd_data),
        .init_done(sdram_init_done));

    //========================================================================
    // CDC: control plane (clk_sys) -> video plane (clk_pix)
    //========================================================================
    wire [127:0] qstate_pix;
    wire [63:0]  param_pix;
    wire         call_pulse_pix;

    cdc_bus_handshake #(.W(128)) u_cdc_qstate (
        .src_clk(clk_sys), .src_rst_n(rst_n_sys), .src_data(qstate_sys),
        .dst_clk(clk_pix), .dst_rst_n(rst_n_pix), .dst_data(qstate_pix));

    cdc_bus_handshake #(.W(64)) u_cdc_param (
        .src_clk(clk_sys), .src_rst_n(rst_n_sys), .src_data(param_sys),
        .dst_clk(clk_pix), .dst_rst_n(rst_n_pix), .dst_data(param_pix));

    cdc_pulse u_cdc_call (
        .src_clk(clk_sys), .src_rst_n(rst_n_sys), .src_pulse(call_pulse_sys), .src_busy(),
        .dst_clk(clk_pix), .dst_rst_n(rst_n_pix), .dst_pulse(call_pulse_pix));

    //========================================================================
    // Video pipeline (clk_pix)
    //========================================================================
    wire        vt_de, vt_hs, vt_vs, vt_frame_start, vt_line_start;
    wire [9:0]  vt_x, vt_y;
    wire [15:0] vt_frame_cnt;

    video_timing u_video_timing (
        .clk(clk_pix), .rst_n(rst_n_pix),
        .de(vt_de), .hs(vt_hs), .vs(vt_vs), .x(vt_x), .y(vt_y),
        .frame_start(vt_frame_start), .line_start(vt_line_start),
        .frame_cnt(vt_frame_cnt));

    wire [23:0] rgb_cur, rgb_next, rgb_trans;
    wire        disp_underrun, tr_underrun, tr_need_second;

    frame_reader u_frame_reader_main (
        .clk_pix(clk_pix), .rst_n_pix(rst_n_pix),
        .clk_mem(clk_mem), .rst_n_mem(rst_n_mem),
        .fb_base(22'h000000), .frame_start(vt_frame_start),
        .line_start(vt_line_start), .de(vt_de),
        .px_rgb(rgb_cur), .underrun(disp_underrun), .primed(), .urgent(),
        .disp_req_valid(disp_req_valid), .disp_req_ready(disp_req_ready),
        .disp_req_addr(disp_req_addr),   .disp_req_we(disp_req_we), .disp_req_len(disp_req_len),
        .disp_wr_valid(disp_wr_valid),   .disp_wr_ready(disp_wr_ready), .disp_wr_data(disp_wr_data),
        .disp_rd_valid(disp_rd_valid),   .disp_rd_ready(disp_rd_ready), .disp_rd_data(disp_rd_data));

    frame_reader u_frame_reader_trans (
        .clk_pix(clk_pix), .rst_n_pix(rst_n_pix),
        .clk_mem(clk_mem), .rst_n_mem(rst_n_mem),
        .fb_base(22'h04B000), .frame_start(vt_frame_start),
        .line_start(vt_line_start), .de(vt_de & tr_need_second),
        .px_rgb(rgb_next), .underrun(tr_underrun), .primed(), .urgent(),
        .disp_req_valid(tr_req_valid), .disp_req_ready(tr_req_ready),
        .disp_req_addr(tr_req_addr),   .disp_req_we(tr_req_we), .disp_req_len(tr_req_len),
        .disp_wr_valid(tr_wr_valid),   .disp_wr_ready(tr_wr_ready), .disp_wr_data(tr_wr_data),
        .disp_rd_valid(tr_rd_valid),   .disp_rd_ready(tr_rd_ready), .disp_rd_data(tr_rd_data));

    transition_engine u_transition_engine (
        .clk(clk_pix), .rst_n(rst_n_pix),
        .start(1'b0), .mode(param_pix[35:32]), .duration(8'd30),
        .frame_start(vt_frame_start), .x(vt_x), .y(vt_y), .de(vt_de),
        .rgb_cur(rgb_cur), .rgb_next(rgb_next), .rgb_out(rgb_trans),
        .need_second(tr_need_second), .busy(), .done());

    wire [13:0] font_addr;  wire [31:0] font_dout;
    font_rom u_font_rom (.clk(clk_pix), .addr(font_addr), .dout(font_dout));

    wire [23:0] osd_rgb;   wire [7:0] osd_alpha;
    osd_renderer u_osd_renderer (
        .clk(clk_pix), .rst_n(rst_n_pix),
        .x(vt_x), .y(vt_y), .de(vt_de),
        .line_start(vt_line_start), .frame_start(vt_frame_start),
        .frame_cnt(vt_frame_cnt),
        .qstate(qstate_pix), .param(param_pix),
        .cfg_we(1'b0), .cfg_addr(10'd0), .cfg_wdata(32'd0),
        .font_addr(font_addr), .font_dout(font_dout),
        .osd_rgb(osd_rgb), .osd_alpha(osd_alpha));

    //========================================================================
    // Audio pipeline (clk_pix)
    //========================================================================
    wire        aud_stb;
    wire [15:0] tone_sample, pcm_sample, aud_l, aud_r;
    wire        play_req, play_busy, play_done, pcm_underrun;
    wire [21:0] play_base, play_samples;

    audio_sample_clk u_audio_sample_clk (
        .clk(clk_pix), .rst_n(rst_n_pix), .stb(aud_stb));

    audio_tone_gen u_audio_tone_gen (
        .clk(clk_pix), .rst_n(rst_n_pix), .stb(aud_stb), .enable(1'b1),
        .freq_inc(24'd349525), .amplitude(8'd128), .sample(tone_sample));

    audio_announcer u_audio_announcer (
        .clk(clk_pix), .rst_n(rst_n_pix),
        .call_pulse(call_pulse_pix), .call_ticket(qstate_pix[15:0]),
        .call_room(qstate_pix[27:24]), .call_prio(qstate_pix[32]),
        .call_recall(qstate_pix[33]),
        .clip_sel(clip_sel), .clip_base(clip_base), .clip_samples(clip_samples),
        .play_req(play_req), .play_base(play_base), .play_samples(play_samples),
        .play_busy(play_busy), .play_done(play_done), .announcing());

    audio_pcm_player u_audio_pcm_player (
        .clk_pix(clk_pix), .rst_n_pix(rst_n_pix),
        .clk_mem(clk_mem), .rst_n_mem(rst_n_mem),
        .stb(aud_stb), .play_req(play_req),
        .play_base(play_base), .play_samples(play_samples),
        .play_busy(play_busy), .play_done(play_done),
        .sample(pcm_sample), .underrun(pcm_underrun),
        .aud_req_valid(aud_req_valid), .aud_req_ready(aud_req_ready),
        .aud_req_addr(aud_req_addr),   .aud_req_we(aud_req_we), .aud_req_len(aud_req_len),
        .aud_wr_valid(aud_wr_valid),   .aud_wr_ready(aud_wr_ready), .aud_wr_data(aud_wr_data),
        .aud_rd_valid(aud_rd_valid),   .aud_rd_ready(aud_rd_ready), .aud_rd_data(aud_rd_data));

    audio_mixer u_audio_mixer (
        .clk(clk_pix), .rst_n(rst_n_pix), .stb(aud_stb),
        .tone_in(tone_sample), .pcm_in(pcm_sample), .volume(param_pix[23:16]),
        .aud_l(aud_l), .aud_r(aud_r));

    wire       bin_valid;  wire [3:0] bin_idx;  wire [7:0] bin_mag, aud_level;
    goertzel_spectrum u_goertzel_spectrum (
        .clk(clk_pix), .rst_n(rst_n_pix), .stb(aud_stb), .sample(aud_l),
        .bin_valid(bin_valid), .bin_idx(bin_idx), .bin_mag(bin_mag), .level(aud_level));

    wire [23:0] spec_rgb;  wire [7:0] spec_alpha;
    spectrum_render u_spectrum_render (
        .clk(clk_pix), .rst_n(rst_n_pix),
        .x(vt_x), .y(vt_y), .de(vt_de), .frame_start(vt_frame_start),
        .mode(param_pix[39:36]),
        .bin_valid(bin_valid), .bin_idx(bin_idx), .bin_mag(bin_mag),
        .level(aud_level), .sample(aud_l), .stb(aud_stb),
        .spec_rgb(spec_rgb), .spec_alpha(spec_alpha));

    //========================================================================
    // Final composition and HDMI transmit
    //========================================================================
    wire        co_de, co_hs, co_vs;  wire [23:0] co_rgb;
    osd_compositor u_osd_compositor (
        .clk(clk_pix), .rst_n(rst_n_pix),
        .de_in(vt_de), .hs_in(vt_hs), .vs_in(vt_vs), .rgb_base(rgb_trans),
        .osd_rgb(osd_rgb), .osd_alpha(osd_alpha),
        .spec_rgb(spec_rgb), .spec_alpha(spec_alpha), .param(param_pix),
        .de_out(co_de), .hs_out(co_hs), .vs_out(co_vs), .rgb_out(co_rgb));

    wire [9:0] tmds_ch0, tmds_ch1, tmds_ch2;
    hdmi_tx_core u_hdmi_tx_core (
        .clk(clk_pix), .rst_n(rst_n_pix),
        .vid_de(co_de), .vid_hs(co_hs), .vid_vs(co_vs), .vid_rgb(co_rgb),
        .aud_stb(aud_stb), .aud_l(aud_l), .aud_r(aud_r),
        .tmds_ch0(tmds_ch0), .tmds_ch1(tmds_ch1), .tmds_ch2(tmds_ch2),
        .aud_overflow(), .aud_underflow());

    // Four identical serialisers keep all lanes latency-matched.
    // The clock lane sends a fixed 10'b1111100000 pattern.
    tmds_serdes u_ser_clk (.clk_pix(clk_pix), .clk_ser(clk_ser), .rst_n(rst_n_pix),
                           .din(10'b1111100000), .sdata_p(HDMI_CLK_P));
    tmds_serdes u_ser_d0  (.clk_pix(clk_pix), .clk_ser(clk_ser), .rst_n(rst_n_pix),
                           .din(tmds_ch0),     .sdata_p(HDMI_D0_P));
    tmds_serdes u_ser_d1  (.clk_pix(clk_pix), .clk_ser(clk_ser), .rst_n(rst_n_pix),
                           .din(tmds_ch1),     .sdata_p(HDMI_D1_P));
    tmds_serdes u_ser_d2  (.clk_pix(clk_pix), .clk_ser(clk_ser), .rst_n(rst_n_pix),
                           .din(tmds_ch2),     .sdata_p(HDMI_D2_P));

    //========================================================================
    // Differentiating features: latency + AV sync instrumentation
    //========================================================================
    latency_probe u_latency_probe (
        .clk_sys(clk_sys), .rst_n_sys(rst_n_sys),
        .clk_pix(clk_pix), .rst_n_pix(rst_n_pix),
        .start_evt(key_press[0]), .stop_evt(vt_frame_start),
        .lat_us(), .lat_frames(), .lat_valid());

    av_sync_monitor u_av_sync_monitor (
        .clk(clk_pix), .rst_n(rst_n_pix),
        .frame_start(vt_frame_start), .aud_stb(aud_stb),
        .samples_per_frame(), .fs_measured_hz(), .drift_ppm());

    //========================================================================
    // Status LEDs
    //========================================================================
    assign LED = {disp_underrun | pcm_underrun,   // 3: any real-time underrun
                  sdram_init_done,                 // 2: SDRAM ready
                  assets_ok,                       // 1: assets loaded
                  qstate_sys[34]};                 // 0: auto-call mode

endmodule

// media_carousel_20261103: board ports remain unchanged.
// Concrete media/control/CDC instances are in top.v and interface_contract.yaml.

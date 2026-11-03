//============================================================================
// MedQ - HDMI outpatient queue-calling terminal
// Integrated MedQ top, original Anlogic clock/serializer/SDRAM primitives.
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

module top #(parameter SD_INIT_DIV=62, SD_DATA_DIV=1, SD_RESPONSE_LIMIT=255,
    SERVICE_STARTUP_CYCLES=100000000, FEEDBACK_CYCLES=3750000,
    INPUT_DEBOUNCE_CYCLES=250000, INPUT_INIT_CYCLES=250000,
    parameter [63:0] CALL_INTERVAL_CYCLES=64'd25000000*64'd30) (
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
    wire clk_sys;                            // 50 MHz, PLL feedback global clock
    wire clk_pix;                            // 25 MHz
    wire clk_ser;                            // 125 MHz
    wire clk_mem;                            // 50 MHz
    wire clk_sdram;                          // 50 MHz, +8 ns / 144 degrees
    wire pll_locked;

    wire rst_n_sys, rst_n_pix, rst_n_mem;
    wire [7:0] service_status_sys,service_status_pix;

`ifdef SIMULATION
    assign clk_sys=clk50mhz;
    // Preserve the established behavioral clock profile for business regression.
    // generate with TD IP Generator -> rtl/al_ip/clk_wize.v  (ALREADY PRESENT, reused from DEMO 31)
    // 50 MHz -> C0 125 MHz (clk_ser), C1 25 MHz (clk_pix)
    clk_wize u_clk_wize (
        .refclk   (clk50mhz),
        .reset    (1'b0),
        .clk0_out (clk_ser),
        .clk1_out (clk_pix)
    );

    // generate with TD IP Generator -> rtl/al_ip/pll_mem.v   (NOT YET GENERATED, needs TD)
    // Behavioral counterpart of sys_pll: 50 MHz and +8 ns SDRAM clock.
    pll_mem u_pll_mem (
        .refclk   (clk50mhz),
        .reset    (1'b0),
        .extlock  (pll_locked),
        .clk0_out (clk_mem),
        .clk1_out (clk_sdram)
    );
`else
    wire video_locked,memory_locked;
    assign pll_locked=video_locked & memory_locked;
    medq_pll u_medq_pll (
        .refclk(clk50mhz), .reset(1'b0), .extlock(video_locked),
        .clk0_out(clk_ser), .clk1_out(clk_pix), .clk2_out()
    );
    // Timing-closed memory profile: C0/C1 50 MHz, C2 50 MHz / 144 degrees.
    sys_pll u_sys_pll (
        .refclk(clk50mhz),.reset(1'b0),.extlock(memory_locked),
        .clk0_out(clk_sys),.clk1_out(clk_mem),.clk2_out(clk_sdram)
    );
`endif

    rst_sync #(.POR_CYCLES(50000)) u_rst_sys (
        .clk(clk_sys), .ext_rst_n(pll_locked), .pll_locked(pll_locked), .rst_n_out(rst_n_sys));
    rst_sync #(.POR_CYCLES(25000)) u_rst_pix (
        .clk(clk_pix), .ext_rst_n(pll_locked), .pll_locked(pll_locked), .rst_n_out(rst_n_pix));
    rst_sync #(.POR_CYCLES(50000)) u_rst_mem (
        .clk(clk_mem), .ext_rst_n(pll_locked), .pll_locked(pll_locked), .rst_n_out(rst_n_mem));

    //========================================================================
    // Control plane (clk_sys)
    //========================================================================
    wire [3:0] key_press,board_keys,board_switches;
    wire [1:0] doctor_event,call_grant,call_request,request_return;
    wire [15:0] request_ticket;
    wire [1:0] running;
    wire inputs_ready,clinic_visible,clinic_enable,media_show;
    wire [6:0] photo_alpha;
    wire [21:0] media_fb_pix,media_fb_mem;
    wire [2:0] media_valid_sys,media_valid_pix;
    medq_board_inputs u_board_inputs(.clk(clk_pix),.rst_n(rst_n_pix),.keys(KEY),.switches(SW),
        .keys_sync(board_keys),.switches_sync(board_switches));
    medq_v03_inputs #(.DEBOUNCE_CYCLES(INPUT_DEBOUNCE_CYCLES),.INIT_CYCLES(INPUT_INIT_CYCLES)) u_inputs(
        .clk(clk_pix),.rst_n(rst_n_pix && clinic_enable),.keys_sync(board_keys),.switches_sync(board_switches),
        .running(running),.ready(inputs_ready),.enqueue(key_press),.doctor_event(doctor_event));

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

    wire [127:0] qstate_sys,qstate_pix,qstate_service;
    wire [1:0] announcement_start;
    wire call_pulse_sys,call_pulse_pix;
    wire [15:0] call_ticket_pix={8'd0,call_grant[1] ? request_ticket[15:8] : request_ticket[7:0]};
    wire [3:0] call_room_pix=call_grant[1] ? 4'd2 : 4'd1;
    assign call_pulse_pix=|call_grant;
    medq_dual_service #(.INTERVAL_CYCLES(CALL_INTERVAL_CYCLES)) u_dual_service(
        .clk(clk_pix),.rst_n(rst_n_pix),.running(running),.inputs_ready(inputs_ready),.enqueue(key_press),
        .doctor_event(doctor_event),.grant(call_grant),.request(call_request),.request_ticket(request_ticket),
        .request_return(request_return),.qstate(qstate_service));
    medq_subtitle_notify u_subtitle_notify(.clk(clk_pix),.rst_n(rst_n_pix),
        .state_in(qstate_service),.announcement_start(announcement_start),.grant(call_grant),.state_out(qstate_pix));
    cdc_pulse u_call_indicator_cdc(.src_clk(clk_pix),.src_rst_n(rst_n_pix),.src_pulse(call_pulse_pix),.src_busy(),
        .dst_clk(clk_sys),.dst_rst_n(rst_n_sys),.dst_pulse(call_pulse_sys));

    wire [63:0] param_sys;
    wire clinic_enable_sys;
    cdc_sync_bit u_clinic_enable_sys(.clk(clk_sys),.rst_n(rst_n_sys),.d_in(clinic_enable),.d_out(clinic_enable_sys));
    param_ctrl u_param_ctrl (
        .clk(clk_sys), .rst_n(rst_n_sys),
        .key_press(4'd0), .key_hold(4'd0), .sw(4'hf),
        .ext_we(cmd_param_we && clinic_enable_sys), .ext_sel(cmd_param_sel), .ext_val(cmd_param_val),
        .param(param_sys), .osd_hint_id(), .osd_hint_val(), .osd_hint_vis());

    seg_scan u_seg_scan (
        .clk(clk_sys), .rst_n(rst_n_sys),
        .digits({16'h0,qstate_sys[39:32],qstate_sys[7:0]}), .dp(8'h00), .blank(8'h00),
        .seg_data(SEG_DATA), .seg_sel(SEG_SEL));


    //========================================================================
    // Storage chain (clk_sys) -> SDRAM write master (clk_mem)
    //========================================================================
    wire        wr_req_valid, wr_req_ready, wr_req_we, wr_wr_valid, wr_wr_ready;
    wire        wr_rd_valid,  wr_rd_ready;
    wire [21:0] wr_req_addr;  wire [8:0] wr_req_len;
    wire [31:0] wr_wr_data,   wr_rd_data;
    wire        assets_ok,asset_error;    wire [3:0] load_progress;
    wire [5:0] img_count; wire [6:0] pcm_count;
    wire [5:0]  clip_sel;     wire [21:0] clip_base, clip_samples;

    asset_loader #(.SD_INIT_DIV(SD_INIT_DIV),.SD_DATA_DIV(SD_DATA_DIV),.SD_RESPONSE_LIMIT(SD_RESPONSE_LIMIT),.MEDIA_PROFILE(1)) u_asset_loader (
        .clk_sys(clk_sys), .rst_n_sys(rst_n_sys),
        .clk_mem(clk_mem), .rst_n_mem(rst_n_mem),
        .load_req(1'b0), .img_sel(5'd0), .fb_sel(2'd0),
        .load_busy(), .load_done(), .load_err(asset_error),
        .img_count(img_count), .pcm_count(pcm_count),
        .assets_ok(assets_ok), .media_valid(media_valid_sys), .progress(load_progress),
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
    wire        sdram_init_done,memory_fault;
    wire main_urgent;

    sdram_arbiter u_sdram_arbiter (
        .clk(clk_mem), .rst_n(rst_n_mem),
        .aud_req_valid(aud_req_valid),  .aud_req_ready(aud_req_ready),
        .aud_req_addr(aud_req_addr),    .aud_req_we(aud_req_we), .aud_req_len(aud_req_len),
        .aud_wr_valid(aud_wr_valid),    .aud_wr_ready(aud_wr_ready), .aud_wr_data(aud_wr_data),
        .aud_rd_valid(aud_rd_valid),    .aud_rd_ready(aud_rd_ready), .aud_rd_data(aud_rd_data),
        .disp_req_valid(disp_req_valid),.disp_urgent(main_urgent),.disp_req_ready(disp_req_ready),
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
        .clk(clk_mem), .clk_sdram(clk_sdram), .rst_n(rst_n_mem),
        .mem_req_valid(mem_req_valid),  .mem_req_ready(mem_req_ready),
        .mem_req_addr(mem_req_addr),    .mem_req_we(mem_req_we), .mem_req_len(mem_req_len),
        .mem_wr_valid(mem_wr_valid),    .mem_wr_ready(mem_wr_ready), .mem_wr_data(mem_wr_data),
        .mem_rd_valid(mem_rd_valid),    .mem_rd_ready(mem_rd_ready), .mem_rd_data(mem_rd_data),
        .init_done(sdram_init_done),.fault(memory_fault));

    //========================================================================
    // CDC: control plane (clk_sys) -> video plane (clk_pix)
    //========================================================================
    wire [63:0]  param_pix;

    cdc_bus_handshake #(.W(128)) u_cdc_qstate (
        .src_clk(clk_pix), .src_rst_n(rst_n_pix), .src_data(qstate_pix),
        .dst_clk(clk_sys), .dst_rst_n(rst_n_sys), .dst_data(qstate_sys));

    cdc_bus_handshake #(.W(64)) u_cdc_param (
        .src_clk(clk_sys), .src_rst_n(rst_n_sys), .src_data(param_sys),
        .dst_clk(clk_pix), .dst_rst_n(rst_n_pix), .dst_data(param_pix));

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

    cdc_bus_handshake #(.W(3)) u_media_valid_cdc(
        .src_clk(clk_sys),.src_rst_n(rst_n_sys),.src_data(media_valid_sys),
        .dst_clk(clk_pix),.dst_rst_n(rst_n_pix),.dst_data(media_valid_pix));
    medq_media_control #(.DEBOUNCE_CYCLES(INPUT_DEBOUNCE_CYCLES)) u_media_control(
        .clk(clk_pix),.rst_n(rst_n_pix),.frame_start(vt_frame_start),.keys_sync(board_keys),
        .media_valid(media_valid_pix),.clinic_visible(clinic_visible),.clinic_enable(clinic_enable),
        .fb_base(media_fb_pix),.media_show(media_show),.photo_alpha(photo_alpha));
    cdc_bus_handshake #(.W(22)) u_media_base_cdc(
        .src_clk(clk_pix),.src_rst_n(rst_n_pix),.src_data(media_fb_pix),
        .dst_clk(clk_mem),.dst_rst_n(rst_n_mem),.dst_data(media_fb_mem));

    wire [23:0] rgb_cur, rgb_next, rgb_trans, rgb_prefetched;
    wire        disp_underrun, tr_underrun, tr_need_second;
    wire main_primed;
    reg frame_data_enabled;
    // SDRAM power-up may span initial active lines. Keep the loading OSD on a
    // defined background, prefill the FIFO, then start only at a frame boundary.
    always @(posedge clk_pix or negedge rst_n_pix)begin
        if(!rst_n_pix)frame_data_enabled<=0;
        else if(vt_frame_start && main_primed)frame_data_enabled<=1;
    end
    assign rgb_cur=frame_data_enabled && media_show ? rgb_prefetched : 24'd0;

    frame_reader u_frame_reader_main (
        .clk_pix(clk_pix), .rst_n_pix(rst_n_pix),
        .clk_mem(clk_mem), .rst_n_mem(rst_n_mem),
        .fb_base(media_fb_mem), .frame_start(vt_frame_start),
        .line_start(vt_line_start), .de(vt_de && frame_data_enabled),
        .px_rgb(rgb_prefetched), .underrun(disp_underrun), .primed(main_primed), .urgent(main_urgent),
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
    // Two compact AA pages: unchanged clinic glyphs plus operation messages.
    wire [12:0] compact_font_addr=font_addr[12:0]-13'd3584;
    font_rom #(.ADDR_W(13),.HEXFILE("font_v03.hex")) u_font_rom (
        .clk(clk_pix), .addr(compact_font_addr), .dout(font_dout));

    wire [23:0] osd_rgb;   wire [7:0] osd_alpha;
    osd_renderer #(.LIVE_STATUS(1),.DUAL(1),.MEDIA_LAYOUT(1)) u_osd_renderer (
        .clk(clk_pix), .rst_n(rst_n_pix),
        .x(vt_x), .y(vt_y), .de(vt_de),
        .line_start(vt_line_start), .frame_start(vt_frame_start),
        .frame_cnt(vt_frame_cnt),
        .qstate(qstate_pix), .param(param_pix), .service_status(service_status_pix),
        .cover_mode(!clinic_visible),.media_show(media_show),.photo_alpha(photo_alpha),
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

    wire fallback_tone,pcm_abort,active_room;
    assign BUZZER=fallback_tone && tone_sample[15];
    audio_tone_gen u_audio_tone_gen (
        .clk(clk_pix), .rst_n(rst_n_pix), .stb(aud_stb && (|running)), .enable(fallback_tone),
        .freq_inc(24'd349525), .amplitude(8'd128), .sample(tone_sample));
    medq_dual_announcer #(.TONE_CYCLES(FEEDBACK_CYCLES)) u_dual_announcer(
        .clk(clk_pix),.rst_n(rst_n_pix),.running(running),.voice_ready(service_status_pix[1:0]==2'd1),
        .request(call_request),.request_ticket(request_ticket),.request_return(request_return),.doctor_event(doctor_event),.qstate(qstate_pix),
        .grant(call_grant),.announcement_start(announcement_start),.clip_sel(clip_sel),.clip_base(clip_base),.clip_samples(clip_samples),
        .play_req(play_req),.play_base(play_base),.play_samples(play_samples),.play_busy(play_busy),.play_done(play_done),
        .pcm_abort(pcm_abort),.fallback_tone(fallback_tone),.announcing(),.active_room(active_room),.active_ticket());

    audio_pcm_player #(.CONTROLLED(1)) u_audio_pcm_player (
        .clk_pix(clk_pix), .rst_n_pix(rst_n_pix),
        .clk_mem(clk_mem), .rst_n_mem(rst_n_mem),
        .stb(aud_stb), .run_enable(|running),.abort_play(pcm_abort),.play_req(play_req),
        .play_base(play_base), .play_samples(play_samples),
        .play_busy(play_busy), .play_done(play_done),
        .sample(pcm_sample), .underrun(pcm_underrun),
        .aud_req_valid(aud_req_valid), .aud_req_ready(aud_req_ready),
        .aud_req_addr(aud_req_addr),   .aud_req_we(aud_req_we), .aud_req_len(aud_req_len),
        .aud_wr_valid(aud_wr_valid),   .aud_wr_ready(aud_wr_ready), .aud_wr_data(aud_wr_data),
        .aud_rd_valid(aud_rd_valid),   .aud_rd_ready(aud_rd_ready), .aud_rd_data(aud_rd_data));

    audio_mixer u_audio_mixer (
        .clk(clk_pix), .rst_n(rst_n_pix), .stb(aud_stb),
        .tone_in(fallback_tone ? tone_sample : 16'd0), .pcm_in(running[active_room] ? pcm_sample : 16'd0), .volume(param_pix[23:16]),
        .aud_l(aud_l), .aud_r(aud_r));

    wire [23:0] spec_rgb;  wire [7:0] spec_alpha;
    medq_audio_wave u_audio_wave(.clk(clk_pix),.rst_n(rst_n_pix),.frame_start(vt_frame_start),
        .x(vt_x),.y(vt_y),.de(vt_de),.enabled(clinic_visible),.sample(aud_l),.stb(aud_stb),
        .rgb(spec_rgb),.alpha(spec_alpha));

    //========================================================================
    // Final composition and HDMI transmit
    //========================================================================
    wire        co_de, co_hs, co_vs;  wire [23:0] co_rgb;
    wire aligned_de, aligned_hs, aligned_vs;
    wire [23:0] aligned_spec_rgb;
    wire [7:0] aligned_spec_alpha;
    medq_video_align u_video_align (
        .clk(clk_pix),.rst_n(rst_n_pix),.de(vt_de),.hs(vt_hs),.vs(vt_vs),
        .spec_rgb(spec_rgb),.spec_alpha(spec_alpha),
        .de_out(aligned_de),.hs_out(aligned_hs),.vs_out(aligned_vs),
        .spec_rgb_out(aligned_spec_rgb),.spec_alpha_out(aligned_spec_alpha));
    osd_compositor u_osd_compositor (
        .clk(clk_pix), .rst_n(rst_n_pix),
        .de_in(aligned_de), .hs_in(aligned_hs), .vs_in(aligned_vs), .rgb_base(rgb_trans),
        .osd_rgb(osd_rgb), .osd_alpha(osd_alpha),
        .spec_rgb(aligned_spec_rgb), .spec_alpha(aligned_spec_alpha), .param(param_pix),
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
    wire memory_ready_sys,memory_fault_sys,underrun_sys;
    cdc_sync_bit u_ready_sync(.clk(clk_sys),.rst_n(rst_n_sys),.d_in(sdram_init_done),.d_out(memory_ready_sys));
    cdc_sync_bit u_fault_sync(.clk(clk_sys),.rst_n(rst_n_sys),.d_in(memory_fault),.d_out(memory_fault_sys));
    cdc_sync_bit u_underrun_sync(.clk(clk_sys),.rst_n(rst_n_sys),.d_in(disp_underrun | pcm_underrun),.d_out(underrun_sys));
    medq_service_guard #(.STARTUP_CYCLES(SERVICE_STARTUP_CYCLES)) u_service_guard(
        .clk(clk_sys),.rst_n(rst_n_sys),.assets_ok(assets_ok && pcm_count==54),.load_error(asset_error || (assets_ok && pcm_count!=54)),
        .memory_ready(memory_ready_sys),.memory_fault(memory_fault_sys),.underrun(underrun_sys),
        .progress(load_progress),.service_status(service_status_sys));
    cdc_bus_handshake #(.W(8)) u_service_cdc(.src_clk(clk_sys),.src_rst_n(rst_n_sys),.src_data(service_status_sys),
        .dst_clk(clk_pix),.dst_rst_n(rst_n_pix),.dst_data(service_status_pix));

    assign LED = {service_status_sys[3] | (service_status_sys[1:0]==2'd3),   // 3: any real-time underrun
                  sdram_init_done,                 // 2: SDRAM ready
                  assets_ok,                       // 1: assets loaded
                  qstate_sys[64]};                 // 0: auto-call mode

endmodule

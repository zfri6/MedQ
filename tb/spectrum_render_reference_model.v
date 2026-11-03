//============================================================================
// spectrum_render.v
// Spectrum / waveform / volume-bar visualizer.
//
// Fixed region: bottom-right, 192×96 pixels (x=448..639, y=384..479).
//
// Modes (param[39:36]):
//   0 = off (transparent)
//   1 = Bar spectrum:   16 vertical bars, 12px wide each, height = bin_mag
//   2 = Waveform:       scrolling audio waveform, ±40px from center line
//   3 = Volume bar:     horizontal bar, width = level
//
// goertzel_spectrum drives bin_valid/bin_idx/bin_mag/level on every block.
// audio_mixer drives sample (stb-gated).
//
// Domain: clk_pix
//============================================================================
`timescale 1ns / 1ps

module spectrum_render_reference (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [9:0]  x,
    input  wire [9:0]  y,
    input  wire        de,
    input  wire        frame_start,
    input  wire [3:0]  mode,
    input  wire        bin_valid,
    input  wire [3:0]  bin_idx,
    input  wire [7:0]  bin_mag,
    input  wire [7:0]  level,
    input  wire [15:0] sample,
    input  wire        stb,
    // These are passthrough-style: we output our own RGB/alpha
    output reg  [23:0] spec_rgb,
    output reg  [7:0]  spec_alpha
);

    //========================================================================
    // Constants
    //========================================================================
    // Region: x=448..639 (192px), y=384..479 (96px)
    localparam REGION_X0 = 10'd448;
    localparam REGION_X1 = 10'd639;
    localparam REGION_Y0 = 10'd384;
    localparam REGION_Y1 = 10'd479;
    localparam REGION_W  = 192;
    localparam REGION_H  = 96;

    // Bar mode
    localparam BAR_W     = 12;     // pixels per bar
    localparam BAR_COUNT = 16;
    localparam BAR_H_MAX = 80;     // max bar height in pixels
    localparam BAR_Y0    = 10'd399; // bottom of bars (y = 479 - 80)

    // Waveform mode
    localparam WAVE_CY   = 10'd432;  // vertical center
    localparam WAVE_AMP  = 10'd40;   // ±40px amplitude

    // Volume bar mode
    localparam VOL_Y0    = 10'd464;
    localparam VOL_H     = 16;

    // Colors
    localparam C_GREEN  = 24'h00FF00;
    localparam C_YELLOW = 24'hFFFF00;
    localparam C_RED    = 24'hFF4040;
    localparam C_DIM    = 24'h003000;
    localparam C_BLACK  = 24'h000000;

    //========================================================================
    // Spectrum bin registers (16 bins)
    //========================================================================
    reg [7:0] bin_reg [0:15];

    // Overall level
    reg [7:0] level_reg;

    // Waveform ring buffer: 256 entries, 16-bit signed samples
    reg [15:0] wave_buf [0:255];
    reg [7:0]  wave_wr_ptr;

    //========================================================================
    // Update on bin_valid / stb
    //========================================================================
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 16; i = i + 1) bin_reg[i] <= 8'd0;
            level_reg    <= 8'd0;
            wave_wr_ptr <= 8'd0;
            for (i = 0; i < 256; i = i + 1) wave_buf[i] <= 16'd0;
        end else begin
            if (bin_valid)
                bin_reg[bin_idx] <= bin_mag;
            if (stb) begin
                level_reg       <= level;
                wave_buf[wave_wr_ptr] <= sample;
                wave_wr_ptr <= wave_wr_ptr + 8'd1;
            end
        end
    end

    //========================================================================
    // Region detection
    //========================================================================
    wire in_region = (x >= REGION_X0) && (x <= REGION_X1) &&
                     (y >= REGION_Y0) && (y <= REGION_Y1);

    wire [9:0] lx = x - REGION_X0;  // 0..191
    wire [9:0] ly = y - REGION_Y0;  // 0..95

    //========================================================================
    // Bar spectrum mode (mode == 1)
    //========================================================================
    // 16 bars, 12px wide each: bar 0 at x=448..459, bar 15 at x=618..629
    wire [3:0] bar_idx = (lx / 10'd12);   // 0..15
    wire [9:0] bar_x0  = {6'd0, bar_idx} * 10'd12;
    wire [9:0] bar_x1  = bar_x0 + 10'd12 - 10'd1;

    // Bar height: bin_mag * BAR_H_MAX / 255
    wire [9:0] bar_height = ({2'd0, bin_reg[bar_idx]} * 10'd80) >> 8;
    wire [9:0] bar_y0 = BAR_Y0;                    // bottom
    wire [9:0] bar_y1 = BAR_Y0 - bar_height + 10'd1; // top

    wire bar_in_x = (x >= bar_x0) && (x <= bar_x1);
    wire bar_in_y = (y >= bar_y1) && (y <= bar_y0);
    wire bar_hit  = in_region && bar_in_x && bar_in_y && (mode == 4'd1);

    wire [23:0] bar_color = (bin_reg[bar_idx] > 8'd180) ? C_RED    :
                             (bin_reg[bar_idx] > 8'd100) ? C_YELLOW : C_GREEN;

    //========================================================================
    // Waveform mode (mode == 2)
    //========================================================================
    // Scroll: rightmost pixel (lx=191) shows newest sample (wave_wr_ptr-1)
    //          leftmost pixel  (lx=0)   shows oldest sample (wave_wr_ptr-192)
    // Read address: (wave_wr_ptr - 192 + lx) mod 256
    wire [7:0] wave_rd_idx = wave_wr_ptr - 8'd192 + lx[7:0];  // wraps naturally
    wire [15:0] wave_samp  = wave_buf[wave_rd_idx];

    // Normalize signed sample (±32768) to pixel offset (±WAVE_AMP)
    // wave_samp is unsigned 16-bit (from audio_mixer output, signed PCM)
    wire signed [16:0] s_offset = {1'b0, wave_samp} - 17'd32768; // 0 centered
    wire signed [9:0]  y_offset = (s_offset * 17'd40) >>> 16;    // ±40px
    wire [9:0] wave_y_pixel = WAVE_CY + y_offset;                 // absolute y

    wire wave_hit = in_region && (mode == 4'd2) &&
                    (y >= wave_y_pixel - 10'd1) && (y <= wave_y_pixel + 10'd1);

    //========================================================================
    // Volume bar mode (mode == 3)
    //========================================================================
    wire [9:0] vol_fill_w = ({2'd0, level_reg} * 10'd192) >> 8; // 0..192
    wire vol_hit = in_region && (mode == 4'd3) &&
                   (y >= VOL_Y0) && (y < VOL_Y0 + 10'd16) &&
                   (lx < vol_fill_w);

    wire [23:0] vol_color = (level_reg > 8'd180) ? C_RED    :
                             (level_reg > 8'd100) ? C_YELLOW : C_GREEN;

    //========================================================================
    // Combine and output
    //========================================================================
    wire any_hit = bar_hit || wave_hit || vol_hit;

    wire [23:0] hit_rgb = bar_hit ? bar_color  :
                           wave_hit ? C_GREEN  :
                           vol_hit  ? vol_color :
                           C_BLACK;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            spec_rgb   <= 24'd0;
            spec_alpha <= 8'd0;
        end else begin
            if (in_region && any_hit) begin
                spec_rgb   <= hit_rgb;
                spec_alpha <= 8'd255;   // fully opaque
            end else begin
                // Transparent outside our region
                spec_rgb   <= 24'd0;
                spec_alpha <= 8'd0;
            end
        end
    end

endmodule

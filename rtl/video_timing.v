//============================================================================
// video_timing.v
// 640x480@60 Standard Video Timing Generator
//
// Pixel clock: 25.000 MHz
// H total = 640 + 16 + 96 + 48 = 800
// V total = 480 + 10 +  2 + 33 = 525
// HS/VS: negative polarity
//
// Domain: clk_pix
//============================================================================
`timescale 1ns / 1ps

module video_timing #(
    // Horizontal timing (pixel clocks)
    parameter H_ACT  = 640,
    parameter H_FP   = 16,
    parameter H_SYNC = 96,
    parameter H_BP   = 48,
    // Vertical timing (scanlines)
    parameter V_ACT  = 480,
    parameter V_FP   = 10,
    parameter V_SYNC = 2,
    parameter V_BP   = 33
) (
    input  wire        clk,
    input  wire        rst_n,

    output reg         de,
    output reg         hs,
    output reg         vs,
    output reg  [9:0]  x,
    output reg  [9:0]  y,
    output wire        frame_start,
    output wire        line_start,
    output reg  [15:0] frame_cnt
);

    localparam H_TOTAL = H_ACT + H_FP + H_SYNC + H_BP;  // 800
    localparam V_TOTAL = V_ACT + V_FP + V_SYNC + V_BP;  // 525

    reg [9:0] h_cnt;
    reg [9:0] v_cnt;

    // -------------------------------------------------------------------------
    // Counters
    // -------------------------------------------------------------------------
    wire h_end = (h_cnt == H_TOTAL - 1);
    wire v_end = (v_cnt == V_TOTAL - 1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            h_cnt <= {10{1'b0}};
        end else begin
            h_cnt <= h_end ? {10{1'b0}} : (h_cnt + 10'd1);
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v_cnt <= V_ACT;  // start in blanking so frame/OSD prefetch can fill
        end else begin
            if (h_end) begin
                v_cnt <= v_end ? {10{1'b0}} : (v_cnt + 10'd1);
            end
        end
    end

    // -------------------------------------------------------------------------
    // Sync pulses — negative polarity
    // -------------------------------------------------------------------------
    wire h_sync_zone = (h_cnt >= H_ACT + H_FP) && (h_cnt < H_ACT + H_FP + H_SYNC);
    wire v_sync_zone = (v_cnt >= V_ACT + V_FP) && (v_cnt < V_ACT + V_FP + V_SYNC);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) hs <= 1'b1;
        else        hs <= h_sync_zone ? 1'b0 : 1'b1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) vs <= 1'b1;
        else        vs <= v_sync_zone ? 1'b0 : 1'b1;
    end

    // -------------------------------------------------------------------------
    // Display enable — active within the visible window
    // -------------------------------------------------------------------------
    wire h_active = (h_cnt < H_ACT);
    wire v_active = (v_cnt < V_ACT);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) de <= 1'b0;
        else        de <= h_active && v_active;
    end

    // -------------------------------------------------------------------------
    // Pixel coordinates — hold last value outside active region
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x <= {10{1'b0}};
            y <= {10{1'b0}};
        end else begin
            if (h_active && v_active) x <= h_cnt;   // 0..639
            if (h_active && v_active) y <= v_cnt;   // 0..479
        end
    end

    // -------------------------------------------------------------------------
    // Frame counter — increments on falling edge of VS (start of each frame)
    // -------------------------------------------------------------------------
    reg vs_d1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vs_d1     <= 1'b1;         // vs starts high; avoid spurious edge at rst_n=0
            frame_cnt <= {16{1'b0}};
        end else begin
            vs_d1 <= vs;
            if (!vs && vs_d1)          // rising edge of low = falling edge of vs
                frame_cnt <= frame_cnt + 16'd1;
        end
    end

    // -------------------------------------------------------------------------
    // frame_start / line_start: one cycle before first active pixel
    //
    // line_start: fires at h_end (h_cnt == H_TOTAL-1) — the last cycle of
    //             each line. The next cycle has h_cnt==0 and is the first pixel.
    // frame_start: fires at h_end AND v_cnt==0 — the last cycle of line 0.
    //             The next cycle has h_cnt==0, v_cnt==0 and is the first
    //             active pixel of the frame.
    // -------------------------------------------------------------------------
    assign line_start  = h_end;
    assign frame_start  = h_end && v_end;

endmodule

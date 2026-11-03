//============================================================================
// transition_engine.v
// Video transition effects between two frame buffers.
//
// Modes:
//   1 = Fade:       alpha-blend rgb_cur and rgb_next pixel-by-pixel
//   2 = Slide-left:  new frame reveals from right, pushing old frame left
//   3 = Slide-right: new frame reveals from left, pushing old frame right
//   4 = Wipe:        old frame wipes away left-to-right revealing new
//
// Modes 2/3/4 are pure address remapping — no extra SDRAM bandwidth.
// Mode 1 (fade) requires the second frame reader to be active and blends
// rgb_cur/rgb_next with an alpha that increases linearly per frame.
// need_second is asserted when mode==1 and a transition is in progress.
//
// Domain: clk_pix
//============================================================================
`timescale 1ns / 1ps

module transition_engine (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,        // pulse to initiate a transition
    input  wire [3:0]  mode,         // 1=fade 2=slide-left 3=slide-right 4=wipe
    input  wire [7:0]  duration,    // transition duration in frames (1..255)
    input  wire        frame_start,  // one cycle before first active pixel
    input  wire [9:0]  x,           // current pixel column 0..639
    input  wire [9:0]  y,           // current pixel row    0..479
    input  wire        de,          // display enable
    input  wire [23:0] rgb_cur,    // current frame pixel
    input  wire [23:0] rgb_next,   // next frame pixel (fade mode only)
    output reg  [23:0] rgb_out,
    output reg          need_second, // high when second frame reader must be active
    output reg          busy,
    output reg          done         // one-cycle pulse when transition finishes
);

    //========================================================================
    // State machine
    //========================================================================
    localparam ST_IDLE     = 2'd0;
    localparam ST_ACTIVE   = 2'd1;
    localparam ST_COMPLETE = 2'd2;

    reg [1:0]  state;
    reg [7:0]  duration_r;
    reg [3:0]  mode_r;
    reg [15:0] frame_counter;   // frames elapsed: 0 at transition start

    // Edge detect frame_start
    reg fs_d1;
    wire fs_re = frame_start && !fs_d1;  // rising edge

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= ST_IDLE;
            duration_r    <= 8'd0;
            mode_r        <= 4'd0;
            frame_counter <= 16'd0;
            busy          <= 1'b0;
            done          <= 1'b0;
            fs_d1         <= 1'b0;
        end else begin
            fs_d1 <= frame_start;
            done  <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (start) begin
                        duration_r    <= duration;
                        mode_r        <= mode;
                        frame_counter <= 16'd0;
                        state         <= ST_ACTIVE;
                        busy          <= 1'b1;
                    end
                end

                ST_ACTIVE: begin
                    if (fs_re) begin
                        // frame_counter==0 during the first frame of transition
                        frame_counter <= frame_counter + 16'd1;
                        // Last frame is duration_r; transition completes after it
                        if (frame_counter >= {8'd0, duration_r} - 16'd1)
                            state <= ST_COMPLETE;
                    end
                end

                ST_COMPLETE: begin
                    // Hold last frame for exactly one full frame, then return to idle
                    if (fs_re) begin
                        state <= ST_IDLE;
                        busy  <= 1'b0;
                        done  <= 1'b1;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

    //========================================================================
    // Alpha (fade) and progress threshold (slide/wipe) — computed per-pixel
    // alpha_u8: 0 = 100% cur, 255 = 100% next
    // progress: pixel column at which next frame begins
    //========================================================================
    // When transitioning: alpha = (frame_counter + 1) / duration
    // When idle: alpha = 0
    // frame_counter goes 1..duration-1 during ST_ACTIVE
    // At frame_counter==1 (first transition frame): alpha = 2/duration → small
    // At frame_counter==duration-1 (last transition frame): alpha ≈ 1.0
    // Actually: alpha increases from small to 1.0 across the transition frames.

    // Q8.16 multiply for alpha: (frame_counter+1) / duration * 255
    // alpha_prod = (frame_counter+1) * 255; alpha_u8 = alpha_prod / duration
    wire [23:0] alpha_prod = ({16'd0, frame_counter + 16'd1} * 24'd255);
    wire [7:0]  alpha_u8  = (state == ST_ACTIVE && duration_r > 0)
                             ? alpha_prod[23:16]  // upper 8 bits of Q24.8 = result * 255
                             : 8'd0;

    // progress_px = (frame_counter+1) / duration * 640  (0..640)
    wire [23:0] prog_prod = ({16'd0, frame_counter + 16'd1} * 24'd640);
    wire [9:0]  progress  = (state == ST_ACTIVE && duration_r > 0)
                             ? prog_prod[23:14]   // upper 10 bits of Q24.8 >> 8 → 0..640
                             : 10'd0;

    //========================================================================
    // need_second: asserted only during fade transitions
    //========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) need_second <= 1'b0;
        else         need_second <= (mode_r == 4'd1) && (state != ST_IDLE);
    end

    //========================================================================
    // Pixel output
    //========================================================================
    // Fade: out = cur + (next - cur) * alpha / 255
    // Slide modes: select cur or next based on x vs progress threshold

    // Per-channel difference * alpha
    wire signed [16:0] diff_r = {1'b0, rgb_next[23:16]} - {1'b0, rgb_cur[23:16]};
    wire signed [16:0] diff_g = {1'b0, rgb_next[15:8]}  - {1'b0, rgb_cur[15:8]};
    wire signed [16:0] diff_b = {1'b0, rgb_next[7:0]}   - {1'b0, rgb_cur[7:0]};

    wire [15:0] blend_r = {8'd0, rgb_cur[23:16]} + (diff_r * {9'd0, alpha_u8} >> 8);
    wire [15:0] blend_g = {8'd0, rgb_cur[15:8]}  + (diff_g * {9'd0, alpha_u8} >> 8);
    wire [15:0] blend_b = {8'd0, rgb_cur[7:0]}   + (diff_b * {9'd0, alpha_u8} >> 8);

    wire [23:0] rgb_fade = {blend_r[7:0], blend_g[7:0], blend_b[7:0]};

    // For slide-left/wipe: x >= progress → show next (new frame comes from right)
    // For slide-right: x < (640 - progress) → show next
    wire [9:0] slide_thresh = progress;
    wire       show_next_slide = (mode_r == 4'd2 || mode_r == 4'd4)
                                 ? (x >= slide_thresh)   // left slide / wipe
                                 : (x < 10'd640 - slide_thresh);  // right slide

    wire [23:0] rgb_slide = show_next_slide ? rgb_next : rgb_cur;

    // Mode selection
    reg [23:0] rgb_mixed;
    always @* begin
        case (mode_r)
            4'd1: rgb_mixed = rgb_fade;  // fade
            4'd2: rgb_mixed = rgb_slide; // slide-left
            4'd3: rgb_mixed = rgb_slide; // slide-right
            4'd4: rgb_mixed = show_next_slide ? rgb_next : rgb_cur; // wipe
            default: rgb_mixed = rgb_cur; // no transition
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rgb_out <= 24'd0;
        end else begin
            rgb_out <= de ? rgb_mixed : rgb_cur;
        end
    end

endmodule

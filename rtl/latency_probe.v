// =============================================================================
// MedQ - latency_probe
// Differentiating Feature G1: End-to-end latency measurement
//
// Function:  Measure the wall-clock time from key_press (clk_sys) to the
//            first frame where the updated qstate appears on screen (clk_pix).
//            Output latency in microseconds and whole frames.
//
// Clocking:  Two independent clock domains driven by the top.
//              clk_sys : 50 MHz  — free-running counter
//              clk_pix : 25 MHz  — stop event and result output
//
// Protocol:  start_evt (clk_sys pulse)  -> arm the probe
//            stop_evt  (clk_pix pulse)  -> capture counter, compute result
//            lat_valid is a single-cycle pulse in clk_pix domain.
//
// Constraints (EG4S20BG256 / TD 6.2.1):
//   - No async set/reset; all registers use synchronous reset via rst_n.
//   - No initial statements for simulation-only defaults.
//   - All CDC is explicit (two flip-flop synchronisers, no gray-code).
// =============================================================================
`timescale 1ns / 1ps

module latency_probe (
    // ---- clk_sys side (start) ----
    input  wire        clk_sys,
    input  wire        rst_n_sys,
    input  wire        start_evt,   // single-cycle pulse in clk_sys domain

    // ---- clk_pix side (stop + output) ----
    input  wire        clk_pix,
    input  wire        rst_n_pix,
    input  wire        stop_evt,    // single-cycle pulse in clk_pix domain

    // ---- measurement results (clk_pix domain) ----
    output wire [15:0] lat_us,      // microseconds, 0..65535
    output wire [7:0]  lat_frames,  // whole frames,  0..255
    output wire        lat_valid    // single-cycle pulse: result is ready
);

    // =========================================================================
    // Parameters
    // =========================================================================
    // 1 tick @ 50 MHz = 20 ns = 0.02 us
    // To convert ticks to microseconds: divide by 50.
    localparam US_DIVISOR = 6'd50;

    // Frame period at 60 Hz: 1/60 s ≈ 16666.67 us.
    // We compute frames as integer division by 16667.
    localparam FRAME_US = 15'd16800;

    // Max counter value before it saturates (22 bits = 83.886 ms @ 50 MHz).
    // Saturation does not corrupt state; we just clamp the output.
    localparam COUNTER_W = 6'd22;
    localparam COUNTER_MAX = (1 << COUNTER_W) - 1;  // 22'h3FFFFF

    // =========================================================================
    // Stage 1 (clk_sys): Free-running counter + arm FSM
    //
    // States:
    //   IDLE   : waiting for start_evt.  counter = 0.
    //   RUN    : counting ticks since start.  stop_latched_sys gates overflow.
    //   DONE   : stop_latched_sys is high; counter holds final value.
    //            next start_evt resets to IDLE.
    // =========================================================================
    localparam [1:0] S_IDLE = 2'b00;
    localparam [1:0] S_RUN  = 2'b01;
    localparam [1:0] S_DONE = 2'b10;

    reg [1:0] state_sys;

    // CDC: stop_evt from clk_pix -> clk_sys (two FF synchroniser)
    reg stop_meta0_sys;
    reg stop_meta1_sys;
    always @(posedge clk_sys or negedge rst_n_sys) begin
        if (!rst_n_sys) begin
            stop_meta0_sys <= 1'b0;
            stop_meta1_sys <= 1'b0;
        end else begin
            stop_meta0_sys <= stop_evt;
            stop_meta1_sys <= stop_meta0_sys;
        end
    end

    // stop_latched: set on the clk_sys rising edge where stop_meta1_sys == 1,
    // and cleared when start_evt re-arms.
    reg stop_latched_sys;
    always @(posedge clk_sys or negedge rst_n_sys) begin
        if (!rst_n_sys) begin
            stop_latched_sys <= 1'b0;
        end else begin
            if (start_evt) begin
                stop_latched_sys <= 1'b0;   // re-arm
            end else if (stop_meta1_sys && (state_sys == S_RUN)) begin
                stop_latched_sys <= 1'b1;   // latch the stop
            end
        end
    end

    // Main counter
    reg [COUNTER_W-1:0] counter_sys;
    always @(posedge clk_sys or negedge rst_n_sys) begin
        if (!rst_n_sys) begin
            state_sys   <= S_IDLE;
            counter_sys <= {COUNTER_W{1'b0}};
        end else begin
            case (state_sys)
                S_IDLE: begin
                    counter_sys <= {COUNTER_W{1'b0}};
                    if (start_evt) begin
                        state_sys <= S_RUN;
                    end
                end

                S_RUN: begin
                    if (stop_latched_sys) begin
                        state_sys <= S_DONE;
                        // counter_sys already holds the final tick count
                    end else begin
                        if (counter_sys != COUNTER_MAX[COUNTER_W-1:0]) begin
                            counter_sys <= counter_sys + 1'b1;
                        end
                    end
                end

                S_DONE: begin
                    // Wait for next start_evt to restart.
                    if (start_evt) begin
                        state_sys   <= S_RUN;
                        counter_sys <= {COUNTER_W{1'b0}};
                    end
                end

                default: begin
                    state_sys   <= S_IDLE;
                    counter_sys <= {COUNTER_W{1'b0}};
                end
            endcase
        end
    end

    // =========================================================================
    // Stage 2 (clk_sys): Capture counter value when stop_latched_sys rises.
    // This register holds the final tick count for the current measurement.
    // =========================================================================
    reg [COUNTER_W-1:0] captured_ticks_sys;
    reg captured_valid_sys;

    reg stop_latched_prev;
    always @(posedge clk_sys or negedge rst_n_sys) begin
        if (!rst_n_sys) begin
            stop_latched_prev    <= 1'b0;
            captured_ticks_sys  <= {COUNTER_W{1'b0}};
            captured_valid_sys   <= 1'b0;
        end else begin
            stop_latched_prev    <= stop_latched_sys;
            captured_valid_sys   <= 1'b0;

            // Capture on the rising edge of stop_latched_sys
            if (stop_latched_sys && !stop_latched_prev) begin
                captured_ticks_sys  <= counter_sys;
                captured_valid_sys <= 1'b1;
            end

            // Clear after capture; the DONE state already guards re-arm
            if (start_evt) begin
                captured_valid_sys <= 1'b0;
            end
        end
    end

    // =========================================================================
    // Stage 3 (clk_pix): CDC the captured result + valid flag
    // Two independent synchronisers for the data value and the strobe.
    // =========================================================================
    // CDC for valid strobe
    reg valid_meta0_pix;
    reg valid_meta1_pix;
    reg result_ready_pix;

    always @(posedge clk_pix or negedge rst_n_pix) begin
        if (!rst_n_pix) begin
            valid_meta0_pix <= 1'b0;
            valid_meta1_pix <= 1'b0;
            result_ready_pix <= 1'b0;
        end else begin
            valid_meta0_pix <= captured_valid_sys;
            valid_meta1_pix <= valid_meta0_pix;
            // Pulse: result_ready_pix is set when valid_meta1_pix goes high,
            // and cleared when the consumer reads it (or next cycle).
            if (valid_meta1_pix && !result_ready_pix) begin
                result_ready_pix <= 1'b1;
            end else begin
                result_ready_pix <= 1'b0;  // consume immediately
            end
        end
    end

    // CDC for the counter value (22 bits) — two-stage synchroniser.
    // Even if the value changes during crossing, the worst case is off by ±1
    // tick (20 ns), which is well within spec.
    reg [COUNTER_W-1:0] ticks_meta0;
    reg [COUNTER_W-1:0] ticks_meta1;
    reg [COUNTER_W-1:0] ticks_pix;

    always @(posedge clk_pix or negedge rst_n_pix) begin
        if (!rst_n_pix) begin
            ticks_meta0 <= {COUNTER_W{1'b0}};
            ticks_meta1 <= {COUNTER_W{1'b0}};
            ticks_pix   <= {COUNTER_W{1'b0}};
        end else begin
            ticks_meta0 <= captured_ticks_sys;
            ticks_meta1 <= ticks_meta0;
            ticks_pix   <= ticks_meta1;
        end
    end

    // =========================================================================
    // Stage 4 (clk_pix): Compute results
    //
    // Conversion:
    //   us  = ticks / 50        (22 bits in, 16 bits out, shift-subtract div)
    //   frames = us / 16667    (16 bits in,  8 bits out)
    //
    // Both conversions are pure combinational (functions) fed by a register,
    // keeping the output pipelined and avoiding multi-cycle timing paths.
    // =========================================================================
    wire [15:0] lat_us_next;
    wire [7:0]  lat_frames_next;

    assign lat_us_next     = div_u22_u16(ticks_pix);
    assign lat_frames_next = div_u16_u8 ({16'h0, lat_us_next});

    // lat_valid: single-cycle pulse when result is freshly computed.
    reg lat_valid_pix;
    always @(posedge clk_pix or negedge rst_n_pix) begin
        if (!rst_n_pix) begin
            lat_valid_pix <= 1'b0;
        end else begin
            lat_valid_pix <= result_ready_pix;
        end
    end

    // Output registers (registered at the end of the pipeline stage)
    reg [15:0] lat_us_reg;
    reg [7:0]  lat_frames_reg;

    always @(posedge clk_pix or negedge rst_n_pix) begin
        if (!rst_n_pix) begin
            lat_us_reg     <= 16'h0;
            lat_frames_reg <= 8'h0;
        end else begin
            if (result_ready_pix) begin
                lat_us_reg     <= lat_us_next;
                lat_frames_reg <= lat_frames_next;
            end
        end
    end

    assign lat_us     = lat_us_reg;
    assign lat_frames = lat_frames_reg;
    assign lat_valid  = lat_valid_pix;

    // =========================================================================
    // Helper functions (Verilog-2001, not automatic)
    // Shift-subtract division: works in 1 combinational pass, no loops needed.
    // =========================================================================

    // Divide unsigned 22-bit dividend by 50 -> 16-bit quotient
    function [15:0] div_u22_u16;
        input [21:0] dividend;
        reg   [37:0] remainder;
        reg   [15:0] quotient;
        integer bit_idx;
        begin
            remainder = {16'h0, dividend};  // 38-bit working value
            quotient  = 16'h0;
            // 22 iterations (one per output bit)
            for (bit_idx = 0; bit_idx < 22; bit_idx = bit_idx + 1) begin
                remainder = remainder << 1;
                quotient  = quotient  << 1;
                if (remainder >= 38'd50) begin
                    remainder[0] = 1'b0;  // subtract 50 from lower bits
                    remainder = remainder - 38'd50;
                    quotient[0] = 1'b1;
                end
            end
            div_u22_u16 = quotient;
        end
    endfunction

    // Divide unsigned 32-bit dividend by 16667 -> 8-bit quotient
    function [7:0] div_u16_u8;
        input [31:0] dividend;
        reg   [47:0] remainder;
        reg   [7:0]  quotient;
        integer bit_idx;
        begin
            remainder = {16'h0, dividend};  // 48-bit working value
            quotient  = 8'h0;
            // 8 iterations (one per output bit)
            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                remainder = remainder << 1;
                quotient  = quotient  << 1;
                if (remainder >= 48'd16667) begin
                    remainder = remainder - 48'd16667;
                    quotient[0] = 1'b1;
                end
            end
            div_u16_u8 = quotient;
        end
    endfunction

endmodule

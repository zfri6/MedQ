// =============================================================================
// MedQ - av_sync_monitor
// Differentiating Feature G2: Audio-video sync evidence
//
// Function:  Count audio samples per video frame, accumulate over a measurement
//            window, compute the measured sample rate and frequency drift in ppm.
//            This turns "audio-video sync" from a checkbox into a number.
//
// Clocking:  clk_pix domain (25 MHz).  All state is local to this domain.
//
// Measurement window: 256 frames (~4.27 s at 60 Hz).
//   samples_per_256frames = samples_frame0 + samples_frame1 + ... + samples_frame255
//   avg_samples_per_frame = samples_per_256frames / 256
//   fs_measured_hz        = avg_samples_per_frame * 60
//   drift_ppm             = (avg_samples_per_frame - 800) * 1250
//                          = (samples_per_256frames - 204800) * 1250 / 256
//   The ×1250 conversion is exact:
//     1 extra sample/frame = +1250 ppm (1.25 ppm per sample).
//
// Constraints (EG4S20BG256 / TD 6.2.1):
//   - Verilog-2001 only (no logic/always_ff/interface/enum/typedef).
//   - All registers use synchronous reset.
//   - No initial statements for simulation-only defaults.
// =============================================================================
`timescale 1ns / 1ps

module av_sync_monitor (
    input  wire        clk,
    input  wire        rst_n,

    // ---- Video timing (drives measurement window) ----
    input  wire        frame_start,  // one-cycle pulse at start of each frame

    // ---- Audio clock (48 kHz strobe) ----
    input  wire        aud_stb,      // one-cycle pulse at each audio sample

    // ---- Outputs (updated once per 256-frame window) ----
    output wire [11:0] samples_per_frame, // avg samples per frame this window
    output wire [19:0] fs_measured_hz,    // measured sample rate in Hz
    output wire [15:0] drift_ppm           // signed: + = audio faster than expected
);

    // =========================================================================
    // Parameters
    // =========================================================================
    // Theoretical values at exact 60 Hz / 48 kHz:
    localparam THZ = 20'd48000;          // theoretical sample rate (Hz)
    localparam FRAMES_PER_WINDOW = 9'd256; // measurement window (power of 2)

    // Expected samples per 256-frame window at perfect sync:
    localparam EXPECTED_256 = 18'd204800; // 800 × 256
    // ppm conversion: drift_ppm = (avg - 800) * 1250
    // where avg = samples_per_256frames / 256
    // => drift_ppm = (samples_per_256frames - 204800) * 1250 / 256
    // Use >> 8 to divide by 256 (power of 2).
    // Intermediate: (samples_per_256frames - 204800) fits in 19 bits (max 262143).
    // × 1250 fits in 32 bits (max ~328M).

    // =========================================================================
    // State machine
    // =========================================================================
    localparam [1:0] S_INIT = 2'b00;  // wait for first frame_start to sync
    localparam [1:0] S_MEAS = 2'b01;  // accumulating samples over 256 frames
    localparam [1:0] S_DONE = 2'b10;  // results computed, output for 1 frame

    reg [1:0] state;

    // -------------------------------------------------------------------------
    // Counters
    // -------------------------------------------------------------------------
    // Samples accumulated in current frame
    reg [11:0] count_frame;
    // Total samples accumulated over the full 256-frame window
    reg [17:0] count_total;
    // Frame counter within the measurement window (0..255)
    reg [7:0]  frame_idx;

    // -------------------------------------------------------------------------
    // Measurement result registers (updated at the end of each window)
    // -------------------------------------------------------------------------
    reg [11:0] samples_per_frame_reg;
    reg [19:0] fs_measured_hz_reg;
    reg [15:0] drift_ppm_reg;

    // Temporary computation registers (combinational, inferred from registers)
    reg [17:0] avg_raw;        // count_total >> 8
    reg [19:0] fs_computed;    // avg_raw * 60
    reg signed [15:0] ppm_computed; // signed drift ppm, clamped to 16-bit

    // =========================================================================
    // Main state machine
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= S_INIT;
            count_frame      <= 12'h0;
            count_total      <= 18'h0;
            frame_idx        <= 8'h0;
            samples_per_frame_reg <= 12'd800;
            fs_measured_hz_reg    <= THZ;
            drift_ppm_reg         <= 16'h0;
        end else begin
            case (state)
                // -----------------------------------------------------------------
                S_INIT: begin
                    // Wait for first frame_start to align to the video boundary.
                    // Reset counters; don't accumulate any samples until MEAS starts.
                    count_frame <= 12'h0;
                    count_total <= 18'h0;
                    frame_idx   <= 8'h0;
                    if (frame_start) begin
                        state <= S_MEAS;
                    end
                end

                // -----------------------------------------------------------------
                S_MEAS: begin
                    // Accumulate aud_stb pulses into the frame counter.
                    if (aud_stb) begin
                        count_frame <= count_frame + 12'h1;
                    end

                    // At frame boundary: commit the frame count and advance.
                    if (frame_start) begin
                        count_total <= count_total + {6'h0, count_frame};
                        count_frame <= 12'h0;
                        frame_idx   <= frame_idx + 8'h1;

                        // When we have completed 256 frames:
                        if (frame_idx == 8'd255) begin
                            state <= S_DONE;
                        end
                    end
                end

                // -----------------------------------------------------------------
                S_DONE: begin
                    // Compute results from the 256-frame accumulation.
                    // avg = count_total / 256 (>>8)
                    avg_raw = count_total >> 8;
                    if (avg_raw > 18'd4095)
                        avg_raw = 18'd4095;  // clamp to 12-bit
                    samples_per_frame_reg <= avg_raw[11:0];

                    // fs_measured = avg * 60
                    fs_computed   = avg_raw * 20'd60;
                    fs_measured_hz_reg <= fs_computed;

                    // ppm = (avg - 800) * 1250, signed, clamped to 16-bit
                    // avg_raw is unsigned 18-bit; do subtraction in signed space.
                    if (avg_raw >= 18'd800) begin
                        ppm_computed = $signed({1'b0, avg_raw[14:0]}) - 15'sd800;
                        ppm_computed = ppm_computed * 16'sd1250;
                    end else begin
                        ppm_computed = - (15'sd800 - $signed({1'b0, avg_raw[14:0]}));
                        ppm_computed = ppm_computed * 16'sd1250;
                    end
                    // Clamp to signed 16-bit range
                    if (ppm_computed > 16'sd32767)
                        ppm_computed = 16'sd32767;
                    if (ppm_computed < -16'sd32768)
                        ppm_computed = -16'sd32768;
                    drift_ppm_reg <= ppm_computed;

                    // Reset for next measurement window.
                    count_total <= 18'h0;
                    count_frame <= 12'h0;
                    frame_idx   <= 8'h0;

                    // Immediately transition back to MEAS for next window.
                    state <= S_MEAS;
                end

                // -----------------------------------------------------------------
                default: begin
                    state            <= S_INIT;
                    count_frame      <= 12'h0;
                    count_total      <= 18'h0;
                    frame_idx        <= 8'h0;
                end
            endcase
        end
    end

    // =========================================================================
    // Outputs
    // =========================================================================
    // All outputs are registered (updated at the end of each 256-frame window).
    // During the INIT and MEAS states they hold the value from the previous window.
    assign samples_per_frame = samples_per_frame_reg;
    assign fs_measured_hz    = fs_measured_hz_reg;
    assign drift_ppm        = drift_ppm_reg;

endmodule

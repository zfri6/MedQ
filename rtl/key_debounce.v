//============================================================================
// key_debounce.v - N-key debouncer with level, press, release, and hold output
// Domain: clk_sys (50 MHz)
//
// Debounce time: 10 ms @ 50 MHz  (CNT_MAX = 500000)
// Press:   rising-edge single-cycle pulse on key_level 0->1
// Release: falling-edge single-cycle pulse on key_level 1->0
// Hold:    high continuously while key is pressed >= 1 second
//
// Strategy: per-key two-phase stable counter. When raw != debounced,
// counter increments. When counter reaches threshold, raw wins and
// counter resets. Hold counter starts when debounced=pressed and runs
// until debounced=released.
//============================================================================
`timescale 1ns / 1ps

module key_debounce #(
    parameter integer N        = 4,
    parameter integer CNT_MAX  = 500000,   // 10 ms @ 50 MHz
    parameter integer HOLD_CNT_MAX = 50000000
) (
    input  wire clk,
    input  wire rst_n,
    input  wire [N-1:0] key_in_n,  // board keys, active low (pressed=0)

    output wire [N-1:0] key_level,
    output wire [N-1:0] key_press,
    output wire [N-1:0] key_release,
    output wire [N-1:0] key_hold
);

    localparam STABLE_W = 19;  // 2^19 = 524288 > CNT_MAX=500000
    localparam HOLD_W   = 26;  // 2^26 = 67M > HOLD_CNT_MAX=50M

    // Per-key state arrays
    reg [N-1:0] debounced;    // current debounced level (1=pressed)
    reg [N-1:0] prev_deb;     // previous debounced for edge detection
    reg [N-1:0] hold_r;       // hold output (1=held >= 1 s)

    // Counters — inferred as distributed RAM / registers
    reg [STABLE_W-1:0] stable_cnt [0:N-1];
    reg [HOLD_W-1:0]   hold_cnt   [0:N-1];

    integer i;

    // ---- Main debounce FSM (one per key, rolled) ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < N; i = i + 1) begin
                debounced[i]   <= 1'b0;
                prev_deb[i]    <= 1'b0;
                hold_r[i]      <= 1'b0;
                stable_cnt[i]  <= {STABLE_W{1'b0}};
                hold_cnt[i]    <= {HOLD_W{1'b0}};
            end
        end else begin
            // Capture previous debounced for edge detection
            prev_deb <= debounced;

            for (i = 0; i < N; i = i + 1) begin
                // Raw input: key_in_n[i]==0 -> pressed
                // new_sample: raw disagrees with debounced
                if ((~key_in_n[i]) != debounced[i]) begin
                    // Raw disagrees with debounced: count
                    if (stable_cnt[i] != CNT_MAX - 1) begin
                        stable_cnt[i] <= stable_cnt[i] + 1'b1;
                    end else begin
                        // Threshold reached: adopt raw value
                        debounced[i]   <= ~key_in_n[i];
                        stable_cnt[i]   <= {STABLE_W{1'b0}};
                        // Reset hold when state changes
                        hold_r[i]      <= 1'b0;
                        hold_cnt[i]     <= {HOLD_W{1'b0}};
                    end
                end else begin
                    // Stable: reset counter
                    stable_cnt[i] <= {STABLE_W{1'b0}};
                end

                // ---- Hold counter: runs while continuously pressed ----
                if (debounced[i]) begin
                    if (!hold_r[i]) begin
                        // Not yet in hold: count up
                        if (hold_cnt[i] < HOLD_CNT_MAX - 1) begin
                            hold_cnt[i] <= hold_cnt[i] + 1'b1;
                        end else begin
                            // Threshold reached: enter hold state
                            hold_r[i]   <= 1'b1;
                        end
                    end
                    // else: already held, do nothing (stay high)
                end else begin
                    // Released: reset hold
                    hold_r[i]   <= 1'b0;
                    hold_cnt[i] <= {HOLD_W{1'b0}};
                end
            end
        end
    end

    // ---- Edge generation (single-cycle pulses) ----
    // 0->1 transition = press; 1->0 = release
    assign key_level   = debounced;
    assign key_press   = debounced & ~prev_deb;  // rising edge
    assign key_release = ~debounced & prev_deb;   // falling edge
    assign key_hold    = hold_r;

endmodule

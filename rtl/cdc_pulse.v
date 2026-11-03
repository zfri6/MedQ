//============================================================================
// cdc_pulse.v - Pulse CDC via two-FF handshake
// Domain: src_clk / dst_clk (two independent clock domains)
//
// Pulse crossing with busy/flow-control on the source side.
// - src_pulse: single-cycle pulse on src_clk domain
// - dst_pulse: single-cycle pulse on dst_clk domain (approx 1-2 cycles later)
// - src_busy:  asserted while a transaction is in-flight; prevents new pulse
//              from src from being forwarded until dst has acknowledged.
//
// Handshake protocol (four-phase, but simplified for single-bit pulse):
//   src: pulse -> set src_busy, send req toggle
//   dst: detect req, generate dst_pulse, send ack toggle
//   src: detect ack, clear src_busy
//============================================================================
`timescale 1ns / 1ps

module cdc_pulse (
    input  wire src_clk,
    input  wire src_rst_n,
    input  wire src_pulse,   // single-cycle pulse on src_clk
    output wire src_busy,     // 1=transaction in-flight; pulse ignored while high

    input  wire dst_clk,
    input  wire dst_rst_n,
    output wire dst_pulse    // single-cycle pulse on dst_clk
);

    // --- Cross-domain signals ---
    // Source -> Destination: request toggle (level signal)
    reg src_req_reg;
    wire dst_ack_sync;   // ack from dst, synchronized to src_clk

    // Destination -> Source: acknowledgment toggle (level signal)
    reg dst_ack_reg;
    wire src_req_sync;   // req from src, synchronized to dst_clk

    // --- Source-side logic ---
    wire src_req_change;  // rising edge of src_req_reg
    wire src_ack_seen;    // ack toggled back

    // src_req_reg toggles on each incoming pulse (if not busy)
    always @(posedge src_clk or negedge src_rst_n) begin
        if (!src_rst_n) begin
            src_req_reg <= 1'b0;
        end else begin
            // On a pulse while not busy, raise request
            if (src_pulse && !src_busy) begin
                src_req_reg <= ~src_req_reg;
            end
        end
    end

    // src_busy: high while waiting for ack to return
    // Detect rising edge of dst_ack_sync (ack arrived)
    reg dst_ack_meta;
    always @(posedge src_clk or negedge src_rst_n) begin
        if (!src_rst_n) begin
            dst_ack_meta <= 1'b0;
        end
    end

    // dst_ack_sync is the synchronized dst_ack_reg to src_clk
    cdc_sync_bit #(.STAGES(2), .INIT(0)) u_sync_ack (
        .clk   (src_clk),
        .rst_n (src_rst_n),
        .d_in  (dst_ack_reg),
        .d_out (dst_ack_sync)
    );

    // src_busy: asserted when req has been sent but ack not yet received
    // req and ack are toggles; busy when they differ
    assign src_busy = (src_req_reg != dst_ack_sync);

    // --- Destination-side logic ---
    // dst_req_sync is the synchronized src_req_reg to dst_clk
    cdc_sync_bit #(.STAGES(2), .INIT(0)) u_sync_req (
        .clk   (dst_clk),
        .rst_n (dst_rst_n),
        .d_in  (src_req_reg),
        .d_out (src_req_sync)
    );

    // dst_ack_reg toggles on each new req arrival (rising edge of src_req_sync)
    reg dst_req_prev;
    always @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) begin
            dst_req_prev <= 1'b0;
            dst_ack_reg  <= 1'b0;
        end else begin
            dst_req_prev <= src_req_sync;
            // Toggle ack on rising edge of req
            if (src_req_sync != dst_req_prev) begin
                dst_ack_reg <= src_req_sync;
            end
        end
    end

    // dst_pulse: one-cycle pulse on each rising edge of synchronized req
    reg dst_req_meta;
    always @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) begin
            dst_req_meta <= 1'b0;
        end else begin
            dst_req_meta <= src_req_sync;
        end
    end

    assign dst_pulse = src_req_sync != dst_req_meta;

endmodule

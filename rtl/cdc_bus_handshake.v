//============================================================================
// cdc_bus_handshake.v - Wide bus CDC via four-phase handshake
// Domain: src_clk / dst_clk (two independent clock domains)
//
// Four-phase (request-acknowledge) handshake for a wide data bus.
// Guarantees that the destination side sees all W bits from the same
// source clock cycle as an atomic snapshot.
//
// Protocol:
//   src: src_data stable -> src_req=1
//   dst: see src_req=1, capture src_data_sync, src_ack=1
//   src: see src_ack=1, src_req=0, src_data may change
//   dst: see src_req=0, src_ack=0  (return to idle)
//
// Default W=128 (for qstate_bus).  Parameterized for other widths (64 for
// param_bus, etc.).
//============================================================================
`timescale 1ns / 1ps

module cdc_bus_handshake #(
    parameter W = 128  // bus width in bits
) (
    input  wire src_clk,
    input  wire src_rst_n,
    input  wire [W-1:0] src_data,

    input  wire dst_clk,
    input  wire dst_rst_n,
    output wire [W-1:0] dst_data
);

    // --- Cross-domain signals ---
    // Request: src->dst level signal
    reg src_req;
    wire dst_ack_sync;

    // Acknowledge: dst->src level signal
    reg dst_ack;
    wire src_req_sync;

    reg [W-1:0] src_last_data;

    // Source-side automatic request generation.  The frozen public interface
    // exposes a level bus only, so a changed level is the send event.
    always @(posedge src_clk or negedge src_rst_n) begin
        if (!src_rst_n) begin
            src_req       <= 1'b0;
            src_last_data <= {W{1'b0}};
        end else begin
            if (src_req && dst_ack_sync) begin
                src_req <= 1'b0;
            end else if (!src_req && !dst_ack_sync && (src_data != src_last_data)) begin
                src_last_data <= src_data;
                src_req <= 1'b1;
            end
        end
    end

    // src_req_auto: raises src_req when upstream puts new data on src_data.
    // Detects rising edge of "upstream wants to send": src_data changes while src_req==0.
    // We use a simple level detect: src_req stays 0 until ack; upstream must
    // hold src_data stable for the entire req phase.  The upstream module
    // (queue_fsm) changes src_data only when src_req==0 (or after the handshake).
    //
    // This module raises src_req when src_data is first presented while src_req==0.
    // We detect this via a "data valid" flag from source side.
    // Implementation: src_req stays high until ack arrives.  Caller ensures
    // src_data is stable during src_req==1.  This module just does the CDC.
    //
    // Actually, we need a way to detect "new data arrived on src_data".
    // Simplest: caller sets a "send" strobe (one cycle).  We capture it.
    // But the interface contract says src_data is a Maded-level signal.
    // We implement the standard 4-phase: src_req is raised by caller, held until ack.
    // This module handles the CDC of src_req and src_data, and the CDC of dst_ack.
    //
    // Wait - re-reading the spec: "src_data  dir: in  width: W" (level signal).
    // The caller is expected to hold src_data stable while src_req is high.
    // This module just CDC-s the bundle.

    // --- Request CDC: src_req -> dst_req_sync ---
    cdc_sync_bit #(.STAGES(2), .INIT(0)) u_sync_req (
        .clk   (dst_clk),
        .rst_n (dst_rst_n),
        .d_in  (src_req),
        .d_out (src_req_sync)
    );

    // --- Data CDC: src_data -> dst_data (multi-bit, level crossing) ---
    // All W bits are captured simultaneously by dst_data register,
    // which updates only when dst has accepted the current word.
    reg [W-1:0] dst_data_raw;

    // --- Acknowledge CDC: dst_ack -> src_ack_sync ---
    cdc_sync_bit #(.STAGES(2), .INIT(0)) u_sync_ack (
        .clk   (src_clk),
        .rst_n (src_rst_n),
        .d_in  (dst_ack),
        .d_out (dst_ack_sync)
    );

    // --- Destination-side state machine ---
    // States: IDLE=0, SAMPLE=1
    localparam S_IDLE   = 1'b0;
    localparam S_SAMPLE = 1'b1;

    reg state;

    always @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) begin
            state         <= S_IDLE;
            dst_ack       <= 1'b0;
            dst_data_raw  <= {W{1'b0}};
        end else begin
            case (state)
                S_IDLE: begin
                    if (src_req_sync) begin
                        // New request detected: capture data and ack
                        dst_data_raw <= src_last_data;
                        dst_ack      <= 1'b1;
                        state        <= S_SAMPLE;
                    end else begin
                        dst_ack <= 1'b0;
                    end
                end

                S_SAMPLE: begin
                    // Waiting for request to go low (source consumed the ack)
                    if (!src_req_sync) begin
                        dst_ack <= 1'b0;
                        state   <= S_IDLE;
                    end
                end

                default: begin
                    state   <= S_IDLE;
                    dst_ack <= 1'b0;
                end
            endcase
        end
    end

    // dst_data is the captured value, held stable
    assign dst_data = dst_data_raw;

endmodule

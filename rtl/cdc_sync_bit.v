//============================================================================
// cdc_sync_bit.v - Single-bit CDC synchronizer (two-FF / multi-FF)
// Domain: any (src and dst clocks are separate)
//
// STAGES: number of flip-flop stages in the synchronizer chain (default 2)
// INIT  : initial value on rst_n release (default 0)
//
// Classic two-FF synchronizer eliminates metastability on single-bit
// crossing from one clock domain to another.  STAGES=2 INIT=0 is the
// standard recommended by most guidelines; more stages can be used for
// very fast source clocks.
//============================================================================
`timescale 1ns / 1ps

module cdc_sync_bit #(
    parameter STAGES = 2,
    parameter INIT   = 0
) (
    input  wire clk,
    input  wire rst_n,
    input  wire d_in,
    output wire d_out
);

    // Sync chain: STAGES flip-flops in series on dst clock domain.
    // The first flop captures the possibly metastable input; subsequent
    // flops resolve before d_out is used.
    reg [STAGES-1:0] sync_chain;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_chain <= {STAGES{INIT}};
        end else begin
            sync_chain <= {sync_chain[STAGES-2:0], d_in};
        end
    end

    // Output is the last stage of the sync chain
    assign d_out = sync_chain[STAGES-1];

endmodule

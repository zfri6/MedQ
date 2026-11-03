//============================================================================
// rst_sync.v - Async assert, sync release reset synchronizer
// Domain: any
//
// POR_CYCLES: number of clk cycles to count when pll_locked is 0
//             default 50000 @50MHz = 1 ms
//
// Strategy:
//   - ext_rst_n or !pll_locked immediately forces rst_n_out=0 (async assert)
//   - on release (ext_rst_n=1 and pll_locked=1), two flip-flops on clk domain
//     guarantee sync release and eliminate metastability
//   - if pll_locked is permanently 0 (no PLL), POR counter holds reset until
//     POR_CYCLES expire, then auto-releases
//============================================================================
`timescale 1ns / 1ps

module rst_sync #(
    parameter integer POR_CYCLES = 50000
) (
    input  wire clk,
    input  wire ext_rst_n,   // external async reset, active low
    input  wire pll_locked,   // PLL lock indicator, active high; tie to 1 if absent
    output wire rst_n_out      // domain reset, active low
);

    // Two-FF sync chain for reset release
    reg rst_meta1;
    reg rst_meta2;

    // POR counter: counts when pll_locked==0, clears when locked
    reg [15:0] por_cnt;  // 16-bit, covers 65535; POR_CYCLES default=50000 fits

    wire por_done;
    wire por_rst_n;   // 1=POR has expired (no PLL, must release)

    // POR expiry: done when counter reaches POR_CYCLES-1
    assign por_done  = (por_cnt >= (POR_CYCLES[15:0] - 1'b1));
    assign por_rst_n = por_done;

    // POR counter
    always @(posedge clk or negedge ext_rst_n) begin
        if (!ext_rst_n) begin
            por_cnt <= 16'h0;
        end else begin
            // Count when PLL is not locked (or pll_locked tied low)
            if (!pll_locked) begin
                if (!por_done)
                    por_cnt <= por_cnt + 1'b1;
                // else hold
            end else begin
                // PLL locked: reset POR so next unlock re-counts
                por_cnt <= 16'h0;
            end
        end
    end

    // Release condition: PLL locked OR POR expired (no PLL case)
    wire release_req;  // 1 = may release
    assign release_req = ext_rst_n && (pll_locked | por_rst_n);

    // Two-FF sync chain
    always @(posedge clk or negedge release_req) begin
        if (!release_req) begin
            // Async assert: as soon as release is invalid, reset
            rst_meta1 <= 1'b0;
            rst_meta2 <= 1'b0;
        end else begin
            // Sync release: two FF on target clock domain
            rst_meta1 <= 1'b1;
            rst_meta2 <= rst_meta1;
        end
    end

    assign rst_n_out = rst_meta2;

endmodule

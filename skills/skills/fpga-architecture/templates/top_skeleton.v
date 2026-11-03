// rtl/top_skeleton.v -- architecture-stage skeleton for HX4S20 / EG4S20BG256
// Verilog-2001 only. No business logic. Fill instances from
// doc/arch/interface_contract.yaml and doc/arch/connection_matrix.md.
// Board pin names come from doc/hw/extracted_facts.json when present.

module top (
    input  wire        CLOCK,
    input  wire        rst_n,
    output wire [3:0]  LED
);

    wire clk;
    wire rst_n_sync;
    wire pll_lock;

    // generate with TD IP Generator -> rtl/al_ip/pll_sys.v
    // pll_sys u_pll (
    //     .refclk   (CLOCK),
    //     .reset    (~rst_n),
    //     .extlock  (pll_lock),
    //     .clk0_out (clk)
    // );
    assign clk      = CLOCK;
    assign pll_lock = 1'b1;

    // reset_sync u_rst (
    //     .clk   (clk),
    //     .rst_n (rst_n & pll_lock),
    //     .out_n (rst_n_sync)
    // );
    assign rst_n_sync = rst_n & pll_lock;

    // <core_module> u_core (
    //     .clk   (clk),
    //     .rst_n (rst_n_sync),
    //     .LED   (LED)
    // );
    assign LED = 4'b0000;

endmodule

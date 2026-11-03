`timescale 1ns / 1ps
// HDMI BCH Figure 5-5, zero seed, data bits in transmission (LSB-first) order.
module hdmi_bch_ecc(input wire clk,rst_n,clear,shift_en,bit_in,output wire [7:0] ecc_out);
    reg [7:0] ecc;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) ecc<=0;
        else if (clear) ecc<=0;
        else if (shift_en) ecc<=(ecc>>1)^((ecc[0]^bit_in) ? 8'h83 : 8'd0);
    end
    assign ecc_out=ecc;
endmodule

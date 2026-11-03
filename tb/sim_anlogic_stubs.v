`timescale 1ns / 1ps
// Behavioral 50 MHz reference clock IP. No device timing/jitter claims.
module clk_wize(input wire refclk,reset,output reg clk0_out,clk1_out);
    initial begin clk0_out=0; clk1_out=0; end
    always #4 clk0_out=reset ? 0 : ~clk0_out;
    always #20 clk1_out=reset ? 0 : ~clk1_out;
endmodule
module pll_mem(input wire refclk,reset,output reg extlock,output reg clk0_out,output reg clk1_out);
    integer lock_count;
    initial begin extlock=0; clk0_out=0; clk1_out=0; lock_count=0; end
    always #10 clk0_out=reset ? 0 : ~clk0_out;
    initial begin #8;forever #10 clk1_out=reset ? 0 : ~clk1_out;end
    always @(posedge refclk) begin
        if(reset) begin lock_count<=0; extlock<=0; end
        else if(lock_count<16) lock_count<=lock_count+1;
        else extlock<=1;
    end
endmodule

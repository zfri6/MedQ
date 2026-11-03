`timescale 1ns / 1ps
// Exact rational 48 kHz strobe at 25 MHz; 520/521-cycle intervals.
module audio_sample_clk #(
    parameter integer ACC_W=24, ACC_INC=32212,
    parameter integer CLK_HZ=25000000, SAMPLE_HZ=48000
)(input wire clk,rst_n,output reg stb);
    reg [31:0] acc;
    wire [32:0] sum={1'b0,acc}+SAMPLE_HZ;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin acc<=0; stb<=0; end
        else begin
            stb<=sum>=CLK_HZ;
            acc<=sum>=CLK_HZ ? sum-CLK_HZ : sum;
        end
    end
endmodule

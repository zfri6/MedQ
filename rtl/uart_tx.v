`timescale 1ns / 1ps
// 8N1 valid/ready transmitter; ready means byte accepted at this edge.
module uart_tx #(
    parameter integer CLK_HZ = 50000000,  // 50 MHz
    parameter integer BAUD  = 115200
) (
    input  wire clk,
    input  wire rst_n,

    input  wire       in_valid,
    output wire       in_ready,
    input  wire [7:0] in_data,

    output reg         txd
);


    localparam PERIOD=CLK_HZ/BAUD;
    reg busy;
    reg [31:0] timer;
    reg [3:0] bit_index;
    reg [9:0] frame;
    assign in_ready=!busy;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin busy<=0;timer<=0;bit_index<=0;frame<=10'h3ff;txd<=1;end
        else if(!busy)begin
            txd<=1;
            if(in_valid)begin
                frame<={1'b1,in_data,1'b0};txd<=0;busy<=1;timer<=PERIOD-1;bit_index<=0;
            end
        end else if(timer!=0)timer<=timer-1'b1;
        else if(bit_index==9)begin busy<=0;txd<=1;end
        else begin bit_index<=bit_index+1'b1;txd<=frame[bit_index+1'b1];timer<=PERIOD-1;end
    end
endmodule

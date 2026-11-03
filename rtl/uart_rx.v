`timescale 1ns / 1ps
// 8N1 center sampling, false-start rejection, one-cycle byte/error indication.
module uart_rx #(
    parameter integer CLK_HZ = 50000000,  // 50 MHz
    parameter integer BAUD  = 115200
) (
    input  wire clk,
    input  wire rst_n,
    input  wire rxd,

    output reg         out_valid,
    output reg  [7:0] out_data,
    output reg         frame_err
);


    localparam PERIOD=CLK_HZ/BAUD;
    localparam IDLE=0,START=1,DATA=2,STOP=3;
    reg [1:0] state;
    reg [31:0] timer;
    reg [2:0] bit_index;
    reg [7:0] shift;
    reg sync1,sync2;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE;timer<=0;bit_index<=0;shift<=0;sync1<=1;sync2<=1;
            out_valid<=0;out_data<=0;frame_err<=0;
        end else begin
            sync1<=rxd;sync2<=sync1;out_valid<=0;frame_err<=0;
            case(state)
                IDLE: if(!sync2) begin timer<=PERIOD/2-1;state<=START;end
                START: if(timer!=0)timer<=timer-1'b1;
                       else if(sync2)state<=IDLE;
                       else begin timer<=PERIOD-1;bit_index<=0;state<=DATA;end
                DATA: if(timer!=0)timer<=timer-1'b1;
                      else begin
                        shift[bit_index]<=sync2;timer<=PERIOD-1;
                        if(bit_index==7)state<=STOP;else bit_index<=bit_index+1'b1;
                      end
                STOP: if(timer!=0)timer<=timer-1'b1;
                      else begin
                        if(sync2)begin out_data<=shift;out_valid<=1;end
                        else frame_err<=1;
                        state<=IDLE;
                      end
                default:state<=IDLE;
            endcase
        end
    end
endmodule

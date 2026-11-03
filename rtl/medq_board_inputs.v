`timescale 1ns/1ps
// Board contacts are asynchronous. Synchronize before debounce/control use.
module medq_board_inputs(input wire clk,rst_n,input wire [3:0] keys,switches,
 output reg [3:0] keys_sync,switches_sync);
 (* ASYNC_REG="TRUE" *) reg [3:0] keys_meta,switches_meta;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin keys_meta<=15;switches_meta<=15;keys_sync<=15;switches_sync<=15;end
  else begin keys_meta<=keys;keys_sync<=keys_meta;switches_meta<=switches;switches_sync<=switches_meta;end
 end
endmodule

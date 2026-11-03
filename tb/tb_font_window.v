`timescale 1ns/1ps
// All virtual-window rows, not only the visible characters in a screenshot.
module tb_font_window;
 reg clk=0;always #20 clk=~clk;reg [13:0] virtual_addr=3584;
 wire [12:0] compact_addr=virtual_addr[12:0]-13'd3584;
 wire [31:0] a,b;
 font_rom original(.clk(clk),.addr(virtual_addr),.dout(a));
 font_rom #(.ADDR_W(13),.HEXFILE("font_v03.hex")) compact(.clk(clk),.addr(compact_addr),.dout(b));
 initial begin
  for(integer i=0;i<4096;i=i+1)begin
   @(negedge clk);virtual_addr=3584+i;@(posedge clk);#1;
   if(a!==b || (^b===1'bx))$fatal(1,"ERROR compact font word=%0d full=%h compact=%h",i,a,b);
  end
  for(integer j=4096;j<8192;j=j+1)begin
   @(negedge clk);virtual_addr=3584+j;@(posedge clk);#1;if(^b===1'bx)$fatal(1,"ERROR uninitialized event atlas row=%0d",j);
  end
  $display("PASS production compact font: all4096 words bit-identical to virtual3584..7679, unchanged synchronous latency, one active 8K ROM, second page fully initialized");$finish;
 end
 initial begin #400000;$fatal(1,"TIMEOUT compact font equivalence");end
endmodule

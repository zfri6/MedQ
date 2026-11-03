`timescale 1ns/1ps
// Calling remains available even when removable media cannot provide speech.
module medq_service_guard #(parameter integer STARTUP_CYCLES=100000000)(
 input wire clk,rst_n,assets_ok,load_error,memory_ready,memory_fault,underrun,
 input wire [3:0] progress,output wire [7:0] service_status);
 function integer bits;
  input integer n;integer v;
  begin bits=1;v=n-1;while(v>1)begin bits=bits+1;v=v>>1;end end
 endfunction
 localparam WIDTH=bits(STARTUP_CYCLES);
 reg [WIDTH-1:0] timer;
 reg deadline,warning;
 reg [1:0] mode;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin timer<=0;deadline<=0;warning<=0;end
  else begin
   if(!deadline)begin
    if(timer==STARTUP_CYCLES-1)deadline<=1;
    else timer<=timer+1'b1;
   end
   if(assets_ok && underrun)warning<=1;
  end
 end
 always @* begin
  if(memory_fault || (deadline && !memory_ready))mode=3;
  else if(assets_ok && !load_error && memory_ready)mode=1;
  else if(load_error || deadline)mode=2;
  else mode=0;
 end
 assign service_status=rst_n ? {progress,warning,1'b0,mode}:8'd0;
endmodule

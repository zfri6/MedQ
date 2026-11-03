`timescale 1ns/1ps
// Finite fallback chime, no continuous idle tone.
module medq_call_feedback #(parameter integer DURATION_CYCLES=3750000)(
 input wire clk,rst_n,call_pulse,voice_ready,output wire tone_enable);
 function integer bits;
  input integer n;integer v;
  begin bits=1;v=n;while(v>1)begin bits=bits+1;v=v>>1;end end
 endfunction
 localparam WIDTH=bits(DURATION_CYCLES);
 reg [WIDTH-1:0] remaining;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)remaining<=0;
  else if(voice_ready)remaining<=0;
  else if(call_pulse)remaining<=DURATION_CYCLES;
  else if(remaining!=0)remaining<=remaining-1'b1;
 end
 assign tone_enable=rst_n && remaining!=0;
endmodule

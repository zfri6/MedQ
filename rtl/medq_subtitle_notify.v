`timescale 1ns/1ps
// Carry each room's admitted announcement (including replay) into the existing
// frame-snapshotted UI bus. No queue/audio/control side effects.
module medq_subtitle_notify(input wire clk,rst_n,
 input wire [127:0] state_in,input wire [1:0] announcement_start,grant,
 output wire [127:0] state_out);
 reg [1:0] epoch;
 reg [15:0] seen_a,seen_b;
 reg [14:0] message_a,message_b;
 wire replay_a=announcement_start[0] && !grant[0];
 wire replay_b=announcement_start[1] && !grant[1];
 // Forward a just-committed operation immediately, so a frame on the very
 // next clock cannot pair a new card state with an old operation subtitle.
 wire [15:0] visible_a=replay_a ? {~epoch[0],4'd3,state_in[22],state_in[7:0],2'b00} :
   state_in[83:68]!=seen_a ? {~epoch[0],state_in[82:68]} : {epoch[0],message_a};
 wire [15:0] visible_b=replay_b ? {~epoch[1],4'd3,state_in[54],state_in[39:32],2'b00} :
   state_in[99:84]!=seen_b ? {~epoch[1],state_in[98:84]} : {epoch[1],message_b};
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin epoch<=0;seen_a<=0;seen_b<=0;message_a<=0;message_b<=0;end
  else begin
   seen_a<=state_in[83:68];seen_b<=state_in[99:84];
   if(announcement_start[0] && !grant[0])begin
    epoch[0]<=!epoch[0];message_a<={4'd3,state_in[22],state_in[7:0],2'b00};
   end else if(state_in[83:68]!=seen_a)begin epoch[0]<=!epoch[0];message_a<=state_in[82:68];end
   if(announcement_start[1] && !grant[1])begin
    epoch[1]<=!epoch[1];message_b<={4'd3,state_in[54],state_in[39:32],2'b00};
   end else if(state_in[99:84]!=seen_b)begin epoch[1]<=!epoch[1];message_b<=state_in[98:84];end
  end
 end
 assign state_out={state_in[127:100],visible_b,visible_a,
   state_in[67:57],visible_b[15],state_in[55:25],visible_a[15],state_in[23:0]};
endmodule

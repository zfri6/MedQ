`timescale 1ns/1ps
// Final HDMI PCM, signed and volume-adjusted. History snapshots only at VS.
// Four-pixel linear interpolation gives a restrained antialiased live wave.
module medq_audio_wave(input wire clk,rst_n,frame_start,de,stb,enabled,
 input wire [9:0] x,y,input wire [15:0] sample,
 output reg [23:0] rgb,output reg [7:0] alpha);
 reg signed [4:0] history[0:31],view[0:31];
 reg [6:0] divide;
 reg signed [4:0] point;
 integer k;
 always @*begin
  if($signed(sample)>16'sd14336)point=7;
  else if($signed(sample)<-16'sd14336)point=-7;
  else point=$signed(sample)>>>11;
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   divide<=0;
   for(k=0;k<32;k=k+1)begin history[k]<=0;view[k]<=0;end
  end else begin
   if(stb)begin
    if(divide==95)begin
     divide<=0;history[31]<=enabled ? point : 5'sd0;
     for(k=0;k<31;k=k+1)history[k]<=history[k+1];
    end else divide<=divide+1'b1;
   end
   if(frame_start)for(k=0;k<32;k=k+1)view[k]<=enabled ? history[k] : 5'sd0;
  end
 end
 reg [6:0] dx;
 reg signed [8:0] p0,p1,interpolated;
 reg signed [12:0] distance;
 reg [7:0] coverage;
 reg speaker;
 always @*begin
  dx=x-480;p0=0;p1=0;interpolated=0;distance=0;coverage=0;speaker=0;
  if(x>=480 && x<604 && y>=436 && y<458)begin
   p0={{4{view[dx[6:2]][4]}},view[dx[6:2]]};
   p1={{4{view[dx[6:2]+5'd1][4]}},view[dx[6:2]+5'd1]};
   interpolated=(p0<<<2)+((p1-p0)*$signed({1'b0,dx[1:0]}));
   distance=$signed({1'b0,y,2'b00})-(13'sd1788-interpolated);
   if(distance<0)distance=-distance;
   if(distance<=2)coverage=255;else if(distance==3)coverage=128;else if(distance==4)coverage=40;
  end
  if((x>=456 && x<460 && y>=444 && y<450) ||
     (x>=460 && x<465 && y>=441+(464-x) && y<453-(464-x)))speaker=1;
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin rgb<=0;alpha<=0;end
  else begin rgb<=24'h078a86;alpha<=de && enabled ? (speaker ? 8'd255 : coverage) : 8'd0;end
 end
endmodule

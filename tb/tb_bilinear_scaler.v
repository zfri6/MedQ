`timescale 1ns/1ps
module tb_bilinear_scaler;
 reg clk=0;always #10 clk=~clk;
 reg rst=0,bypass=0,iv=0,ordy=0;reg [10:0] w=3,h=3,ix=0,iy=0;reg [23:0] rgb=0;
 wire ir,ov,ol;wire [23:0] out;wire [9:0] ox,oy;
 integer phase=0,seen=0,checks=0,ticks=0,x,y,desc=0;
 reg stalled=0;reg [44:0] held;
 bilinear_scaler dut(.clk(clk),.rst_n(rst),.bypass(bypass),.src_w(w),.src_h(h),
  .in_valid(iv),.in_rgb(rgb),.in_x(ix),.in_y(iy),.in_last(1'b0),.in_ready(ir),
  .out_ready(ordy),.out_valid(ov),.out_rgb(out),.out_x(ox),.out_y(oy),.out_last(ol));
 function [23:0] pixel(input integer x,y);
  begin pixel={8'((x*37+y*11)%256),8'((x*7+y*53)%256),8'((x*19+y*23)%256)};end
 endfunction
 function [7:0] mix(input [7:0] a,b,input integer f);
  begin mix=(a*(65536-f)+b*f+32768)>>16;end
 endfunction
 function [23:0] golden(input integer x,y);
  integer sx,sy,x0,x1,y0,y1,k;
  reg [23:0] a,b,c,d;
  begin
   sx=65536*x*(w-1)/639;sy=65536*y*(h-1)/479;
   x0=sx>>16;y0=sy>>16;x1=x0+1<w ? x0+1:x0;y1=y0+1<h ? y0+1:y0;
   a=pixel(x0,y0);b=pixel(x1,y0);c=pixel(x0,y1);d=pixel(x1,y1);
   for(k=0;k<3;k=k+1)golden[k*8+:8]=mix(mix(a[k*8+:8],b[k*8+:8],sx&65535),mix(c[k*8+:8],d[k*8+:8],sx&65535),sy&65535);
  end
 endfunction
 always @(negedge clk)begin ticks=ticks+1;ordy=ticks%7!=2 && ticks%7!=3;end
 always @(posedge clk)if(rst)begin
  if(stalled && (!ov || {ol,oy,ox,out}!==held))$fatal(1,"ERROR scaler stalled output");
  stalled=ov && !ordy;held={ol,oy,ox,out};
  if(ov && ordy)begin
   if(ox!==10'(seen%640) || oy!==10'(desc ? 479-seen/640 : seen/640))$fatal(1,"ERROR scaler order phase=%0d seen=%0d x=%0d y=%0d",phase,seen,ox,oy);
   if(out!==(bypass ? pixel(ox,oy):golden(ox,oy)))$fatal(1,"ERROR scaler pixel phase=%0d xy=%0d/%0d got=%h exp=%h",phase,ox,oy,out,golden(ox,oy));
   if(ol!==(seen==307199))$fatal(1,"ERROR scaler last phase=%0d seen=%0d",phase,seen);
   seen=seen+1;checks=checks+1;
  end
 end else stalled=0;
 initial begin
  repeat(5)@(negedge clk);rst=1;
  for(phase=0;phase<4;phase=phase+1)begin
   seen=0;bypass=phase>=2;desc=phase%2;
   w=bypass?640:(phase==0?1:3);h=bypass?480:(phase==0?1:3);
   for(y=0;y<h;y=y+1)for(x=0;x<w;x=x+1)begin
    @(negedge clk);ix=x;iy=desc?h-1-y:y;rgb=pixel(ix,iy);iv=1;
    @(posedge clk);while(!ir)@(posedge clk);
    @(negedge clk);iv=0;
   end
   wait(seen==307200);repeat(5)@(negedge clk);
  end
  $display("PASS scaler: 1228800 exact pixels, 1x1 and 3x3, both orientations, 640x480 bypass, stalls and consecutive images");$finish;
 end
 initial begin #300000000;$fatal(1,"TIMEOUT scaler phase=%0d seen=%0d state=%0d",phase,seen,dut.state);end
endmodule

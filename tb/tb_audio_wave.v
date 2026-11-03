`timescale 1ns/1ps
module tb_audio_wave;
 reg clk=0,rst=0,frame=0,de=1,stb=0,enabled=1;always #5 clk=~clk;
 reg [9:0] x=0,y=0;reg [15:0] sample=0;wire [23:0] rgb;wire [7:0] alpha;
 medq_audio_wave dut(.clk(clk),.rst_n(rst),.frame_start(frame),.de(de),.stb(stb),.enabled(enabled),.x(x),.y(y),.sample(sample),.rgb(rgb),.alpha(alpha));
 integer points[0:31];integer i,j,xx,yy,p0,p1,interpolated,distance,want,checks=0,nonflat=0;
 task raster;
  begin
   for(yy=436;yy<458;yy=yy+1)for(xx=480;xx<604;xx=xx+1)begin
    @(negedge clk);x=xx;y=yy;
    p0=points[(xx-480)/4];p1=points[(xx-480)/4+1];
    interpolated=p0*4+(p1-p0)*((xx-480)%4);
    distance=yy*4-(447*4-interpolated);if(distance<0)distance=-distance;
    want=distance<=2 ? 255 : distance==3 ? 128 : distance==4 ? 40 : 0;
    @(posedge clk);#1;
    if(alpha!==want || rgb!==24'h078a86)$fatal(1,"ERROR audio wave x=%0d y=%0d got=%0d expected=%0d",xx,yy,alpha,want);
    checks=checks+1;
   end
  end
 endtask
 initial begin
  for(i=0;i<32;i=i+1)points[i]=0;
  repeat(5)@(negedge clk);rst=1;repeat(3)@(negedge clk);
  raster;
  // Signed HDMI sample amplitudes after mixer, both saturation directions.
  for(i=0;i<32;i=i+1)begin
   @(negedge clk);
   sample=(i%16-8)*4096;stb=1;
   points[i]=($signed(sample)>14336 ? 7 : $signed(sample)<-14336 ? -7 : $signed(sample)>>>11);
   repeat(96)@(posedge clk);#1;
  end
  @(negedge clk);stb=0;
  // The incoming samples must not tear the current displayed frame.
  for(i=0;i<32;i=i+1)if(dut.view[i]!==0)$fatal(1,"ERROR audio snapshot changed inside frame");
  frame=1;@(negedge clk);frame=0;repeat(3)@(negedge clk);raster;
  enabled=0;@(negedge clk);x=484;y=447;@(posedge clk);#1;
  if(alpha!==0)$fatal(1,"ERROR waveform visible on cover");
  $display("PASS HDMI waveform: %0d exact antialiased/interpolated pixels, signed amplitude/saturation, silence baseline, frame-held history and cover suppression",checks);$finish;
 end
 initial begin #1000000;$fatal(1,"TIMEOUT waveform");end
endmodule

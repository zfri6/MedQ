`timescale 1ns/1ps
// Independent integer signed mix * volume /256, including negative floor.
module tb_audio_mixer_signed;
 reg clk=0,rst=0,stb=0;always #5 clk=~clk;
 reg [15:0] tone=0,pcm=0;reg [7:0] volume=0;
 wire [15:0] left,right;
 audio_mixer dut(.clk(clk),.rst_n(rst),.stb(stb),.tone_in(tone),.pcm_in(pcm),.volume(volume),.aud_l(left),.aud_r(right));
 integer a,b,v,want,checks=0,i;reg [31:0] random_state=32'h20307159;
 task check(input integer t,input integer p,input integer gain);
  begin
   @(negedge clk);tone=t;pcm=p;volume=gain;stb=1;
   want=(t+p)*gain;
   want=want>=0 ? want/256 : -((-want+255)/256);
   if(want>32767)want=32767;if(want< -32768)want=-32768;
   @(posedge clk);#1;
   if($signed(left)!==want || left!==right)$fatal(1,"ERROR signed mixer t=%0d p=%0d gain=%0d got=%0d expected=%0d",t,p,gain,$signed(left),want);
   checks=checks+1;
   @(negedge clk);stb=0;tone=16'h7fff;pcm=16'h8000;volume=255;
   @(posedge clk);#1;if($signed(left)!==want)$fatal(1,"ERROR mixer changed without strobe");
  end
 endtask
 initial begin
  repeat(4)@(negedge clk);rst=1;
  check(0,-1000,128);check(0,1000,128);check(-32768,0,255);check(32767,32767,255);check(-32768,-32768,255);
  check(32767,-32768,255);check(-32768,32767,0);check(1,0,1);check(-1,0,1);
  for(i=0;i<4096;i=i+1)begin
   random_state=random_state*1664525+1013904223;a=$signed(random_state[15:0]);
   random_state=random_state*1664525+1013904223;b=$signed(random_state[15:0]);
   random_state=random_state*1664525+1013904223;v=random_state[7:0];check(a,b,v);
  end
  $display("PASS signed HDMI mixer: %0d independent integer reference checks, negative PCM, gain0/1/128/255, positive/negative saturation, stereo identity, strobe hold",checks);$finish;
 end
 initial begin #1000000;$fatal(1,"TIMEOUT signed mixer");end
endmodule

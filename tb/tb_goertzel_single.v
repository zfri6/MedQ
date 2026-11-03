`timescale 1ns/1ps
// Independent existing fixed-point vectors, one-bin corner and same-address RAM forwarding.
module tb_goertzel_single;
 reg clk=0;always #20 clk=~clk;
 reg rst=0,stb=0;reg [15:0] sample=0;
 wire valid;wire [3:0] index;wire [7:0] mag,level;
 reg [15:0] samples[0:3071];reg [7:0] expected[0:191];
 integer results=0,b,n;
 goertzel_spectrum #(.BINS(1)) dut(clk,rst,stb,sample,valid,index,mag,level);
 task push(input [15:0] s);
  begin @(negedge clk);sample=s;stb=1;@(negedge clk);stb=0;repeat(518)@(negedge clk);end
 endtask
 always @(posedge clk)begin #1;if(rst && valid)begin
  if(index!==0 || mag!==expected[results*16])$fatal(1,"ERROR single bin=%0d mag=%0d expected=%0d",results,mag,expected[results*16]);
  results=results+1;
 end end
 initial begin
  $readmemh("medq_spectrum_samples.hex",samples);$readmemh("medq_spectrum_expected.hex",expected);
  repeat(4)@(negedge clk);rst=1;
  for(b=0;b<12;b=b+1)begin
   if(b==3)begin for(n=0;n<32;n=n+1)push(16'(n*777));rst=0;repeat(3)@(negedge clk);rst=1;end
   for(n=0;n<256;n=n+1)push(samples[b*256+n]);
   if(results!=b+1)$fatal(1,"ERROR single-bin result count");
  end
  $display("PASS single-bin Goertzel RAM forwarding: 12 independent vector blocks and partial reset");$finish;
 end
 initial begin #100000000;$fatal(1,"TIMEOUT single-bin");end
endmodule

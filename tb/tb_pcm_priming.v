`timescale 1ns/1ps
// Initial descriptor latency is allowed; starvation after playback is not.
module tb_pcm_priming;
 reg pix=0,mem=0,rst=0,request=0,stb=0;
 always #20 pix=~pix;
 always #10 mem=~mem;
 integer tick=0;
 always @(negedge pix)begin tick=tick+1;stb=(tick%4)==0;end
 reg ready=0,valid=0;
 wire req,rd_ready,busy,done,underrun;
 wire [15:0] sample;
 wire [21:0] address;wire [8:0] length;
 audio_pcm_player dut(.clk_pix(pix),.rst_n_pix(rst),.clk_mem(mem),.rst_n_mem(rst),.stb(stb),
  .play_req(request),.play_base(22'h0e1000),.play_samples(22'd6),.play_busy(busy),.play_done(done),.sample(sample),.underrun(underrun),
  .aud_req_valid(req),.aud_req_ready(ready),.aud_req_addr(address),.aud_req_we(),.aud_req_len(length),
  .aud_wr_valid(),.aud_wr_ready(1'b0),.aud_wr_data(),.aud_rd_valid(valid),.aud_rd_ready(rd_ready),.aud_rd_data({16'd400,16'd100}));
 integer silent_strobes=0,n;
 initial begin
  repeat(5)@(negedge pix);rst=1;
  @(negedge pix);request=1;@(negedge pix);request=0;
  wait(req);
  repeat(80)begin
   @(posedge pix);#1;
   if(underrun || sample!==0 || !busy)$fatal(1,"FAIL initial prefetch reported underrun");
   if(stb)silent_strobes=silent_strobes+1;
  end
  if(silent_strobes<16 || address!==22'h0e1000 || length!==3)$fatal(1,"FAIL priming coverage/descriptor");
  @(negedge mem);ready=1;@(posedge mem);@(negedge mem);ready=0;
  wait(rd_ready);@(negedge mem);valid=1;@(posedge mem);@(negedge mem);valid=0;
  // Return just one word, deliberately withholding the rest of the descriptor.
  wait(sample===16'd100);
  for(n=2;n<=3;n=n+1)begin
   @(posedge pix);while(!stb)@(posedge pix);#1;
   if(sample!==n*100 || underrun)$fatal(1,"FAIL interpolated sample during RUN");
  end
  @(posedge pix);while(!stb)@(posedge pix);#1;
  if(!underrun || sample!==0)$fatal(1,"FAIL real mid-clip starvation was hidden");
  $display("PASS PCM priming: %0d initial silent strobes, exact first interpolation, genuine mid-clip starvation detected",silent_strobes);$finish;
 end
 initial begin #100000;$fatal(1,"TIMEOUT PCM priming");end
endmodule

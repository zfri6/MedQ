`timescale 1ns/1ps
module tb_dual_audio;
 reg clk=0,memclk=0;always #20 clk=~clk;always #10 memclk=~memclk;
 reg rst=0,run=1;reg [3:0] enq=0;reg [1:0] doc=0;
 wire [1:0] req,grant,rr;wire [15:0] tickets;wire [127:0] q;
 wire [5:0] clip;wire preq,busy,done,abort_pcm,tone,announcing,active_room;
 wire [7:0] active_ticket;wire [21:0] base,samples;
 wire rv,ready,we,wvalid,rready,rdvalid;wire [21:0] addr;wire [8:0] len;wire [31:0] wd,rd;
 wire [15:0] sample;wire underrun;reg stb=0;integer divider=0;
 always @(posedge clk)begin divider<=divider==4 ? 0 : divider+1;stb<=divider==4;end
 medq_dual_service #(.INTERVAL_CYCLES(1000000)) service(.clk(clk),.rst_n(rst),.running({2{run}}),.inputs_ready(1'b1),
 .enqueue(enq),.doctor_event(doc),.grant(grant),.request(req),.request_ticket(tickets),.request_return(rr),.qstate(q));
 medq_dual_announcer #(.TONE_CYCLES(20)) arb(.clk(clk),.rst_n(rst),.running({2{run}}),.voice_ready(1'b1),.request(req),.doctor_event(doc),
 .request_ticket(tickets),.request_return(rr),.qstate(q),.grant(grant),.clip_sel(clip),.clip_base({9'd0,clip,7'd0}),.clip_samples(22'd64),
 .play_req(preq),.play_base(base),.play_samples(samples),.play_busy(busy),.play_done(done),.pcm_abort(abort_pcm),
 .fallback_tone(tone),.announcing(announcing),.active_room(active_room),.active_ticket(active_ticket));
 audio_pcm_player #(.CONTROLLED(1)) pcm(.clk_pix(clk),.rst_n_pix(rst),.clk_mem(memclk),.rst_n_mem(rst),.stb(stb),.run_enable(run),.abort_play(abort_pcm),
 .play_req(preq),.play_base(base),.play_samples(samples),.play_busy(busy),.play_done(done),.sample(sample),.underrun(underrun),
 .aud_req_valid(rv),.aud_req_ready(ready),.aud_req_addr(addr),.aud_req_we(we),.aud_req_len(len),.aud_wr_valid(wvalid),.aud_wr_ready(1'b0),
 .aud_wr_data(wd),.aud_rd_valid(rdvalid),.aud_rd_ready(rready),.aud_rd_data(rd));
 integer left=0,memaddr=0,bursts=0,beats=0;
 assign ready=left==0;assign rdvalid=left!=0;assign rd={16'h0040,16'h0020};
 always @(posedge memclk)if(!rst)left<=0;else begin
  if(rv && ready)begin left<=len;memaddr<=addr;bursts=bursts+1;end
  if(rdvalid && rready)begin left<=left-1;memaddr<=memaddr+1;beats=beats+1;end
 end
 integer starts_a=0,starts_b=0,clip_index=0,msg_room=0,msg_ticket=0,msg_return=0,pcm_starts=0,aborts=0;
 integer expected_clip,hold_phase,hold_fetched,hold_remaining;
 always @(posedge clk)if(rst)begin
  if(grant[0])begin starts_a=starts_a+1;clip_index=0;msg_room=0;msg_ticket=tickets[7:0];msg_return=rr[0];end
  if(grant[1])begin starts_b=starts_b+1;clip_index=0;msg_room=1;msg_ticket=tickets[15:8];msg_return=rr[1];end
  if(preq)begin
   case(clip_index)
    0:expected_clip=1;1:expected_clip=msg_return ? (msg_room ? 20 : 19) : (msg_room ? 17 : 2);
    2:expected_clip=3+(msg_ticket>>4);3:expected_clip=3+(msg_ticket&15);
    4:expected_clip=51;5:expected_clip=msg_room ? (msg_return ? 35+msg_ticket : 40+msg_ticket) : (msg_return ? 20+msg_ticket : 25+msg_ticket);6:expected_clip=52;7:expected_clip=msg_room ? 15 : 14;8:expected_clip=18;default:expected_clip=-1;
   endcase
   if(clip!==expected_clip || busy)$fatal(1,"ERROR voice sequence/accept index=%0d got=%0d expected=%0d busy=%b",clip_index,clip,expected_clip,busy);
   clip_index=clip_index+1;pcm_starts=pcm_starts+1;
  end
  if(abort_pcm)aborts=aborts+1;
  if(underrun)$fatal(1,"ERROR controlled PCM underrun");
 end
 task inputs(input [3:0] e,input [1:0] d);begin @(negedge clk);enq=e;doc=d;@(negedge clk);enq=0;doc=0;end endtask
 initial begin
  repeat(8)@(negedge clk);rst=1;
  inputs(3,0);wait(busy && pcm.play_started);repeat(8)@(negedge clk);
  // Independent stop/drain/replay is exercised by tb_independent_call_audio.
  run=1;inputs(1,0);inputs(4,0);
  if(q[7:0]!=1 || q[12:8]!=1 || q[17:13]!=1)$fatal(1,"ERROR return preempted active patient");
  inputs(0,1);wait(starts_b==1 && busy);repeat(10)@(negedge clk);
  if(q[19:18]!=2 || q[51:50]!=1)$fatal(1,"ERROR one-room arrival corrupts other room");
  inputs(0,1);repeat(30)@(negedge clk);
  if(abort_pcm || !active_room || starts_a!=1)$fatal(1,"ERROR A departure cancelled B voice or bypassed busy");
  wait(starts_a==2);@(negedge clk);
  if(q[7:0]!=1 || !q[22] || q[12:8]!=1 || q[17:13]!=0)$fatal(1,"ERROR pending A ordinary not rechecked for return");
  wait(!announcing && !busy);repeat(10)@(negedge clk);
  if(starts_a!=2 || starts_b!=1 || pcm_starts!=19 || aborts==0 || bursts<19 || left!=0)$fatal(1,"ERROR audio coverage a=%0d b=%0d clips=%0d abort=%0d",starts_a,starts_b,pcm_starts,aborts);
  $display("PASS fair A/B voice admission, 9-clip Chinese/A-B/BCD sequence, safe abort drain, cross-room isolation, pending return priority, complete unpaused voice sequence; PCM clips=%0d bursts=%0d beats=%0d",pcm_starts,bursts,beats);$finish;
 end
 initial begin #2000000;$fatal(1,"TIMEOUT audio state=%0d PCM=%0d a=%0d b=%0d",arb.state,pcm.state,starts_a,starts_b);end
endmodule

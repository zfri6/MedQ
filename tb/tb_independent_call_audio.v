`timescale 1ns/1ps
// Actual dual-domain PCM player: stopped rooms release shared audio fairly.
module tb_independent_call_audio;
 reg clk=0,mc=0;always #20 clk=~clk;always #10 mc=~mc;
 reg rst=0;reg [1:0] run=3,doc=0;reg [3:0] enq=0;
 wire [1:0] req,grant,ret,announcement_start;wire [15:0] tickets;wire [127:0] q;
 wire [5:0] clip;wire preq,busy,done,abort_pcm,tone,announcing,room;
 wire [7:0] ticket;wire [21:0] base,samples;
 wire rv,ready,we,wvalid,rready,rdvalid;wire [21:0] addr;wire [8:0] len;wire [31:0] wd;
 wire [15:0] sample;wire underrun;reg stb=0;integer div=0;
 always @(posedge clk)begin div<=div==2 ? 0 : div+1;stb<=div==2;end
 medq_dual_service #(.INTERVAL_CYCLES(1000000)) service(.clk(clk),.rst_n(rst),.running(run),.inputs_ready(1'b1),
  .enqueue(enq),.doctor_event(doc),.grant(grant),.request(req),.request_ticket(tickets),.request_return(ret),.qstate(q));
 medq_dual_announcer arb(.clk(clk),.rst_n(rst),.running(run),.voice_ready(1'b1),.request(req),.doctor_event(doc),
  .request_ticket(tickets),.request_return(ret),.qstate(q),.grant(grant),.announcement_start(announcement_start),.clip_sel(clip),.clip_base({9'd0,clip,7'd0}),.clip_samples(22'd64),
  .play_req(preq),.play_base(base),.play_samples(samples),.play_busy(busy),.play_done(done),.pcm_abort(abort_pcm),
  .fallback_tone(tone),.announcing(announcing),.active_room(room),.active_ticket(ticket));
 audio_pcm_player #(.CONTROLLED(1)) pcm(.clk_pix(clk),.rst_n_pix(rst),.clk_mem(mc),.rst_n_mem(rst),.stb(stb),
  .run_enable(|run),.abort_play(abort_pcm),.play_req(preq),.play_base(base),.play_samples(samples),
  .play_busy(busy),.play_done(done),.sample(sample),.underrun(underrun),.aud_req_valid(rv),.aud_req_ready(ready),
  .aud_req_addr(addr),.aud_req_we(we),.aud_req_len(len),.aud_wr_valid(wvalid),.aud_wr_ready(1'b0),.aud_wr_data(wd),
  .aud_rd_valid(rdvalid),.aud_rd_ready(rready),.aud_rd_data(32'h00400020));
 integer left=0,bursts=0,beats=0;
 assign ready=left==0;assign rdvalid=left!=0;
 always @(posedge mc)if(!rst)left<=0;else begin
  if(rv && ready)begin left<=len;bursts=bursts+1;end
  if(rdvalid && rready)begin left<=left-1;beats=beats+1;end
 end
 integer grants_a=0,grants_b=0,say_a=0,say_b=0,complete_a=0,complete_b=0,aborts=0;
 integer ix=0,mroom=0,mticket=0,mret=0,expected=0,c_prefix=0;
 always @(posedge clk)if(rst)begin
  if((grant & ~run)!=0)$fatal(1,"ERROR disabled room granted");
  if(grant[0])grants_a=grants_a+1;if(grant[1])grants_b=grants_b+1;
  if(preq)begin
   if((arb.state==0) !== (|announcement_start))$fatal(1,"ERROR replay/first-phrase subtitle event");
   if(arb.state==0)begin
    mroom=arb.choose_b;ix=0;
    mticket=grant!=0 ? (mroom ? tickets[15:8] : tickets[7:0]) : (mroom ? q[39:32] : q[7:0]);
    mret=grant!=0 ? ret[mroom] : (mroom ? q[54] : q[22]);
    if(mroom)say_b=say_b+1;else say_a=say_a+1;
   end
   if(!run[mroom] || busy)$fatal(1,"ERROR stopped room play or mailbox overwrite");
   case(ix)
    0:expected=1;1:expected=mret ? (mroom ? 20 : 19) : (mroom ? 17 : 2);
    2:expected=3+(mticket>>4);3:expected=3+(mticket&15);4:expected=51;5:expected=mroom ? (mret ? 35+mticket : 40+mticket) : (mret ? 20+mticket : 25+mticket);6:expected=52;7:expected=mroom ? 15 : 14;8:expected=18;
    default:expected=-1;
   endcase
   if(clip!==expected)$fatal(1,"ERROR replay/class/target sequence room=%0d ix=%0d got=%0d expected=%0d",mroom,ix,clip,expected);
   if(clip==19)c_prefix=c_prefix+1;
   ix=ix+1;
  end
  if(done && !abort_pcm && ix==9 && pcm.state==0)begin
   if(mroom)complete_b=complete_b+1;else complete_a=complete_a+1;
   ix=0;
  end
  if(abort_pcm)aborts=aborts+1;
  if(underrun)$fatal(1,"ERROR actual PCM underrun");
 end
 task events(input [3:0] e,input [1:0] d);begin @(negedge clk);enq=e;doc=d;@(negedge clk);enq=0;doc=0;end endtask
 reg [29:0] frozen;
 initial begin
  repeat(8)@(negedge clk);rst=1;events(3,0);
  wait(busy && pcm.play_started);@(negedge clk);run=2;
  repeat(2)@(negedge clk);frozen=service.a.elapsed;
  wait(grants_b==1 && busy && pcm.play_started);repeat(12)@(negedge clk);
  if(grants_a!=1 || q[21:20]!=1 || !arb.replay[0] || service.a.elapsed!=frozen)$fatal(1,"ERROR A stop blocked B or advanced A");
  run=1;repeat(2)@(negedge clk);frozen=service.b.elapsed;
  wait(say_a==2 && busy && pcm.play_started);repeat(40)@(negedge clk);
  if(grants_a!=1 || grants_b!=1 || q[53:52]!=1 || !arb.replay[1] || service.b.elapsed!=frozen)$fatal(1,"ERROR B stop blocked A or replay recounted");
  wait(!announcing && !busy);if(complete_a!=1 || complete_b!=0)$fatal(1,"ERROR partial sentences treated complete");
  events(0,1);events(0,1);run=3;
  wait(complete_b==1);wait(!announcing && !busy);
  if(grants_a!=1 || grants_b!=1 || say_a!=2 || say_b!=2 || arb.replay!=0 || left!=0)$fatal(1,"ERROR symmetric replay/fairness");
  run=0;events(5,0);run=1;wait(grants_a==2 && busy && pcm.play_started);@(negedge clk);run=0;
  wait(!announcing && !busy);events(0,1);events(0,1);
  if(arb.replay[0] || service.completed_a!=2)$fatal(1,"ERROR doctor while off retained stale C01 replay");
  run=1;wait(grants_a==3);@(negedge clk);wait(!announcing && !busy);
  if(q[7:0]!=2 || q[22] || q[21:20]!=1 || grants_b!=1 || q[39:32]!=1 || c_prefix!=0 || aborts<3 || beats!=bursts*32)
   $fatal(1,"ERROR disabled cancellation/class/ordinary sequence/drain totals C=%0d q=%h grants=%0d/%0d aborts=%0d beats=%0d bursts=%0d",c_prefix,q,grants_a,grants_b,aborts,beats,bursts);
  $display("PASS independent A/B stop, symmetric safe PCM drain and fair replay without extra grants, frozen per-room timers, full 9-clip number/class/room routing, SW3/SW4 cancellation while stopped, real dual-clock FIFO and burst conservation");$finish;
 end
 initial begin #5000000;$fatal(1,"TIMEOUT independent audio a=%0d b=%0d say=%0d/%0d complete=%0d/%0d state=%0d",grants_a,grants_b,say_a,say_b,complete_a,complete_b,arb.state);end
endmodule

`timescale 1ns/1ps
// Independent admission-time monitor: speech deliberately outlasts recall interval.
module tb_v03_audio_contention;
 reg clk=0;always #20 clk=~clk;reg rst=0;reg [3:0] enq=0;
 wire [1:0] request,grant,ret;wire [15:0] tickets;wire [127:0] q;
 wire [5:0] clip;wire play_req,abort_pcm,announcing,active_room;
 wire [21:0] base,samples;wire [7:0] active_ticket;
 reg busy=0,done=0;integer remaining=0,cycle=0,last_a=-100,last_b=-100,na=0,nb=0,delayed=0;
 medq_dual_service #(.INTERVAL_CYCLES(17)) service(.clk(clk),.rst_n(rst),.running(2'b11),.inputs_ready(1'b1),.enqueue(enq),.doctor_event(2'd0),
 .grant(grant),.request(request),.request_ticket(tickets),.request_return(ret),.qstate(q));
 medq_dual_announcer arb(.clk(clk),.rst_n(rst),.running(2'b11),.voice_ready(1'b1),.request(request),.doctor_event(2'd0),.request_ticket(tickets),.request_return(ret),.qstate(q),
 .grant(grant),.clip_sel(clip),.clip_base(22'd0),.clip_samples(22'd1),.play_req(play_req),.play_base(base),.play_samples(samples),.play_busy(busy),.play_done(done),
 .pcm_abort(abort_pcm),.fallback_tone(),.announcing(announcing),.active_room(active_room),.active_ticket(active_ticket));
 always @(posedge clk)begin
  cycle=cycle+1;done<=0;
  if(!rst)begin busy<=0;remaining<=0;end
  else begin
   if(play_req)begin if(busy)$fatal(1,"ERROR player request overwritten");busy<=1;remaining<=5;end
   else if(busy)begin if(remaining==0 || abort_pcm)begin busy<=0;done<=1;end else remaining<=remaining-1;end
   if(grant[0])begin
    if(na!=0 && cycle-last_a<17)$fatal(1,"ERROR A early recall");
    if(na!=0 && cycle-last_a>17)delayed=delayed+1;
    if(tickets[7:0]!=1 || q[21:20]!=na)$fatal(1,"ERROR A pending counted early/ticket changed");
    na=na+1;last_a=cycle;
   end
   if(grant[1])begin
    if(nb!=0 && cycle-last_b<17)$fatal(1,"ERROR B early recall");
    if(nb!=0 && cycle-last_b>17)delayed=delayed+1;
    if(tickets[15:8]!=1 || q[53:52]!=nb)$fatal(1,"ERROR B pending counted early/ticket changed");
    nb=nb+1;last_b=cycle;
   end
   if(na>3 || nb>3)$fatal(1,"ERROR more than three admissions");
  end
 end
 initial begin
  repeat(5)@(negedge clk);rst=1;enq=3;@(negedge clk);enq=0;
  wait(service.missed_a==1 && service.missed_b==1);@(negedge clk);
  if(na!=3 || nb!=3 || delayed<2 || service.accepted_a!=1 || service.accepted_b!=1)$fatal(1,"ERROR fairness/delay/conservation a=%0d b=%0d delayed=%0d",na,nb,delayed);
  $display("PASS contested audio: both clinics admitted exactly 3 times, every recall >=17 active cycles from actual start, %0d delayed admissions, no early counting, stable tickets, final missed conservation",delayed);$finish;
 end
 initial begin #100000;$fatal(1,"TIMEOUT contested admission");end
endmodule

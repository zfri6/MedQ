`timescale 1ns/1ps
// SW1 is a calling gate; independent debounced inputs and frame snapshots live.
module tb_sw1_live;
 reg clk=0;always #20 clk=~clk;
 reg rst=0;reg [3:0] keys=15,sw=15;wire [1:0] run;wire ready;
 wire [3:0] enq;wire [1:0] doc,req,grant,ret;
 wire [15:0] tickets;wire [127:0] q;
 wire [5:0] clip;wire preq,abort_pcm,announcing,room;
 wire [7:0] ticket;wire [21:0] base,samples;
 reg busy=0,done=0,fs=0;integer left=0,starts=0,aborts=0,c_prefixes=0,d_prefixes=0;
 reg [9:0] x=100,y=260;wire [13:0] fa;wire [4:0] fc;wire [23:0] bg,fg;wire text_on;wire [7:0] opacity;
 medq_v03_inputs #(.DEBOUNCE_CYCLES(2),.INIT_CYCLES(2)) inputs_dut(
  .clk(clk),.rst_n(rst),.keys_sync(keys),.switches_sync(sw),.running(run),.ready(ready),.enqueue(enq),.doctor_event(doc));
 medq_dual_service #(.INTERVAL_CYCLES(1000000)) service(
  .clk(clk),.rst_n(rst),.running(run),.inputs_ready(ready),.enqueue(enq),.doctor_event(doc),.grant(grant),
  .request(req),.request_ticket(tickets),.request_return(ret),.qstate(q));
 medq_dual_announcer arb(.clk(clk),.rst_n(rst),.running(run),.voice_ready(1'b1),.request(req),.doctor_event(doc),
  .request_ticket(tickets),.request_return(ret),.qstate(q),.grant(grant),.clip_sel(clip),.clip_base(22'd0),.clip_samples(22'd1),
  .play_req(preq),.play_base(base),.play_samples(samples),.play_busy(busy),.play_done(done),.pcm_abort(abort_pcm),
  .fallback_tone(),.announcing(announcing),.active_room(room),.active_ticket(ticket));
 medq_dual_ui_scene scene(.clk(clk),.rst_n(rst),.x(x),.y(y),.frame_start(fs),.qstate(q),.service_status(8'd1),
  .font_addr(fa),.font_column(fc),.background(bg),.foreground(fg),.text_active(text_on),.text_opacity(opacity));
 always @(posedge clk)begin
  done<=0;
  if(!rst)begin busy<=0;left<=0;end
  else begin
   if(!run && (|grant || preq))$fatal(1,"ERROR SW1 off admitted a call");
   if(|grant)starts=starts+1;
   if(preq)begin
    if(busy)$fatal(1,"ERROR player overwrite");
    busy<=1;left<=5;
    if(clip==19)c_prefixes=c_prefixes+1;
    if(clip==20)d_prefixes=d_prefixes+1;
   end else if(abort_pcm)begin busy<=0;left<=0;done<=1;aborts=aborts+1;end
   else if(busy && run)begin if(left==0)begin busy<=0;done<=1;end else left<=left-1;end
  end
 end
 task settle;begin repeat(12)@(negedge clk);end endtask
 task press(input [3:0] mask);begin @(negedge clk);keys=~mask;settle;keys=15;settle;end endtask
 task frame;begin @(negedge clk);fs=1;@(negedge clk);fs=0;end endtask
 reg [9:0] saved_scroll;reg [29:0] saved_elapsed;integer saved_left;
 initial begin
  repeat(5)@(negedge clk);rst=1;wait(ready);settle;
  press(15);frame;saved_scroll=scene.scroll_a;repeat(8)frame;
  if(run || starts!=0 || req!=0 || q[12:8]!=1 || q[17:13]!=1 || q[44:40]!=1 || q[49:45]!=1 ||
     scene.frame_state[12:8]!=1 || scene.scroll_a==saved_scroll)$fatal(1,"ERROR disabled call gate blocked enqueue/display");
  sw[1:0]=0;wait(run==3);wait(preq && clip==19);@(negedge clk);sw[1:0]=3;wait(run==0);settle;
  saved_elapsed=service.a.elapsed;saved_left=left;press(5);repeat(40)@(negedge clk);frame;
  if(starts!=1 || service.a.elapsed!=saved_elapsed || (left!=0 || busy || !arb.replay[0]) || q[12:8]!=2 || q[17:13]!=1 || q[7:0]!=1 || !q[22] || scene.lg!=12)
   $fatal(1,"ERROR SW1 off progress/count/C01 prefix starts=%0d elapsed=%0d/%0d left=%0d busy=%b replay=%b q=%h lg=%0d",starts,service.a.elapsed,saved_elapsed,left,busy,arb.replay,q,scene.lg);
  sw[2]=!sw[2];settle;
  if(q[19:18]!=2 || aborts==0 || busy)$fatal(1,"ERROR disabled calling blocked doctor/cancel drain");
  sw[2]=!sw[2];settle;
  if(q[19:18]!=0 || service.completed_a!=1 || starts!=1)$fatal(1,"ERROR disabled calling blocked departure");
  sw[1:0]=0;wait(run==3);wait(starts==3);wait(!announcing && !busy);settle;
  if(c_prefixes<1 || d_prefixes!=1 || q[7:0]!=2 || !q[22] || q[39:32]!=1 || !q[54] ||
     q[12:8]!=2 || q[17:13]!=0 || q[44:40]!=1 || q[49:45]!=0 || service.accepted_a!=4 || service.accepted_b!=2)
   $fatal(1,"ERROR independent C/D numbering/room routing/priority");
  $display("PASS SW1 off accepts all four queues, live frame/marquees, no grants/recall/timer progress and safe PCM drain, doctor cancellation while off, C01/C02 and D01 voice prefixes, independent A/B ordinary counters and conservation");
  $finish;
 end
 initial begin #2000000;$fatal(1,"TIMEOUT SW1 live acceptance starts=%0d",starts);end
endmodule

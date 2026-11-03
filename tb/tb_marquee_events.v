`timescale 1ns/1ps
// Real service events plus notifier and frame consumer; no DUT state deposits.
module tb_marquee_events;
 reg clk=0;always #20 clk=~clk;
 reg rst=0,fs=0;reg [1:0] run=0,doc=0,allow=0,replay=0;reg [3:0] enq=0;
 wire [1:0] req,grant,ret;assign grant=req&allow;wire [15:0] ticket;wire [127:0] raw,q;
 wire [13:0] fa;wire [4:0] fc;wire [23:0] bg,fg;wire text_on;wire [7:0] opacity;
 medq_dual_service #(.AW(1),.MAX_TICKET(3),.INTERVAL_CYCLES(9)) service(
  .clk(clk),.rst_n(rst),.inputs_ready(1'b1),.running(run),.enqueue(enq),.doctor_event(doc),.grant(grant),
  .request(req),.request_ticket(ticket),.request_return(ret),.qstate(raw));
 medq_subtitle_notify notify(.clk(clk),.rst_n(rst),.state_in(raw),.announcement_start(grant|replay),.grant(grant),.state_out(q));
 medq_dual_ui_scene scene(.clk(clk),.rst_n(rst),.x(10'd24),.y(10'd80),.frame_start(fs),.qstate(q),.service_status(8'd1),
  .font_addr(fa),.font_column(fc),.background(bg),.foreground(fg),.text_active(text_on),.text_opacity(opacity));
 integer checks=0;reg [9:0] covered=0;reg [15:0] msg;reg old_epoch;reg [9:0] b_before,home;
 task settle;begin repeat(4)@(negedge clk);end endtask
 task frame;begin @(negedge clk);fs=1;@(negedge clk);fs=0;end endtask
 task events(input [3:0] e,input [1:0] d);begin @(negedge clk);enq=e;doc=d;@(negedge clk);enq=0;doc=0;end endtask
 task check(input integer room,input integer kind,input [7:0] bcd,input bit isret);
  begin
   settle;msg=q[68+room*16+:16];
   if(msg[14:11]!=kind || (bcd!=0 && (msg[9:2]!=bcd || msg[10]!=isret)))
    $fatal(1,"ERROR event payload room=%0d want kind=%0d ticket=%h ret=%b got=%h",room,kind,bcd,isret,msg);
   home=scene.subtitle_home(room ? q[63:32] : q[31:0],q[68+room*16+:16],room!=0);
   frame;
   if((room ? scene.scroll_b : scene.scroll_a)!=home || scene.scroll_phase[room]!=0 || scene.frame_state!==q)
    $fatal(1,"ERROR event not atomically visible at next centered frame");
   frame;if((room ? scene.scroll_b : scene.scroll_a)!=home)$fatal(1,"ERROR phase reset first frame");
   frame;if((room ? scene.scroll_b : scene.scroll_a)!=(home+1)%592)$fatal(1,"ERROR independent two-frame scroll restart");
   covered[kind]=1;checks=checks+1;
  end
 endtask
 task admit(input integer room);
  begin wait(req[room]);@(negedge clk);allow=1<<room;@(negedge clk);allow=0;end
 endtask
 initial begin
  repeat(5)@(negedge clk);rst=1;settle;frame;repeat(20)frame;
  events(1,0);check(0,1,1,0);events(4,0);check(0,2,1,1);
  events(1,0);check(0,1,2,0);events(1,0);check(0,9,0,0);
  old_epoch=q[83];repeat(20)frame;
  events(1,0);settle;events(1,0);settle;
  if(q[83]!==old_epoch)$fatal(1,"ERROR repeated rejection epoch parity");
  frame;if(scene.scroll_a!=scene.subtitle_home(q[31:0],q[83:68],0))$fatal(1,"ERROR two same-value events lost between frames");
  @(negedge clk);run=1;check(0,7,0,0);admit(0);check(0,3,1,1);
  admit(0);check(0,3,1,1); // same patient recall must refresh immediately
  events(0,1);check(0,4,1,1);events(0,1);check(0,5,1,1);
  run=0;check(0,6,0,0);repeat(20)frame;b_before=scene.scroll_a;
  events(2,0);check(1,1,1,0);
  if(scene.scroll_a==scene.subtitle_home(q[31:0],q[83:68],0) || scene.scroll_a<b_before)$fatal(1,"ERROR B operation reset A marquee");
  run=2;check(1,7,0,0);admit(1);check(1,3,1,0);run=0;check(1,6,0,0);
  run=2;check(1,7,0,0);
  @(negedge clk);replay=2;@(negedge clk);replay=0;check(1,3,1,0);
  if(q[53:52]!=1)$fatal(1,"ERROR replay changed call count");
  events(0,2);check(1,4,1,0);events(0,2);check(1,5,1,0);
  run=0;settle;events(4,0);check(0,2,2,1);run=1;settle;
  admit(0);admit(0);admit(0);wait(q[19:18]==0);check(0,8,2,1);
  run=0;settle;repeat(20)frame;
  // A transient enable/disable pair between frames must still refresh.
  run=1;settle;run=0;settle;frame;if(scene.scroll_a!=scene.subtitle_home(q[31:0],q[83:68],0))$fatal(1,"ERROR short enable pair lost");
  // Commit on the clock immediately before frame_start, with no settling gap.
  @(negedge clk);enq=2;@(negedge clk);enq=0;fs=1;@(posedge clk);#1;
  if(scene.scroll_b!=scene.subtitle_home(q[63:32],q[99:84],1) || scene.frame_state[98:95]!=1 || scene.frame_state[93:86]!=2)
   $fatal(1,"ERROR just-committed event paired with stale subtitle at frame");
  @(negedge clk);fs=0;
  if(covered[9:1]!=9'h1ff || checks<18)$fatal(1,"ERROR incomplete functional event coverage");
  $display("PASS %0d real operation events: enqueue/return/refusal/enable/pause/call/recall/arrival/departure/missed, old patient preserved, safe replay notification, same-value repeated events, next-frame centered reset, independent A/B phase, no queue/call side effects",checks);$finish;
 end
 initial begin #500000;$fatal(1,"TIMEOUT functional marquees checks=%0d q=%h",checks,q);end
endmodule

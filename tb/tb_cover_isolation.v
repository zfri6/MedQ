`timescale 1ns/1ps
// Public clock, contact levels and frame pulse only. No force/deposit.
module tb_cover_isolation;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,frame=0;reg [3:0] keys=15,switches=12;reg [2:0] media=7;
 wire visible,enabled,show;wire [6:0] alpha;wire [21:0] base;
 wire [1:0] running,doctors;wire ready;wire [3:0] enqueue;
 medq_media_control #(.DEBOUNCE_CYCLES(4),.HOLD_FRAMES(5)) dut(
  .clk(clk),.rst_n(rst),.frame_start(frame),.keys_sync(keys),.media_valid(media),
  .clinic_visible(visible),.clinic_enable(enabled),.fb_base(base),.media_show(show),.photo_alpha(alpha));
 medq_v03_inputs #(.DEBOUNCE_CYCLES(4),.INIT_CYCLES(5)) inputs(
  .clk(clk),.rst_n(rst && enabled),.keys_sync(keys),.switches_sync(switches),
  .running(running),.ready(ready),.enqueue(enqueue),.doctor_event(doctors));
 integer enqueues=0,doctor_count=0,frames=0,scenario,i,j,changes=0,zeros=0;
 reg [21:0] old_base;reg [6:0] old_alpha;reg old_visible;
 always @(posedge clk)begin
  if(rst && (|enqueue))enqueues=enqueues+1;
  if(rst && (|doctors))doctor_count=doctor_count+1;
  if(rst && !enabled && ((|enqueue)||(|doctors)||ready||(|running)))$fatal(1,"ERROR cover controls escaped isolation");
 end
 task tick(input integer n);begin repeat(n)@(negedge clk);end endtask
 task vs;begin @(negedge clk);frame=1;@(negedge clk);frame=0;frames=frames+1;end endtask
 task reset;begin rst=0;tick(4);rst=1;enqueues=0;doctor_count=0;tick(15);end endtask
 initial begin
  for(scenario=0;scenario<4;scenario=scenario+1)begin
   keys=~(4'b0001<<scenario);switches=12;reset;
   repeat(8)vs;
   if(visible || enabled || !show || base!=0)$fatal(1,"ERROR boot-held key bypassed cover");
   switches=0;tick(15);switches=15;tick(15);
   if(visible || enabled || doctor_count || enqueues)$fatal(1,"ERROR switches operate clinic while on cover");
   keys=15;tick(15);
   // Bounces shorter than debounce must not change the cover.
   keys=14;tick(1);keys=15;tick(1);keys=14;tick(1);keys=15;tick(10);vs;
   if(visible || enabled)$fatal(1,"ERROR bouncing cover key accepted");
   keys=~(4'b0001<<scenario);tick(12);
   if(visible || !dut.entry_pending)$fatal(1,"ERROR entry must wait for frame");
   vs;tick(10);
   if(!visible || enabled || ready)$fatal(1,"ERROR held entry key armed clinic");
   switches=0;tick(20);keys=0;tick(20);vs;
   if(enabled || enqueues || doctor_count)$fatal(1,"ERROR simultaneous held entry keys leaked");
   keys=15;tick(40);
   if(!enabled || !ready || running!=3 || enqueues || doctor_count)$fatal(1,"ERROR clean release/baseline failed");
   keys=~(4'b0001<<scenario);tick(15);keys=15;tick(15);
   if(enqueues!=1 || doctor_count!=0)$fatal(1,"ERROR fresh clinic key missing/duplicated");
   switches[2]=1;tick(15);
   if(doctor_count!=1)$fatal(1,"ERROR fresh doctor edge after entry missing");
  end
  old_base=base;old_alpha=alpha;
  for(i=0;i<230;i=i+1)begin
   vs;tick(2);
   if(alpha>64)$fatal(1,"ERROR alpha overflow");
   if(base!=old_base)begin
    if(alpha!=0 || old_alpha!=0)$fatal(1,"ERROR visible framebuffer base change");
    changes=changes+1;
   end
   if(alpha==0)zeros=zeros+1;
   old_base=base;old_alpha=alpha;
   // No frame pulse: animation and opacity must remain frozen.
   tick(11);if(base!=old_base || alpha!=old_alpha)$fatal(1,"ERROR animation tearing");
  end
  if(changes<2 || zeros<6)$fatal(1,"ERROR carousel did not alternate both portraits");
  // Missing media and no-card entry cannot deadlock the terminal.
  media=0;keys=15;reset;keys=13;tick(12);vs;keys=15;tick(40);
  if(!visible || !enabled || show || alpha!=0)$fatal(1,"ERROR no-card fallback/entry");
  $display("PASS cover: all four entry keys, boot-held/bounce/multi-key isolation, fresh SW baseline, clinic enqueue, frame-only fade, hidden swap, two-way carousel, no-card entry");$finish;
 end
 initial begin #1000000;$fatal(1,"TIMEOUT cover isolation");end
endmodule

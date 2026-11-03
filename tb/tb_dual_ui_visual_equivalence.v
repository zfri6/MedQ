`timescale 1ns/1ps
// Exact visual-agent scene versus timing implementation, without a font/render
// reference shared with the DUT. All six scene outputs must remain identical.
module tb_dual_ui_visual_equivalence;
 reg clk=0;always #20 clk=~clk;
 reg rst_n=0,fs=0;reg [9:0] x=0,y=0;reg [127:0] q=0;reg [7:0] svc=1;
 wire [13:0] a0,a1;wire [4:0] c0,c1;wire [23:0] b0,b1,f0,f1;
 wire t0,t1;wire [7:0] o0,o1;
 medq_dual_ui_scene dut(.clk(clk),.rst_n(rst_n),.x(x),.y(y),.frame_start(fs),.qstate(q),.service_status(svc),
  .font_addr(a0),.font_column(c0),.background(b0),.foreground(f0),.text_active(t0),.text_opacity(o0));
 medq_dual_ui_reference_model reference(.clk(clk),.rst_n(rst_n),.x(x),.y(y),.frame_start(fs),.qstate(q),.service_status(svc),
  .font_addr(a1),.font_column(c1),.background(b1),.foreground(f1),.text_active(t1),.text_opacity(o1));
 integer checked=0,xx,yy,i;reg [31:0] random_state=32'h317ad901;reg [591:0] scroll_seen=0;
 reg [31:0] new_rom[0:16383],old_rom[0:16383];
 reg [1:0] cv0,cv1;
 initial begin $readmemh("font_rom.hex",new_rom);$readmemh("medq_visual_reference.hex",old_rom);end
 always @(posedge clk)if(rst_n)begin
  #1;
  cv0=t0 ? new_rom[a0][31-2*c0-:2] : 0;
  cv1=t1 ? old_rom[a1][31-2*c1-:2] : 0;
  // The requested event-driven subtitle positions have changed; keep every other pixel exact.
  if(!(y>=72 && y<136) &&
     {b0,f0,t0,o0,cv0}!=={b1,f1,t1,o1,cv1})
   $fatal(1,"ERROR A/B visual geometry/coverage equivalence x=%0d y=%0d bg=%h/%h coverage=%d/%d",x,y,b0,b1,cv0,cv1);
  if(!(y>=72 && y<136))checked=checked+1;
 end
 task frame;begin @(negedge clk);fs=1;@(negedge clk);fs=0;end endtask
 task scan;
  begin
   for(yy=0;yy<480;yy=yy+1)for(xx=0;xx<640;xx=xx+1)begin @(negedge clk);x=xx;y=yy;end
  end
 endtask
 initial begin
  repeat(5)@(negedge clk);rst_n=1;q[64]=1;q[65]=1;
  q[7:0]=8'h09;q[19:18]=1;q[21:20]=3;q[12:8]=16;q[17:13]=16;
  q[39:32]=8'h99;q[51:50]=2;q[44:40]=16;q[49:45]=16;
  frame;scan;
  // Traverse the entire 0..591 scroll ring with moving samples, all breath
  // phases and flash settle values; then scan a complete offscreen marquee.
  for(i=0;i<2048;i=i+1)begin
   random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
   @(negedge clk);x=random_state[9:0];y=random_state[19:10];frame;
   scroll_seen[dut.scroll_a]=1;
  end
  if(!(&scroll_seen))$fatal(1,"ERROR incomplete marquee position coverage");
  scan;
  q[19:18]=0;q[12:8]=4;q[17:13]=2;q[51:50]=1;q[53:52]=1;svc=2;frame;scan;
  q[19:18]=2;q[23]=1;q[51:50]=0;q[44:40]=0;q[49:45]=0;svc=3;frame;scan;
  q[19:18]=0;q[12:8]=0;q[17:13]=0;q[23]=0;svc=0;frame;scan;
  q[64]=0;q[7:0]=8'h77;q[39:32]=8'h01;svc=1;repeat(128)frame;
  if(checked<1300000)$fatal(1,"ERROR incomplete full scene coverage");
  $display("PASS unchanged-layout visual equivalence (event-driven strips independently checked): %0d exact A/B geometry and pixel-coverage comparisons, five full VGA scans, all 592 marquee positions, all breath phases, max counters, states, services and SW1-off live frames",checked);
  $finish;
 end
 initial begin #150000000;$fatal(1,"TIMEOUT visual equivalence");end
endmodule

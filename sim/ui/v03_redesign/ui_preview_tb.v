`timescale 1ns/1ps
// Front-end preview only (not a regression test): renders the real osd_renderer
// + medq_dual_ui_scene pixels through the production 4K font window, the same
// compact addressing as rtl/top.v, for a set of QSTATE scenarios.
module ui_preview_tb;
 reg clk=0;always #20 clk=~clk;
 reg rst=0,fs=0,de=0;reg [9:0] x=0,y=0;reg [127:0] q=0;reg [7:0] svc=1;
 wire [13:0] addr;wire [31:0] fd;wire [23:0] rgb;wire [7:0] alpha;
 wire [11:0] compact=addr[11:0]-12'd3584;
 osd_renderer #(.LIVE_STATUS(1),.DUAL(1)) dut(.clk(clk),.rst_n(rst),.x(x),.y(y),.de(de),.line_start(1'b0),.frame_start(fs),.frame_cnt(16'd0),
  .qstate(q),.param(64'h10000000000),.service_status(svc),.cfg_we(1'b0),.cfg_addr(10'd0),.cfg_wdata(32'd0),
  .font_addr(addr),.font_dout(fd),.osd_rgb(rgb),.osd_alpha(alpha));
 font_rom #(.ADDR_W(12),.HEXFILE("font_v03.hex")) font(.clk(clk),.addr(compact),.dout(fd));
 integer f,xx,yy;
 task frames(input integer n);integer i;begin for(i=0;i<n;i=i+1)begin @(negedge clk);fs=1;@(negedge clk);fs=0;end end endtask
 // room: ticket BCD, ordinary, return, state, calls, rejected
 function [31:0] room(input [7:0] t,input [4:0] n,r,input [1:0] st,c,input rej);
  room={8'd0,rej,1'b0,c,st,r,n,t};
 endfunction
 task render(input [8*16-1:0] name);
  begin
   f=$fopen({name,".ppm"},"wb");$fwrite(f,"P6\n640 480\n255\n");
   for(yy=0;yy<480;yy=yy+1)for(xx=0;xx<640;xx=xx+1)begin
    @(negedge clk);x=xx;y=yy;de=1;
    if(xx>1 || yy>0)begin #2;$fwrite(f,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);end
   end
   @(negedge clk);de=0;#2;$fwrite(f,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);
   @(negedge clk);#2;$fwrite(f,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);$fclose(f);
  end
 endtask
 initial begin
  repeat(4)@(negedge clk);rst=1;q[65:64]=2'b11;
  svc=0;q[63:0]={room(0,0,0,0,0,0),room(0,0,0,0,0,0)};frames(3);render("s0_idle");
  svc=1;q[63:0]={room(8'h01,2,0,2,1,0),room(8'h01,3,1,1,1,0)};frames(17);render("s1_a01_b01");
  q[63:0]={room(8'h99,0,0,1,3,1),room(8'h09,16,0,2,1,0)};frames(17);render("s2_a09_b99");
  svc=2;q[63:0]={room(8'h00,4,2,0,0,0),room(8'h10,12,5,1,2,0)};frames(17);render("s3_a10_bsoon");
  svc=3;q[63:0]={room(8'h01,1,0,1,1,0),room(8'h99,5,3,1,1,0)};frames(1);render("s4_a99_flash");
  $display("PREVIEW done");$finish;
 end
endmodule

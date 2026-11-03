`timescale 1ns/1ps
module tb_dual_ui;
 reg clk=0;always #20 clk=~clk;
 reg rst=0,fs=0,de=0;reg [9:0] x=0,y=0;reg [127:0] q=0;reg [7:0] svc=1;
 wire [13:0] addr;wire [31:0] fd;wire [23:0] rgb;wire [7:0] alpha;
 osd_renderer #(.LIVE_STATUS(1),.DUAL(1)) dut(.clk(clk),.rst_n(rst),.x(x),.y(y),.de(de),.line_start(1'b0),.frame_start(fs),.frame_cnt(16'd0),
 .qstate(q),.param(64'h10000000000),.service_status(svc),.cfg_we(1'b0),.cfg_addr(10'd0),.cfg_wdata(32'd0),.font_addr(addr),.font_dout(fd),.osd_rgb(rgb),.osd_alpha(alpha));
 font_rom #(.ADDR_W(13),.HEXFILE("font_v03.hex")) font(.clk(clk),.addr(addr[12:0]-13'd3584),.dout(fd));
 reg [31:0] reference_rom[0:8191];reg [23:0] exp_now,exp_old;reg old_de=0;
 integer checked=0,ink=0,partial=0,partial2=0,output_file,xx,yy;
 // Independent reference: four coverage levels 0,1/3,2/3,1 times opacity, rounded blend.
 function [23:0] blend(input [23:0] bg,fg,input [1:0] cov,input [7:0] op);
  integer c,a;
  begin
   a=cov==0 ? 0 : cov==1 ? (op+1)/3 : cov==2 ? (2*op+1)/3 : op;
   for(c=0;c<3;c=c+1)blend[c*8+:8]=(bg[c*8+:8]*(255-a)+fg[c*8+:8]*a+127)/255;
  end
 endfunction
 reg [9:0] saved_a,saved_b;reg [127:0] saved_frame;
 reg [138:0] saved_animation;
 wire [138:0] animation={dut.u_dual_scene.scroll_phase,dut.u_dual_scene.breath,
  dut.u_dual_scene.age_a,dut.u_dual_scene.age_b,dut.u_dual_scene.glow,
  dut.u_dual_scene.route_a,dut.u_dual_scene.route_b,dut.u_dual_scene.flash_a,dut.u_dual_scene.flash_b};
 initial $readmemh("font_v03.hex",reference_rom);
 always @(posedge clk)if(rst)begin
  if(de && dut.scene_text && (dut.scene_addr<3584 || dut.scene_addr>=11776 || dut.scene_column>=16))
   $fatal(1,"ERROR production coverage atlas address/column out of range");
  exp_now=dut.scene_text ? blend(dut.scene_bg,dut.scene_fg,reference_rom[dut.scene_addr-3584][31-2*dut.scene_column-:2],dut.scene_opacity) : dut.scene_bg;
  #1;
  if(old_de)begin
   if(rgb!==exp_old || alpha!==255)$fatal(1,"ERROR coverage ROM/pixel pipeline x=%0d y=%0d rgb=%h expected=%h",x,y,rgb,exp_old);
   if(dut.scene_text && dut.scene_addr>=3584 && dut.scene_addr<11776 && reference_rom[dut.scene_addr-3584][31-2*dut.scene_column-:2]==1)partial=partial+1;
   if(dut.scene_text && reference_rom[dut.scene_addr-3584][31-2*dut.scene_column-:2]==2)partial2=partial2+1;
   checked=checked+1;
  end
  exp_old=exp_now;old_de=de;
 end else old_de=0;
 task frame;begin @(negedge clk);fs=1;@(negedge clk);fs=0;end endtask
 task render(input integer index);
  begin
   output_file=$fopen($sformatf("dual_ui_%0d.ppm",index),"wb");$fwrite(output_file,"P6\n640 480\n255\n");
   for(yy=0;yy<480;yy=yy+1)begin
    for(xx=0;xx<640;xx=xx+1)begin
     @(negedge clk);x=xx;y=yy;de=1;
     if(xx>1 || yy>0)begin #2;$fwrite(output_file,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);end
    end
   end
   @(negedge clk);de=0;#2;$fwrite(output_file,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);
   @(negedge clk);#2;$fwrite(output_file,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);$fclose(output_file);
  end
 endtask
 initial begin
  repeat(5)@(negedge clk);rst=1;q[64]=1;q[65]=1;q[7:0]=8'h01;q[19:18]=1;q[21:20]=1;q[12:8]=2;
  q[39:32]=8'h12;q[51:50]=1;q[53:52]=1;q[49:45]=3;
  frame;saved_a=dut.u_dual_scene.scroll_a;saved_b=dut.u_dual_scene.scroll_b;
  repeat(20)@(negedge clk);
  if(dut.u_dual_scene.scroll_a!=saved_a)$fatal(1,"ERROR scroll changed outside frame");
  frame;frame;
  if(dut.u_dual_scene.scroll_a!=saved_a+1 || dut.u_dual_scene.scroll_b!=saved_b+1)$fatal(1,"ERROR scroll must be 1pixel/2frames=29.7619px/s");
  render(0);
  q[19:18]=2;frame;render(1);
  q[64]=0;saved_frame=dut.u_dual_scene.frame_state;saved_a=dut.u_dual_scene.scroll_a;saved_b=dut.u_dual_scene.scroll_b;
  saved_animation=animation;
  q[7:0]=8'h99;q[39:32]=8'h77;svc=3;repeat(20)frame;
  if(dut.u_dual_scene.frame_state[7:0]!=8'h99 || dut.u_dual_scene.frame_service!=3 ||
     dut.u_dual_scene.scroll_b==saved_b || animation===saved_animation)
   $fatal(1,"ERROR SW1 off froze display or marquee");
  q[22]=1;q[54]=1;q[7:0]=1;q[39:32]=1;frame;render(2);
  q[64]=1;frame;
  for(integer j=0;j<2000;j=j+1)begin frame;if(dut.u_dual_scene.scroll_a>591 || dut.u_dual_scene.scroll_b>591)$fatal(1,"ERROR scroll wrap");end
  @(negedge clk);x=23;y=84;#1;if(dut.u_dual_scene.text_active)$fatal(1,"ERROR subtitle left clipping");
  x=616;#1;if(dut.u_dual_scene.text_active)$fatal(1,"ERROR subtitle right clipping");
  if(checked<614000)$fatal(1,"ERROR pixel coverage");
  if(partial<1000)$fatal(1,"ERROR glyph edges are not anti-aliased (partial=%0d)",partial);
  if(partial2<1000)$fatal(1,"ERROR second coverage edge level missing (partial2=%0d)",partial2);
  $display("PASS V0.3 two-bit coverage glyph ROM/pixel alignment %0d pixels (%0d partial-coverage edge pixels), two clinic snapshots, 29.7619px/s independent bounded scroll, SW1-off live updates, C/D return tickets and wrap; RTL PPM captures",checked,partial);$finish;
 end
 initial begin #40000000;$fatal(1,"TIMEOUT dual UI");end
endmodule

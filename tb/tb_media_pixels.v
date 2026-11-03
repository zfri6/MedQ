`timescale 1ns/1ps
// Pixel-pipeline test. Sources are the actual decoded runtime BMP bytes;
// screenshots are emitted by RTL, never redrawn by Python.
module tb_media_pixels;
 reg clk=0,rst=0;always #5 clk=~clk;
 reg [9:0] x=0,y=0;reg de=0,frame=0,welcome_mode=1,show=1;reg [6:0] opacity=64;
 reg [127:0] q=0;reg [63:0] parameters=0;
 wire [13:0] font_address,ref_address;wire [31:0] font_data,ref_data;
 wire [23:0] osd,old_osd,spec,spec_aligned,rgb;wire [7:0] alpha,old_alpha,spec_alpha,spec_aa;
 wire ade,ahs,avs,co_de,co_hs,co_vs;
 reg [23:0] base0=0,base1=0,old_delay=0;
 reg [23:0] pictures[0:921599];
 integer picture=0,fd=0,written=0,active=0,photo_checks=0,cover_checks=0,protected_checks=0;
 integer col,row,a,r,g,b,expected;
 osd_renderer #(.LIVE_STATUS(1),.DUAL(1),.MEDIA_LAYOUT(1)) dut(.clk(clk),.rst_n(rst),.x(x),.y(y),.de(de),
  .line_start(1'b0),.frame_start(frame),.frame_cnt(16'd0),.qstate(q),.param(parameters),.service_status(8'h01),
  .cover_mode(welcome_mode),.media_show(show),.photo_alpha(opacity),.cfg_we(1'b0),.cfg_addr(10'd0),.cfg_wdata(32'd0),
  .font_addr(font_address),.font_dout(font_data),.osd_rgb(osd),.osd_alpha(alpha));
 font_rom #(.ADDR_W(13),.HEXFILE("font_v03.hex")) font(.clk(clk),.addr(font_address[12:0]-13'd3584),.dout(font_data));
 osd_renderer #(.LIVE_STATUS(1),.DUAL(1)) baseline(.clk(clk),.rst_n(rst),.x(x),.y(y),.de(de),
  .line_start(1'b0),.frame_start(frame),.frame_cnt(16'd0),.qstate(q),.param(parameters),.service_status(8'h01),
  .cover_mode(1'b0),.media_show(1'b0),.photo_alpha(7'd0),.cfg_we(1'b0),.cfg_addr(10'd0),.cfg_wdata(32'd0),
  .font_addr(ref_address),.font_dout(ref_data),.osd_rgb(old_osd),.osd_alpha(old_alpha));
 font_rom #(.ADDR_W(13),.HEXFILE("font_v03.hex")) reference_font(.clk(clk),.addr(ref_address[12:0]-13'd3584),.dout(ref_data));
 medq_audio_wave wave(.clk(clk),.rst_n(rst),.frame_start(frame),.x(x),.y(y),.de(de),.enabled(!welcome_mode),
  .sample(16'd0),.stb(1'b0),.rgb(spec),.alpha(spec_alpha));
 medq_video_align align(.clk(clk),.rst_n(rst),.de(de),.hs(1'b1),.vs(1'b1),.spec_rgb(spec),.spec_alpha(spec_alpha),
  .de_out(ade),.hs_out(ahs),.vs_out(avs),.spec_rgb_out(spec_aligned),.spec_alpha_out(spec_aa));
 osd_compositor compositor(.clk(clk),.rst_n(rst),.de_in(ade),.hs_in(ahs),.vs_in(avs),.rgb_base(base1),
  .osd_rgb(osd),.osd_alpha(alpha),.spec_rgb(spec_aligned),.spec_alpha(spec_aa),.param(parameters),
  .de_out(co_de),.hs_out(co_hs),.vs_out(co_vs),.rgb_out(rgb));
 always @(posedge clk)begin base0<=pictures[picture*307200+y*640+x];base1<=base0;old_delay<=old_osd;end
 always @(negedge clk)begin
  #1;
  if(rst && co_de && active)begin
   col=written%640;row=written/640;
   if((^rgb)===1'bx)$fatal(1,"ERROR unknown media pixel %0d,%0d",col,row);
   if(welcome_mode)begin
    if(rgb!==pictures[written])$fatal(1,"ERROR cover pixel alignment x=%0d y=%0d got=%h exp=%h",col,row,rgb,pictures[written]);
    cover_checks=cover_checks+1;
   end else if(col>=456 && col<608 && row>=298 && row<426)begin
    a=opacity==64 ? 255 : opacity*4;
    expected=pictures[picture*307200+written];
    r=(((expected>>16)&255)*a+255*(255-a)+127)/255;
    g=(((expected>>8)&255)*a+255*(255-a)+127)/255;
    b=((expected&255)*a+255*(255-a)+127)/255;
    if(rgb!=={8'(r),8'(g),8'(b)})$fatal(1,"ERROR fade pixel x=%0d y=%0d alpha=%0d got=%h expected=%h",col,row,a,rgb,{8'(r),8'(g),8'(b)});
    photo_checks=photo_checks+1;
   end else if(col<440 || row<144)begin
    if(rgb!==old_delay)$fatal(1,"ERROR clinic/subtitle pixels changed x=%0d y=%0d",col,row);
    protected_checks=protected_checks+1;
   end
   $fwrite(fd,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);written=written+1;
  end
 end
 task render(input integer image,input integer level,input bit welcome);
  integer xx,yy;
  begin
   de=0;picture=image;opacity=level;welcome_mode=welcome;
   @(negedge clk);frame=1;@(negedge clk);frame=0;
   repeat(5)@(negedge clk);
   fd=$fopen($sformatf("media_%0d_%02d.ppm",image,level),"wb");
   if(fd==0)$fatal(1,"ERROR cannot open RTL pixel capture");
   $fwrite(fd,"P6\n640 480\n255\n");written=0;active=1;
   for(yy=0;yy<480;yy=yy+1)for(xx=0;xx<640;xx=xx+1)begin
    @(negedge clk);x=xx;y=yy;de=1;
   end
   @(negedge clk);de=0;repeat(5)@(negedge clk);
   if(written!=307200)$fatal(1,"ERROR frame size got=%0d",written);
   active=0;$fclose(fd);fd=0;
  end
 endtask
 integer level;
 initial begin
  $readmemh("medq_media_rgb0.hex",pictures,0,307199);
  $readmemh("medq_media_rgb1.hex",pictures,307200,614399);
  $readmemh("medq_media_rgb2.hex",pictures,614400,921599);
  parameters[7:0]=128;parameters[15:8]=128;parameters[40]=1;
  // C01 / D01 actual calling states, both rooms enabled, independent captions.
  q[7:0]=1;q[39:32]=1;q[19:18]=1;q[51:50]=1;q[22]=1;q[54]=1;q[67:64]=15;
  repeat(8)@(negedge clk);rst=1;
  render(0,64,1);
  for(level=0;level<=64;level=level+8)render(1,level,0);
  for(level=0;level<=64;level=level+8)render(2,level,0);
  if(cover_checks!=307200 || photo_checks!=350208 || protected_checks!=4320000)$fatal(1,"ERROR pixel coverage totals cover=%0d photo=%0d protected=%0d",cover_checks,photo_checks,protected_checks);
  $display("PASS actual RTL media pixels: exact 307200-pixel cover, 350208 independently blended photo pixels at 18 endpoints/intermediates, unchanged clinic/subtitle pixels=%0d; 19 full 640x480 captures",protected_checks);$finish;
 end
 initial begin #100000000;$fatal(1,"TIMEOUT media pixels");end
endmodule

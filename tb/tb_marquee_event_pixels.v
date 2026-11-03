`timescale 1ns/1ps
module tb_marquee_event_pixels;
 reg clk=0;always #20 clk=~clk;
 reg rst=0,fs=0;reg [9:0] x=0,y=0;reg [127:0] q=0;
 wire [13:0] fa;wire [4:0] fc;wire [23:0] bg,fg;wire active;wire [7:0] opacity;
 medq_dual_ui_scene scene(.clk(clk),.rst_n(rst),.x(x),.y(y),.frame_start(fs),.qstate(q),.service_status(8'd1),
  .font_addr(fa),.font_column(fc),.background(bg),.foreground(fg),.text_active(active),.text_opacity(opacity));
 reg [31:0] rom[0:8191];reg [2:0] expected[0:138239];
 reg [9:0] widths[0:17];
 integer c,kind,room,shift,xx,yy,s,rx,checked=0,partials=0;reg ret;
 reg [2:0] want;reg [1:0] got;reg [23:0] color;
 initial begin $readmemh("font_v03.hex",rom);$readmemh("medq_event_reference.hex",expected);$readmemh("medq_event_widths.hex",widths);end
 task frame;begin @(negedge clk);fs=1;@(negedge clk);fs=0;end endtask
 initial begin
  repeat(5)@(negedge clk);rst=1;
  for(c=0;c<18;c=c+1)begin
   room=c/9;kind=c%9+1;ret=kind==2 || kind==4 || kind==5 || kind==8;
   q=0;q[65]=1;q[67:66]=3;q[64]=1;
   q[68+room*16+:16]={1'b1,kind[3:0],ret,8'h01,2'b00};frame;
   if((room ? scene.scroll_b : scene.scroll_a)!=(593+widths[c])/2)$fatal(1,"ERROR message not centered using independent raster width");
   for(shift=0;shift<5;shift=shift+1)begin
    if(shift!=0)repeat(600)frame;
    s=(((593+widths[c])/2)+shift*300)%592;
    if((room ? scene.scroll_b : scene.scroll_a)!=s)$fatal(1,"ERROR event ring phase");
    for(yy=0;yy<20;yy=yy+1)for(xx=24;xx<616;xx=xx+1)begin
     @(negedge clk);x=xx;y=(room ? 111 : 77)+yy;#1;
     rx=(xx-24+s)%592;want=0;if(rx<384)want=expected[c*7680+yy*384+rx];
     if(active && (fa<3584 || fa>=11776 || fc>15))$fatal(1,"ERROR two-page font address");
     got=active ? rom[fa-3584][31-2*fc-:2] : 0;
     color=want[2] ? (room ? 24'h2f6db5 : 24'h078a86) : 24'h17324a;
     if(got!==want[1:0] || (got!=0 && fg!==color))
      $fatal(1,"ERROR event text c=%0d kind=%0d shift=%0d x=%0d y=%0d cov=%d/%d",c,kind,shift,xx,yy,got,want[1:0]);
     if(opacity!=255)$fatal(1,"ERROR event ring seam faded");
     if(got==1 || got==2)partials=partials+1;
     checked=checked+1;
    end
   end
  end
  if(checked!=1065600 || partials<1000)$fatal(1,"ERROR incomplete event pixel coverage");
  $display("PASS %0d independent exact event pixels: 18 A/B operation messages, allocated/previous ticket identity, ordinary/return, masked names, centered refresh, five ring positions and original two-bit AA",checked);$finish;
 end
 initial begin #100000000;$fatal(1,"TIMEOUT event pixels");end
endmodule

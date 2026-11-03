`timescale 1ns/1ps
module tb_marquee_name;
 reg clk=0;always #20 clk=~clk;
 reg rst=0,fs=0;reg [9:0] x=0,y=0;reg [127:0] q=0;
 wire [13:0] fa;wire [4:0] fc;wire [23:0] bg,fg;wire active;wire [7:0] opacity;
 medq_dual_ui_scene scene(.clk(clk),.rst_n(rst),.x(x),.y(y),.frame_start(fs),.qstate(q),.service_status(8'd1),
  .font_addr(fa),.font_column(fc),.background(bg),.foreground(fg),.text_active(active),.text_opacity(opacity));
 reg [31:0] rom[0:8191];reg [2:0] expected[0:261119];
 reg [9:0] widths[0:33];
 integer c,shift,xx,yy,offset,s,reference_x,n,checked=0,stars=0;
 reg [2:0] want;reg [1:0] got;reg [23:0] color;
 initial begin $readmemh("font_v03.hex",rom);$readmemh("medq_marquee_reference.hex",expected);$readmemh("medq_marquee_widths.hex",widths);end
 task frame;begin @(negedge clk);fs=1;@(negedge clk);fs=0;end endtask
 initial begin
  repeat(5)@(negedge clk);rst=1;
  for(c=0;c<34;c=c+1)begin
   q=0;q[65]=1;q[67:66]=c[1:0];q[64]=|c[1:0];
   case(c)
    0:begin offset=0;q[0+:8]=8'h01;q[22]=1'b0;end
    1:begin offset=32;q[32+:8]=8'h09;q[54]=1'b0;end
    2:begin offset=0;q[0+:8]=8'h10;q[22]=1'b1;end
    3:begin offset=32;q[32+:8]=8'h99;q[54]=1'b1;end
    4:begin offset=0;q[0+:8]=8'h01;q[22]=1'b1;end
    5:begin offset=0;q[0+:8]=8'h02;q[22]=1'b1;end
    6:begin offset=0;q[0+:8]=8'h03;q[22]=1'b1;end
    7:begin offset=0;q[0+:8]=8'h04;q[22]=1'b1;end
    8:begin offset=0;q[0+:8]=8'h05;q[22]=1'b1;end
    9:begin offset=0;q[0+:8]=8'h01;q[22]=1'b0;end
    10:begin offset=0;q[0+:8]=8'h02;q[22]=1'b0;end
    11:begin offset=0;q[0+:8]=8'h03;q[22]=1'b0;end
    12:begin offset=0;q[0+:8]=8'h04;q[22]=1'b0;end
    13:begin offset=0;q[0+:8]=8'h05;q[22]=1'b0;end
    14:begin offset=0;q[0+:8]=8'h06;q[22]=1'b0;end
    15:begin offset=0;q[0+:8]=8'h07;q[22]=1'b0;end
    16:begin offset=0;q[0+:8]=8'h08;q[22]=1'b0;end
    17:begin offset=0;q[0+:8]=8'h09;q[22]=1'b0;end
    18:begin offset=0;q[0+:8]=8'h10;q[22]=1'b0;end
    19:begin offset=32;q[32+:8]=8'h01;q[54]=1'b1;end
    20:begin offset=32;q[32+:8]=8'h02;q[54]=1'b1;end
    21:begin offset=32;q[32+:8]=8'h03;q[54]=1'b1;end
    22:begin offset=32;q[32+:8]=8'h04;q[54]=1'b1;end
    23:begin offset=32;q[32+:8]=8'h05;q[54]=1'b1;end
    24:begin offset=32;q[32+:8]=8'h01;q[54]=1'b0;end
    25:begin offset=32;q[32+:8]=8'h02;q[54]=1'b0;end
    26:begin offset=32;q[32+:8]=8'h03;q[54]=1'b0;end
    27:begin offset=32;q[32+:8]=8'h04;q[54]=1'b0;end
    28:begin offset=32;q[32+:8]=8'h05;q[54]=1'b0;end
    29:begin offset=32;q[32+:8]=8'h06;q[54]=1'b0;end
    30:begin offset=32;q[32+:8]=8'h07;q[54]=1'b0;end
    31:begin offset=32;q[32+:8]=8'h08;q[54]=1'b0;end
    32:begin offset=32;q[32+:8]=8'h09;q[54]=1'b0;end
    33:begin offset=32;q[32+:8]=8'h10;q[54]=1'b0;end
    default:$fatal(1,"ERROR case index");
   endcase
   q[offset+18+:2]=1;q[offset+20+:2]=1;frame;
   for(shift=0;shift<5;shift=shift+1)begin
    if(shift!=0)repeat(600)frame;
    s=(((593+widths[c])/2)+shift*300)%592;
    if((offset!=0 ? scene.scroll_b : scene.scroll_a)!=s)$fatal(1,"ERROR independent centered name width/phase c=%0d",c);
    for(yy=0;yy<20;yy=yy+1)for(xx=24;xx<616;xx=xx+1)begin
     @(negedge clk);x=xx;y=(offset!=0 ? 111 : 77)+yy;#1;
     reference_x=(xx-24+s)%592;want=0;
     if(reference_x>=0 && reference_x<384)want=expected[c*7680+yy*384+reference_x];
     got=active ? rom[(fa-3584)&8191][31-2*fc-:2] : 0;
     color=want[2] ? (offset!=0 ? 24'h2f6db5 : 24'h078a86) : 24'h17324a;
     if(got!==want[1:0] || (got!=0 && fg!==color))
      $fatal(1,"ERROR exact surname subtitle c=%0d shift=%0d x=%0d y=%0d coverage=%0d/%0d fg=%h/%h",c,shift,xx,yy,got,want[1:0],fg,color);
     if(opacity!=255)$fatal(1,"ERROR ring seam loses coverage through edge fade");
     if(bg!==(offset!=0 ? 24'hecf1fa : 24'he8f5f4))$fatal(1,"ERROR subtitle background");
     if(got==1 || got==2)stars=stars+1;
     checked=checked+1;
    end
   end
  end
  if(checked!=2012800 || stars<100)$fatal(1,"ERROR incomplete subtitle coverage");
  $display("PASS %0d independent subtitle pixels: all 30 masked patients plus A01/B09/C10/D99 boundaries, actual-width centering, correct A/B room, all four enable masks, five toroidal scroll positions, preserved two-bit anti-aliasing",checked);$finish;
 end
 initial begin #150000000;$fatal(1,"TIMEOUT exact subtitle oracle");end
endmodule

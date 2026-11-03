`timescale 1ns/1ps
// Independent raster plus conserved one-pixel shift across every ring position.
// No deposits into the DUT; advance only public frame_start and room events.
module tb_marquee_seamless;
 reg clk=0;always #20 clk=~clk;
 reg rst=0,fs=0;reg [9:0] x=0,y=0;reg [127:0] q=0;
 wire [13:0] addr;wire [4:0] column;wire [23:0] bg,fg;
 wire active;wire [7:0] opacity;
 medq_dual_ui_scene scene(.clk(clk),.rst_n(rst),.x(x),.y(y),.frame_start(fs),.qstate(q),.service_status(8'd1),
  .font_addr(addr),.font_column(column),.background(bg),.foreground(fg),.text_active(active),.text_opacity(opacity));
 reg [31:0] rom[0:8191];reg [2:0] reference[0:261119],previous[0:23679],first[0:23679];
 reg [9:0] widths[0:33];reg [2:0] got,want;reg [1:0] cov;
 reg [23:0] color,rgb;reg [9:0] saved_b;reg saved_phase;
 integer step,room,xx,yy,case_id,phase,rx,index,next_index,ink,checked=0,seams=0,out=0,captures=0;
 initial begin
  $readmemh("font_v03.hex",rom);$readmemh("medq_marquee_reference.hex",reference);$readmemh("medq_marquee_widths.hex",widths);
 end
 task frame;begin @(negedge clk);fs=1;@(negedge clk);fs=0;end endtask
 function [23:0] blend;
  input [23:0] a,b;input [1:0] coverage;integer channel;
  begin
   for(channel=0;channel<3;channel=channel+1)
    blend[channel*8+:8]=(a[channel*8+:8]*(3-coverage)+b[channel*8+:8]*coverage+1)/3;
  end
 endfunction
 initial begin
  repeat(5)@(negedge clk);rst=1;q[65]=1;
  q[83:68]={1'b1,4'd3,1'b1,8'h01,2'b00};
  q[99:84]={1'b1,4'd3,1'b1,8'h01,2'b00};frame;
  for(step=0;step<=592;step=step+1)begin
   if(step!=0)begin frame;frame;end
   if(step%16==0 || step==592)begin
    out=$fopen($sformatf("seamless_%03d.ppm",step),"wb");
    if(out==0)$fatal(1,"ERROR seamless capture open");
    $fwrite(out,"P6\n592 40\n255\n");captures=captures+1;
   end
   for(room=0;room<2;room=room+1)begin
    case_id=room ? 19 : 4;phase=((593+widths[case_id])/2+step)%592;ink=0;
    if((room ? scene.scroll_b : scene.scroll_a)!=phase)$fatal(1,"ERROR ring position step=%0d room=%0d",step,room);
    for(yy=0;yy<20;yy=yy+1)for(xx=0;xx<592;xx=xx+1)begin
     @(negedge clk);x=xx+24;y=(room ? 111 : 77)+yy;#1;
     if(opacity!==255 || (active && (addr<3584 || addr>=11776 || column>15)))$fatal(1,"ERROR ring opacity or ROM range");
     cov=active ? rom[addr-3584][31-2*column-:2] : 0;
     color=room ? 24'h2f6db5 : 24'h078a86;
     got={cov!=0 && fg==color,cov};rx=(xx+phase)%592;want=0;
     if(rx<384)want=reference[case_id*7680+yy*384+rx];
     if(got!==want || (cov!=0 && fg!==color && fg!==24'h17324a))
      $fatal(1,"ERROR independent full-ring raster room=%0d step=%0d x=%0d y=%0d got=%h want=%h",room,step,xx,yy,got,want);
     index=room*11840+yy*592+xx;next_index=room*11840+yy*592+(xx+1)%592;
     // Previous rows are retained until their final pixel; last-pixel checks
     // use the separately saved old first pixel, not an overwritten entry.
     if(step==0)first[index]=got;
     else if(xx<591 && got!==previous[next_index])$fatal(1,"ERROR non-conservative left shift");
     else if(xx==591)begin
      if(got!==previous[room*11840+yy*592])$fatal(1,"ERROR left edge did not immediately re-enter right edge");
      seams=seams+1;
     end
     if(step==592 && got!==first[index])$fatal(1,"ERROR full revolution did not return identical pixels");
     if(cov!=0)ink=ink+1;
     if(out!=0)begin rgb=blend(bg,fg,cov);$fwrite(out,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);end
     checked=checked+1;
    end
    if(ink==0)$fatal(1,"ERROR blank interval during continuous ring");
   end
   if(out!=0)begin $fclose(out);out=0;end
   // Retain this exact independent raster as the predecessor for the next step.
   for(room=0;room<2;room=room+1)begin
    case_id=room ? 19 : 4;phase=((593+widths[case_id])/2+step)%592;
    for(yy=0;yy<20;yy=yy+1)for(xx=0;xx<592;xx=xx+1)begin
     rx=(xx+phase)%592;previous[room*11840+yy*592+xx]=rx<384 ? reference[case_id*7680+yy*384+rx] : 0;
    end
   end
  end
  // An A-only event immediately before a frame centers A while B keeps its phase.
  saved_b=scene.scroll_b;saved_phase=scene.scroll_phase[1];
  @(negedge clk);q[83]=!q[83];fs=1;@(posedge clk);#1;
  if(scene.scroll_a!=(593+widths[4])/2 || scene.scroll_phase[0]!=0)$fatal(1,"ERROR same-message A refresh not centered");
  if(scene.scroll_b!=(saved_b+(saved_phase ? 1 : 0))%592)$fatal(1,"ERROR A refresh reset B");
  @(negedge clk);fs=0;
  if(checked!=14042240 || seams!=23680 || captures!=38)$fatal(1,"ERROR incomplete seamless coverage %0d %0d %0d",checked,seams,captures);
  $display("PASS %0d exact independent raster checks, all 592 positions in both paused rooms, %0d immediate left-to-right seam exchanges, zero blank intervals, full-revolution identity, centered A refresh with B phase retained; %0d native-size RTL strip PPMs",checked,seams,captures);$finish;
 end
 initial begin #650000000;$fatal(1,"TIMEOUT continuous marquee");end
endmodule

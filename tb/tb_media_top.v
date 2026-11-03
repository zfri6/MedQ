`timescale 1ns/1ps
// End-to-end production media profile. Board pins only; fade/hold defaults
// remain untouched. Capture stops after the first male portrait has faded in.
// The independent controller and pixel tests cover the complete two-way cycle.
module tb_media_top;
 reg clk=0;always #10 clk=~clk;
 reg [3:0] key=15,sw=12;
 wire tx,sclk,mosi,miso,cs,hc,h0,h1,h2,buzz;wire [3:0] leds;wire [7:0] seg,sel;
 top #(.SD_INIT_DIV(0),.SD_DATA_DIV(0),.SD_RESPONSE_LIMIT(8),.INPUT_DEBOUNCE_CYCLES(4),.INPUT_INIT_CYCLES(5)) dut(
 .clk50mhz(clk),.KEY(key),.SW(sw),.LED(leds),.SEG_DATA(seg),.SEG_SEL(sel),.BUZZER(buzz),.UART_RX(1'b1),.UART_TX(tx),
 .SD_SCLK(sclk),.SD_MOSI(mosi),.SD_MISO(miso),.SD_nCS(cs),.HDMI_CLK_P(hc),.HDMI_D0_P(h0),.HDMI_D1_P(h1),.HDMI_D2_P(h2));
 sd_card_model #(.IMAGE_FILE("medq_media_sd.hex"),.DISK_SECTORS(6144)) card(.sclk(sclk),.mosi(mosi),.miso(miso),.cs_n(cs));
`ifdef MEDQ_REAL_SDRAM
 wire [31:0] device_errors,refreshes;
 medq_sdram_device_model physical(.clk(dut.u_sdram_ctrl_wrap.u_hardware.sdram_clk),.rst_n(dut.rst_n_mem),.initialized(dut.sdram_init_done),
  .ras_n(dut.u_sdram_ctrl_wrap.u_hardware.ras_n),.cas_n(dut.u_sdram_ctrl_wrap.u_hardware.cas_n),
  .we_n(dut.u_sdram_ctrl_wrap.u_hardware.we_n),.addr(dut.u_sdram_ctrl_wrap.u_hardware.phy_addr),
  .ba(dut.u_sdram_ctrl_wrap.u_hardware.bank),.dm(dut.u_sdram_ctrl_wrap.u_hardware.mask),
  .dq(dut.u_sdram_ctrl_wrap.u_hardware.dq),.errors(device_errors),.refresh_count(refreshes));
`endif
 reg [23:0] cover_reference[0:307199],male_reference[0:307199];
 integer phase=0,capturing=0,written=0,fd=0,captures=0,checked=0,male_checked=0;
 integer calls=0,pcm=0,frames=0,audible=0;
 reg cover_captured=0,male_captured=0,previous_de=0;
 reg [6:0] captured_alpha;
 integer xx,yy,aa,r,g,b,p;
 always @(posedge dut.clk_pix)if(dut.rst_n_pix)begin
  if(dut.call_pulse_pix)calls=calls+1;
  if(dut.play_req)pcm=pcm+1;
  if(dut.aud_stb && dut.aud_l!=0)audible=audible+1;
  if(!dut.clinic_enable && (dut.key_press!=0 || dut.doctor_event!=0 || calls!=0 || dut.running!=0))$fatal(1,"ERROR media cover leaked controls");
  if(dut.frame_data_enabled && (dut.disp_underrun || dut.pcm_underrun))$fatal(1,"ERROR media top underrun");
  if(dut.co_de && (^dut.co_rgb)===1'bx)$fatal(1,"ERROR unknown media output");
  if(dut.vt_frame_start)begin
   frames=frames+1;
   if(!cover_captured && dut.media_show && !dut.clinic_visible)phase=1;
   if(cover_captured && !male_captured && dut.clinic_visible && dut.photo_alpha==64)phase=2;
  end
  if(!capturing && phase!=0 && dut.co_de && !previous_de)begin
   capturing=phase;phase=0;written=0;captured_alpha=dut.photo_alpha;
   fd=$fopen(capturing==1 ? "media_top_cover.ppm" : "media_top_clinic.ppm","wb");
   $fwrite(fd,"P6\n640 480\n255\n");
  end
  if(capturing && dut.co_de)begin
   xx=written%640;yy=written/640;
   if(capturing==1)begin
    if(dut.co_rgb!==cover_reference[written])$fatal(1,"ERROR actual SD cover mismatch at %0d,%0d got=%h expected=%h",xx,yy,dut.co_rgb,cover_reference[written]);
    checked=checked+1;
   end else if(xx>=456 && xx<608 && yy>=298 && yy<426)begin
    if(dut.co_rgb!==male_reference[written])$fatal(1,"ERROR actual SDRAM portrait mismatch x=%0d y=%0d got=%h expected=%h base=%h",xx,yy,dut.co_rgb,male_reference[written],dut.u_frame_reader_main.base);
    male_checked=male_checked+1;
   end
   $fwrite(fd,"%c%c%c",dut.co_rgb[23:16],dut.co_rgb[15:8],dut.co_rgb[7:0]);written=written+1;
   if(written==307200)begin
    $fclose(fd);fd=0;captures=captures+1;
    if(capturing==1)cover_captured=1;else male_captured=1;
    capturing=0;
   end
  end
  previous_de=dut.co_de;
 end
 task press(input [3:0] mask);begin @(negedge dut.clk_pix);key=~mask;repeat(30)@(negedge dut.clk_pix);key=15;repeat(30)@(negedge dut.clk_pix);end endtask
 initial begin
  $readmemh("medq_media_rgb0.hex",cover_reference);
  $readmemh("medq_media_rgb1.hex",male_reference);
  wait(dut.rst_n_pix);
  // Doctor switches can move on cover without creating clinic events.
  repeat(1000)@(negedge dut.clk_pix);sw[3:2]=0;repeat(1000)@(negedge dut.clk_pix);sw[3:2]=3;
  wait(cover_captured);
  if(calls!=0 || dut.qstate_pix[63:0]!=0 || dut.assets_ok)$fatal(1,"ERROR cover was not available before PCM/portrait preload finished");
  press(4);wait(dut.inputs_ready);
  if(dut.qstate_service[63:0]!=0 || calls!=0)$fatal(1,"ERROR entering with return key enqueued patient");
  wait(dut.assets_ok && dut.service_status_pix[1:0]==1);
  if(dut.media_valid_sys!=7 || dut.img_count!=3 || dut.pcm_count!=54)$fatal(1,"ERROR media top load inventory");
  press(15);wait(calls==2);wait(pcm==18);wait(!dut.u_dual_announcer.announcing && !dut.play_busy);repeat(4)@(negedge dut.clk_pix);
  if(pcm!=18 || audible==0 || dut.qstate_pix[7:0]!=1 || dut.qstate_pix[39:32]!=1 || !dut.qstate_pix[22] || !dut.qstate_pix[54])$fatal(1,"ERROR media interfered with both rooms/PCM clips=%0d audible=%0d state=%h",pcm,audible,dut.qstate_pix);
  wait(male_captured);
  if(checked!=307200 || male_checked!=19456 || captures!=2 || frames<60)$fatal(1,"ERROR media top coverage");
`ifdef MEDQ_REAL_SDRAM
  if(device_errors!=0 || refreshes<1000 || dut.memory_fault)$fatal(1,"ERROR physical media SDRAM");
  $display("CHECK media top original SDRAM controller physical refreshes=%0d",refreshes);
`endif
  $display("PASS actual board-pin SD media system: early exact cover (307200 pixels), consumed return-entry key, independent switch baseline, all native BMP/54 PCM preload, simultaneous two-room admission/18 clips, exact settled portrait (19456 pixels), default smooth fade, no display/audio underrun; frames=%0d sectors=%0d",frames,card.read_count);$finish;
 end
 initial begin #2500000000;$fatal(1,"TIMEOUT media top loader=%0d media=%b page=%b alpha=%0d calls=%0d",dut.u_asset_loader.state,dut.media_valid_sys,dut.clinic_visible,dut.photo_alpha,calls);end
endmodule

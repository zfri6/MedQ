`timescale 1ns/1ps
module tb_v03_top_audio;
 reg clk=0;always #10 clk=~clk;
 reg [3:0] key=15,sw=12;
 wire tx,sclk,mosi,miso,cs,hc,h0,h1,h2,buzz;wire [3:0] leds;wire [7:0] seg,sel;
 top #(.SD_INIT_DIV(0),.SD_DATA_DIV(0),.SD_RESPONSE_LIMIT(8),.INPUT_DEBOUNCE_CYCLES(4),.INPUT_INIT_CYCLES(5)) dut(
 .clk50mhz(clk),.KEY(key),.SW(sw),.LED(leds),.SEG_DATA(seg),.SEG_SEL(sel),.BUZZER(buzz),.UART_RX(1'b1),.UART_TX(tx),
 .SD_SCLK(sclk),.SD_MOSI(mosi),.SD_MISO(miso),.SD_nCS(cs),.HDMI_CLK_P(hc),.HDMI_D0_P(h0),.HDMI_D1_P(h1),.HDMI_D2_P(h2));
 sd_card_model #(.IMAGE_FILE("medq_v03_long.hex")) card(.sclk(sclk),.mosi(mosi),.miso(miso),.cs_n(cs));
`ifdef MEDQ_REAL_SDRAM
    wire [31:0] device_errors,physical_refreshes;
    medq_sdram_device_model physical_memory(
      .clk(dut.u_sdram_ctrl_wrap.u_hardware.sdram_clk),.rst_n(dut.rst_n_mem),.initialized(dut.sdram_init_done),
      .ras_n(dut.u_sdram_ctrl_wrap.u_hardware.ras_n),.cas_n(dut.u_sdram_ctrl_wrap.u_hardware.cas_n),
      .we_n(dut.u_sdram_ctrl_wrap.u_hardware.we_n),.addr(dut.u_sdram_ctrl_wrap.u_hardware.phy_addr),
      .ba(dut.u_sdram_ctrl_wrap.u_hardware.bank),.dm(dut.u_sdram_ctrl_wrap.u_hardware.mask),
      .dq(dut.u_sdram_ctrl_wrap.u_hardware.dq),.errors(device_errors),.refresh_count(physical_refreshes));
    always @(posedge dut.clk_pix)if(dut.rst_n_pix && dut.co_de && (^dut.co_rgb===1'bx))
      $fatal(1,"ERROR first unknown active RGB base=%h rgb_trans=%h osd=%h/%h spec=%h/%h mem_init=%b",dut.rgb_cur,dut.rgb_trans,dut.osd_rgb,dut.osd_alpha,dut.spec_rgb,dut.spec_alpha,dut.sdram_init_done);
    always @(posedge dut.clk_mem)if(dut.rst_n_mem && dut.u_sdram_ctrl_wrap.u_hardware.core_valid && (^dut.u_sdram_ctrl_wrap.u_hardware.core_data===1'bx))
      $fatal(1,"ERROR unknown physical read data address=%h beat=%0d",dut.u_sdram_ctrl_wrap.u_hardware.base,dut.u_sdram_ctrl_wrap.u_hardware.received);
`endif
 integer starts_a=0,starts_b=0,b_clips=0,aborts=0,phase_hold,fetched_hold,left_hold;
 reg [63:0] queue_hold;
 always @(posedge dut.clk_pix)if(dut.rst_n_pix)begin
  if(dut.call_grant[0])starts_a=starts_a+1;
  if(dut.call_grant[1])starts_b=starts_b+1;
  if(dut.play_req && ((|dut.call_grant) ? dut.call_grant[1] : dut.u_dual_announcer.active_room))b_clips=b_clips+1;
  if(dut.pcm_abort)aborts=aborts+1;
  if(dut.disp_underrun || dut.pcm_underrun)$fatal(1,"ERROR actual top audio/display underrun");
 end
 task press(input [3:0] mask);begin @(negedge dut.clk_pix);key=~mask;repeat(30)@(negedge dut.clk_pix);key=15;repeat(30)@(negedge dut.clk_pix);end endtask
 task doctor_a;begin @(negedge dut.clk_pix);sw[2]=!sw[2];repeat(30)@(negedge dut.clk_pix);end endtask
 task doctor_b;begin @(negedge dut.clk_pix);sw[3]=!sw[3];repeat(30)@(negedge dut.clk_pix);end endtask
 initial begin
  wait(dut.rst_n_pix && dut.u_media_control.released);press(8);wait(dut.clinic_enable);
  if(starts_a!=0 || starts_b!=0 || dut.qstate_service[63:0]!=0)$fatal(1,"ERROR cover entry leaked audio/queue operation");
  wait(dut.inputs_ready && dut.service_status_pix[1:0]==1);
  press(3);wait(dut.play_busy && dut.u_audio_pcm_player.play_started);press(1);
  sw[0]=1;wait(dut.running==2);repeat(10)@(negedge dut.clk_pix);
  left_hold=dut.u_dual_service.a.elapsed;queue_hold=dut.qstate_pix[63:0];
  press(4);wait(starts_b==1 && dut.play_busy);repeat(3000)@(negedge dut.clk_pix);
  if(dut.u_dual_service.a.elapsed!=left_hold || dut.qstate_pix[17:13]!=queue_hold[17:13]+1 ||
     !dut.u_dual_announcer.replay[0] || starts_a!=1 || starts_b!=1 || !dut.u_dual_announcer.active_room || aborts==0)
     $fatal(1,"ERROR actual top A stop blocked B/current timer/enqueue");
  doctor_a;
  if(dut.qstate_pix[19:18]!=2 || dut.u_dual_announcer.replay[0] || !dut.u_dual_announcer.active_room || dut.pcm_abort)
    $fatal(1,"ERROR SW3 did not cancel paused A or cancelled active B");
  doctor_a;repeat(1000)@(negedge dut.clk_pix);
  if(starts_a!=1 || dut.qstate_pix[19:18]!=0)$fatal(1,"ERROR stopped A admitted new call");
  wait(!dut.u_dual_announcer.announcing && !dut.play_busy);
  if(b_clips!=9 || dut.qstate_pix[51:50]!=1)$fatal(1,"ERROR B speech did not complete while A stopped");
  $display("CHECK B full nine clips while A stopped t=%0t",$time);
  sw[1]=1;wait(dut.running==0);repeat(20)@(negedge dut.clk_pix);left_hold=dut.u_dual_service.b.elapsed;
  sw[0]=0;wait(dut.running==1);
  wait(starts_a==2);@(negedge dut.clk_pix);
  if(dut.qstate_pix[7:0]!=1 || !dut.qstate_pix[22] || dut.qstate_pix[12:8]!=1 || dut.qstate_pix[17:13]!=0 || b_clips!=9)
     $fatal(1,"ERROR actual top pending return priority/complete B voice bclips=%0d",b_clips);
  wait(!dut.u_dual_announcer.announcing && !dut.play_busy);
  $display("CHECK A full return speech while B stopped t=%0t",$time);
  if(dut.u_dual_service.b.elapsed!=left_hold || starts_b!=1)$fatal(1,"ERROR B stop advanced while A announced");
  doctor_b;if(dut.qstate_pix[51:50]!=2 || dut.qstate_pix[19:18]!=1)$fatal(1,"ERROR SW4 B arrival routing");
  doctor_b;if(dut.qstate_pix[51:50]!=0 || dut.u_dual_service.completed_b!=1)$fatal(1,"ERROR SW4 B departure while stopped");
`ifdef MEDQ_REAL_SDRAM
  if(device_errors!=0 || physical_refreshes<100 || dut.memory_fault)$fatal(1,"ERROR real controller audio physical checks");
  $display("CHECK actual encrypted SDRAM audio abort/pause, physical refreshes=%0d",physical_refreshes);
`endif
  $display("PASS V0.3 real pin audio: independent SW1 A/SW2 B calling, long PCM safe drain, B nine complete clips with A stopped and reverse timer isolation, live queues, SW3 A/SW4 B arrival/departure while stopped, return priority and no underruns");$finish;
 end
 // Two complete real-rate nine-clip sentences now run sequentially after
 // loading; the former 150ms test ended immediately after the second grant.
 initial begin #350000000;$fatal(1,"TIMEOUT V0.3 pin audio a=%0d b=%0d arb=%0d PCM=%0d left=%0d run=%b",starts_a,starts_b,dut.u_dual_announcer.state,dut.u_audio_pcm_player.state,dut.u_audio_pcm_player.sources_left,dut.running);end
endmodule

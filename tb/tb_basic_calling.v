`timescale 1ns/1ps
// No-card full top, inputs originate at physical KEY/SW pins.
module tb_basic_calling;
 reg clk=0;always #10 clk=~clk;
 reg [3:0] key=15,sw=12;
 wire tx,sclk,mosi,cs,hc,h0,h1,h2,buzz;wire [3:0] leds;wire [7:0] seg,sel;
 top #(.SD_INIT_DIV(0),.SD_DATA_DIV(0),.SD_RESPONSE_LIMIT(8),.SERVICE_STARTUP_CYCLES(4096),.FEEDBACK_CYCLES(50000),
 .INPUT_DEBOUNCE_CYCLES(4),.INPUT_INIT_CYCLES(5)) dut(
 .clk50mhz(clk),.KEY(key),.SW(sw),.LED(leds),.SEG_DATA(seg),.SEG_SEL(sel),.BUZZER(buzz),
 .UART_RX(1'b1),.UART_TX(tx),.SD_SCLK(sclk),.SD_MOSI(mosi),.SD_MISO(1'b1),.SD_nCS(cs),
 .HDMI_CLK_P(hc),.HDMI_D0_P(h0),.HDMI_D1_P(h1),.HDMI_D2_P(h2));
`ifdef MEDQ_REAL_SDRAM
 wire [31:0] device_errors,refreshes;
 medq_sdram_device_model physical(.clk(dut.u_sdram_ctrl_wrap.u_hardware.sdram_clk),.rst_n(dut.rst_n_mem),.initialized(dut.sdram_init_done),
  .ras_n(dut.u_sdram_ctrl_wrap.u_hardware.ras_n),.cas_n(dut.u_sdram_ctrl_wrap.u_hardware.cas_n),
  .we_n(dut.u_sdram_ctrl_wrap.u_hardware.we_n),.addr(dut.u_sdram_ctrl_wrap.u_hardware.phy_addr),
  .ba(dut.u_sdram_ctrl_wrap.u_hardware.bank),.dm(dut.u_sdram_ctrl_wrap.u_hardware.mask),
  .dq(dut.u_sdram_ctrl_wrap.u_hardware.dq),.errors(device_errors),.refresh_count(refreshes));
`endif
 integer starts=0,tones=0,pcm_starts=0,remaining;
 always @(posedge dut.clk_pix)begin
  if(dut.call_pulse_pix)starts=starts+1;
  if(dut.play_req)pcm_starts=pcm_starts+1;
  if(dut.aud_stb && dut.fallback_tone && dut.tone_sample!=0)tones=tones+1;
 end
 initial begin
  wait(dut.rst_n_pix && dut.u_media_control.released);
  key=7;repeat(30)@(negedge dut.clk_pix);key=15;
  wait(dut.clinic_enable);
  if(starts!=0 || dut.qstate_service[63:0]!=0)$fatal(1,"ERROR no-card cover entry leaked clinic operation");
  wait(dut.rst_n_pix && dut.inputs_ready && dut.service_status_pix[1:0]==2);
  repeat(10)@(negedge dut.clk_pix);
  if(dut.assets_ok)$fatal(1,"ERROR no-card loaded assets");
  key=12;repeat(30)@(negedge dut.clk_pix);key=15;
  wait(dut.fallback_tone);repeat(500)@(negedge dut.clk_pix);
  sw[1:0]=3;wait(dut.running==0);repeat(50)@(negedge dut.clk_pix);remaining=dut.u_dual_announcer.tone_left;
  repeat(4000)@(negedge dut.clk_pix);
  if(dut.u_dual_announcer.tone_left!=0 || !dut.u_dual_announcer.replay[0] || dut.aud_l!=0 || buzz || starts!=1)$fatal(1,"ERROR fallback pause");
  sw[1:0]=0;wait(dut.running==3);wait(starts==2);@(negedge dut.clk_pix);wait(!dut.u_dual_announcer.announcing && dut.u_dual_announcer.replay==0);
  repeat(3000)@(negedge dut.clk_pix);
  if(pcm_starts!=0 || tones==0 || dut.aud_l!=0 || starts!=2 || dut.qstate_pix[7:0]!=1 || dut.qstate_pix[39:32]!=1 ||
     dut.qstate_pix[19:18]!=1 || dut.qstate_pix[51:50]!=1)$fatal(1,"ERROR degraded coverage starts=%0d tones=%0d PCM=%0d q=%h",starts,tones,pcm_starts,dut.qstate_pix);
`ifdef MEDQ_REAL_SDRAM
  if(device_errors!=0 || refreshes<10 || dut.memory_fault)$fatal(1,"ERROR basic physical memory");
  $display("CHECK no-card real controller refreshes=%0d",refreshes);
`endif
  $display("PASS no-card board pins: A/B independent screen calls, fair finite tones, independent gates, stopped tone silence/drain/replay without extra grant, idle silence, zero PCM requests");$finish;
 end
 initial begin #40000000;$fatal(1,"TIMEOUT basic dual calling visible=%b enable=%b ready=%b starts=%0d tones=%0d run=%b phase=%0d replay=%b",dut.clinic_visible,dut.clinic_enable,dut.inputs_ready,starts,tones,dut.running,dut.u_dual_announcer.state,dut.u_dual_announcer.replay);end
endmodule

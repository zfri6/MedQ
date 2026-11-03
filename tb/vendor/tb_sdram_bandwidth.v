`timescale 1ns/1ps
// Actual encrypted controller + independent physical memory + display FIFO.
// Demand is an uninterrupted 640x480/25 MHz stream with normal VGA blanking.
module tb_sdram_bandwidth;
 reg clk_pix=0;
`ifdef MEDQ_VENDOR_PLL
 reg refclk=0;always #10 refclk=~refclk;
 reg pll_reset=1;initial begin #200;pll_reset=0;end
 wire clk_mem,clk_sdram,pll_locked;
 sys_pll clocks(.refclk(refclk),.reset(pll_reset),.extlock(pll_locked),.clk0_out(),.clk1_out(clk_mem),.clk2_out(clk_sdram));
`else
 reg clk_mem=0,clk_sdram=0;
 always #10 clk_mem=~clk_mem;
 initial begin #8;forever #10 clk_sdram=~clk_sdram;end
 wire pll_locked=1'b1;
`endif
 always #20 clk_pix=~clk_pix;
 reg rst_n=0,scan=0,filled=0;
 reg fill_req=0,fill_valid=0;
 reg [21:0] fill_address=0;
 reg [31:0] fill_data=0;
 reg aud_req=0,write_req=0,write_valid=0;
 reg [31:0] write_data=0;
 wire aud_ready,aud_valid,write_ready,write_beat_ready;
 wire [31:0] aud_data;
 wire m_req,m_ready,m_we,m_wvalid,m_wready,m_rvalid,m_rready;
 wire [21:0] m_address;wire [8:0] m_length;wire [31:0] m_wdata,m_rdata;
 wire req,ready,we,wvalid,wready,rvalid,rready,init_done,fault;
 wire [21:0] address;wire [8:0] length;
 wire [31:0] wdata,rdata;wire [23:0] rgb;wire underrun;
 integer x=0,y=0,frames=0,checks=0,beats=0,cycles=0,i,j;
 integer audio_bursts=0,writer_bursts=0,audio_words=0,writer_words=0,ai,wi;
 wire de=scan && x<640 && y<480;
 wire display_urgent;
 frame_reader reader(.clk_pix(clk_pix),.rst_n_pix(rst_n && filled),.clk_mem(clk_mem),.rst_n_mem(rst_n && filled),
  .fb_base(22'd0),.frame_start(scan && x==0 && y==0),.line_start(scan && x==0),.de(de),
  .px_rgb(rgb),.underrun(underrun),.primed(),.urgent(display_urgent),.disp_req_valid(req),.disp_req_ready(ready),
  .disp_req_addr(address),.disp_req_we(we),.disp_req_len(length),
  .disp_wr_valid(wvalid),.disp_wr_ready(wready),.disp_wr_data(wdata),
  .disp_rd_valid(rvalid),.disp_rd_ready(rready),.disp_rd_data(rdata));
 medq_sdram_adapter #(.MEM_CLK_HZ(50000000)) dut(.clk(clk_mem),.clk_sdram(clk_sdram),.rst_n(rst_n),
  .mem_req_valid(filled ? m_req : fill_req),.mem_req_ready(m_ready),
  .mem_req_addr(filled ? m_address : fill_address),.mem_req_we(filled ? m_we : 1'b1),.mem_req_len(filled ? m_length : 9'd256),
  .mem_wr_valid(filled ? m_wvalid : fill_valid),.mem_wr_ready(m_wready),.mem_wr_data(filled ? m_wdata : fill_data),
  .mem_rd_valid(m_rvalid),.mem_rd_ready(filled && m_rready),.mem_rd_data(m_rdata),.init_done(init_done),.fault(fault));
 sdram_arbiter arb(.clk(clk_mem),.rst_n(rst_n && filled),
  .aud_req_valid(aud_req),.aud_req_ready(aud_ready),.aud_req_addr(22'h0e1000),.aud_req_we(1'b0),.aud_req_len(9'd64),
  .aud_wr_valid(1'b0),.aud_wr_ready(),.aud_wr_data(32'd0),.aud_rd_valid(aud_valid),.aud_rd_ready(1'b1),.aud_rd_data(aud_data),
  .disp_req_valid(req),.disp_urgent(display_urgent),.disp_req_ready(ready),.disp_req_addr(address),.disp_req_we(we),.disp_req_len(length),
  .disp_wr_valid(wvalid),.disp_wr_ready(wready),.disp_wr_data(wdata),.disp_rd_valid(rvalid),.disp_rd_ready(rready),.disp_rd_data(rdata),
  .tr_req_valid(1'b0),.tr_req_ready(),.tr_req_addr(22'd0),.tr_req_we(1'b0),.tr_req_len(9'd0),
  .tr_wr_valid(1'b0),.tr_wr_ready(),.tr_wr_data(32'd0),.tr_rd_valid(),.tr_rd_ready(1'b0),.tr_rd_data(),
  .wr_req_valid(write_req),.wr_req_ready(write_ready),.wr_req_addr(22'h180000),.wr_req_we(1'b1),.wr_req_len(9'd64),
  .wr_wr_valid(write_valid),.wr_wr_ready(write_beat_ready),.wr_wr_data(write_data),.wr_rd_valid(),.wr_rd_ready(1'b0),.wr_rd_data(),
  .mem_req_valid(m_req),.mem_req_ready(m_ready),.mem_req_addr(m_address),.mem_req_we(m_we),.mem_req_len(m_length),
  .mem_wr_valid(m_wvalid),.mem_wr_ready(m_wready),.mem_wr_data(m_wdata),.mem_rd_valid(m_rvalid),.mem_rd_ready(m_rready),.mem_rd_data(m_rdata));
 wire [31:0] model_errors,refresh_count;
 medq_sdram_device_model memory(.clk(dut.sdram_clk),.rst_n(rst_n),.initialized(init_done),
  .ras_n(dut.ras_n),.cas_n(dut.cas_n),.we_n(dut.we_n),.addr(dut.phy_addr),
  .ba(dut.bank),.dm(dut.mask),.dq(dut.dq),.refresh_count(refresh_count),.errors(model_errors));
 always @(posedge clk_mem)if(scan)begin
  cycles=cycles+1;if(rvalid && rready)beats=beats+1;
  if(fault || model_errors!=0)$fatal(1,"FAIL memory fault/model errors");
 end
 reg active;integer expected;
 always @(posedge clk_pix)if(scan)begin
  active=de;expected=y*640+x;
  #1;
  if(active)begin
   if(underrun || rgb!==expected[23:0])
    $fatal(1,"FAIL scan frame=%0d x=%0d y=%0d rgb=%h expected=%h underrun=%b beats=%0d cycles=%0d",frames,x,y,rgb,expected[23:0],underrun,beats,cycles);
   checks=checks+1;
  end
  if(x==799)begin
   x=0;
   if(y==524)begin
    y=0;frames=frames+1;
    if(frames==2)begin
     if(audio_bursts<30 || writer_bursts<250)$fatal(1,"FAIL insufficient contention coverage");
     $display("CHECK 50MHz memory/25MHz video: frames=%0d pixels=%0d beats=%0d cycles=%0d refresh=%0d",frames,checks,beats,cycles,refresh_count);
     $display("CHECK concurrent audio words=%0d writer words=%0d audio bursts=%0d writer bursts=%0d",audio_words,writer_words,audio_bursts,writer_bursts);
     $display("PASS tb_sdram_bandwidth");$finish;
    end
   end else y=y+1;
  end else x=x+1;
 end
 initial begin
  wait(pll_locked);repeat(10)@(negedge clk_mem);rst_n=1;
  wait(init_done);
  // Populate through the public interface; do not assume the encrypted core's
  // logical-to-physical bank/column mapping when constructing expected pixels.
  for(i=0;i<307200;i=i+256)begin
   @(negedge clk_mem);fill_address=i;fill_req=1;
   @(posedge clk_mem);while(!m_ready)@(posedge clk_mem);
   @(negedge clk_mem);fill_req=0;
   for(j=0;j<256;j=j+1)begin
    fill_valid=1;fill_data=i+j;
    @(posedge clk_mem);while(!m_wready)@(posedge clk_mem);
    @(negedge clk_mem);fill_valid=0;
   end
  end
  wait(dut.state==0);@(negedge clk_mem);filled=1;
  wait(reader.wlevel>=1792);
  @(negedge clk_pix);scan=1;
 end
 // Four times the real PCM word rate and a continually backlogged image writer.
 initial begin
  wait(scan);
  forever begin
   #640000;@(negedge clk_mem);aud_req=1;
   @(posedge clk_mem);while(!aud_ready)@(posedge clk_mem);
   @(negedge clk_mem);aud_req=0;
   for(ai=0;ai<64;ai=ai+1)begin
    @(posedge clk_mem);while(!aud_valid)@(posedge clk_mem);
    if(aud_data!==0)$fatal(1,"FAIL concurrent audio data");
    audio_words=audio_words+1;
   end
   audio_bursts=audio_bursts+1;
  end
 end
 initial begin
  wait(scan);
  forever begin
   #500;@(negedge clk_mem);write_req=1;
   @(posedge clk_mem);while(!write_ready)@(posedge clk_mem);
   @(negedge clk_mem);write_req=0;
   for(wi=0;wi<64;wi=wi+1)begin
    write_valid=1;write_data=32'hf0000000+wi;
    @(posedge clk_mem);while(!write_beat_ready)@(posedge clk_mem);
    writer_words=writer_words+1;
    @(negedge clk_mem);write_valid=0;
   end
   writer_bursts=writer_bursts+1;
  end
 end
 initial begin #200000000;$fatal(1,"TIMEOUT SDRAM display bandwidth");end
endmodule

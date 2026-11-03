`timescale 1ns/1ps
module tb_sdram_hardware;
`ifdef MEDQ_VENDOR_PLL
 reg refclk=0;always #10 refclk=~refclk;
 reg pll_reset=1;initial begin #200;pll_reset=0;end
 wire clk,clk_sdram,pll_locked;
 sys_pll clocks(.refclk(refclk),.reset(pll_reset),.extlock(pll_locked),.clk0_out(),.clk1_out(clk),.clk2_out(clk_sdram));
`else
 reg clk=0;always #10 clk=~clk;
 reg clk_sdram=0;initial begin #8;forever #10 clk_sdram=~clk_sdram;end
 wire pll_locked=1'b1;
`endif
 reg rst_n=0,req=0,we=0,wvalid=0,rready=0;
 reg [21:0] addr=0;reg [8:0] len=0;reg [31:0] wdata=0;
 wire ready,wready,rvalid,init_done,fault;wire [31:0] rdata;
 integer checks=0,n,i,refs,seed=32'h1271abcd;
 reg [31:0] expected[0:2097151];reg [31:0] saved;
 medq_sdram_adapter dut(.clk(clk),.clk_sdram(clk_sdram),.rst_n(rst_n),
  .mem_req_valid(req),.mem_req_ready(ready),.mem_req_addr(addr),.mem_req_we(we),.mem_req_len(len),
  .mem_wr_valid(wvalid),.mem_wr_ready(wready),.mem_wr_data(wdata),
  .mem_rd_valid(rvalid),.mem_rd_ready(rready),.mem_rd_data(rdata),.init_done(init_done),.fault(fault));
 wire [31:0] model_errors;wire [31:0] refresh_count;
 medq_sdram_device_model memory(.clk(dut.sdram_clk),.rst_n(rst_n),.initialized(init_done),
  .ras_n(dut.ras_n),.cas_n(dut.cas_n),.we_n(dut.we_n),.addr(dut.phy_addr),
  .ba(dut.bank),.dm(dut.mask),.dq(dut.dq),.refresh_count(refresh_count),.errors(model_errors));
 task request;
  input integer a,l;input wr;
  begin
   @(negedge clk);addr=a;len=l;we=wr;req=1;
   @(posedge clk);while(!ready)@(posedge clk);
   @(negedge clk);req=0;
  end
 endtask
 task write_range;
  input integer a,l;
  integer j;
  begin
   request(a,l,1);
   for(j=0;j<l;j=j+1)begin
    if(j%7==3)repeat(3)@(negedge clk);
    seed=(seed<<1)^(seed[31]?32'h04c11db7:0);
    wdata=seed ^ (a+j);wvalid=1;expected[a+j]=wdata;
    @(posedge clk);while(!wready)@(posedge clk);
    @(negedge clk);wvalid=0;
   end
  end
 endtask
 task read_range;
  input integer a,l;
  integer j;
  begin
   request(a,l,0);
   for(j=0;j<l;j=j+1)begin
    rready=0;wait(rvalid);saved=rdata;
    repeat(j%5)begin
     @(posedge clk);#1;if(!rvalid || rdata!==saved)begin $display("FAIL stalled read changed");$finish;end
    end
    @(negedge clk);rready=1;
    @(posedge clk);
    if(!rvalid || rdata!==expected[a+j])begin
     $display("FAIL read addr=%0d expected=%h actual=%h received=%0d",a+j,expected[a+j],rdata,dut.received);$finish;
    end
    checks=checks+1;@(negedge clk);rready=0;
   end
  end
 endtask
 task reset_device;
  begin
   @(negedge clk);rst_n=0;req=0;wvalid=0;rready=0;
   wait(pll_locked);repeat(8)@(negedge clk);rst_n=1;wait(init_done);repeat(40)@(negedge clk);
  end
 endtask
 initial begin
  for(i=0;i<2097152;i=i+1)expected[i]=0;
  reset_device();
  write_range(0,256);read_range(0,256);
  write_range(1,1);write_range(3,3);write_range(255,255);read_range(0,256);read_range(256,256);
  write_range(1023,256);read_range(1020,256);read_range(1276,8);
  write_range(2096895,256);read_range(2096892,256);read_range(2097148,4);
  // Application stalls longer than one refresh interval, in both directions.
  request(8193,3,1);refs=refresh_count;repeat(6000)@(negedge clk);
  if(refresh_count<refs+2)begin $display("FAIL refresh while write stalled");$finish;end
  for(n=0;n<3;n=n+1)begin
   wvalid=1;wdata=32'hcafe0000+n;expected[8193+n]=wdata;
   @(posedge clk);while(!wready)@(posedge clk);@(negedge clk);wvalid=0;
  end
  request(8193,3,0);wait(rvalid);saved=rdata;refs=refresh_count;
  repeat(6000)begin @(negedge clk);if(rdata!==saved || !rvalid)begin $display("FAIL long read stall");$finish;end end
  if(refresh_count<refs+2)begin $display("FAIL refresh while read stalled");$finish;end
  for(n=0;n<3;n=n+1)begin
   rready=1;@(posedge clk);if(rdata!==expected[8193+n])begin $display("FAIL stalled burst data");$finish;end
   checks=checks+1;@(negedge clk);
  end
  rready=0;
  // Reset aborts a partly collected write and permits a fresh initialization.
  request(16000,8,1);wvalid=1;wdata=0;@(negedge clk);wvalid=0;reset_device();
  write_range(16381,13);read_range(16380,16);
  // Invalid descriptor is rejected, records a sticky fault, and can be reset.
  @(negedge clk);req=1;addr=2097151;len=2;we=0;
  @(posedge clk);if(ready)begin $display("FAIL accepted overflow");$finish;end
  @(negedge clk);req=0;if(!fault)begin $display("FAIL missing range fault");$finish;end
  if(model_errors!=0)begin $display("FAIL device model errors=%0d",model_errors);$finish;end
  $display("CHECK actual encrypted core, BL4/CL3 physical data, masks, boundaries, stalls, refresh, reset; words=%0d refresh=%0d",checks,refresh_count);
  $display("PASS tb_sdram_hardware");$finish;
 end
 initial begin #12000000;$display("TIMEOUT hardware state=%0d refresh_state=%0d received=%0d",dut.state,dut.refresh_state,dut.received);$finish;end
endmodule

`timescale 1ns/1ps
module tb_async_fifo;
 reg wc=0,rc=0,rst=0,wvalid=0,rready=0;
 always #7 wc=~wc;always #11 rc=~rc;
 reg [31:0] wdata=0;wire [31:0] rdata;wire wready,rvalid;
 wire [4:0] wl,rl;
 integer sent=0,got=0,wt=0,rt=0,epoch=0,total=0;
 reg enable_read=0,enable_write=0;
 reg stalled=0;reg [31:0] held;
 medq_async_fifo #(.W(32),.AW(4)) dut(.wclk(wc),.wrst_n(rst),.wvalid(wvalid),.wdata(wdata),
  .wready(wready),.wlevel(wl),.rclk(rc),.rrst_n(rst),.rready(rready),.rvalid(rvalid),.rdata(rdata),.rlevel(rl));
 function [31:0] pattern(input integer n);begin pattern=32'h93fe0000 ^ (n*32'd2753);end endfunction
 always @(negedge wc)begin
  wt=wt+1;wvalid=rst && enable_write && sent<1000 && wt%7!=0;wdata=pattern(epoch*10000+sent);
 end
 always @(posedge wc)if(rst && wvalid && wready)sent=sent+1;
 always @(negedge rc)begin rt=rt+1;rready=rst && enable_read && rt%5<3;end
 always @(posedge rc)if(rst)begin
  if(wl>16 || rl>16)$fatal(1,"ERROR FIFO count overflow");
  if(stalled && (!rvalid || rdata!==held))$fatal(1,"ERROR FIFO stalled data changed");
  stalled=rvalid && !rready;held=rdata;
  if(rvalid && rready)begin
   if(rdata!==pattern(epoch*10000+got))$fatal(1,"ERROR FIFO epoch=%0d index=%0d data=%h",epoch,got,rdata);
   got=got+1;total=total+1;
  end
 end else stalled=0;
 initial begin
  repeat(4)@(negedge wc);
  for(epoch=0;epoch<2;epoch=epoch+1)begin
   rst=0;enable_write=0;enable_read=0;sent=0;got=0;
   repeat(5)@(negedge wc);rst=1;enable_write=1;
   repeat(60)@(negedge wc);
   if(wl!=16 || wready || sent!=16)$fatal(1,"ERROR FIFO full capacity wl=%0d sent=%0d",wl,sent);
   enable_read=1;wait(got==1000);enable_write=0;
   repeat(8)@(negedge rc);if(rvalid || rl!=0)$fatal(1,"ERROR FIFO drain");
  end
  $display("PASS async FIFO: 2000 ordered words, independent clocks, full/empty, stalls, wrap, simultaneous transfer, reset");$finish;
 end
 initial begin #300000;$fatal(1,"TIMEOUT FIFO sent=%0d got=%0d",sent,got);end
endmodule

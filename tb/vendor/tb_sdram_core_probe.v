`timescale 1ns/1ps
// Observe the supplied encrypted controller, without replacing its data path.
module tb_sdram_core_probe;
reg clk=0; always #5 clk=~clk;
wire shift=~clk;
reg rst=1,wr=0,rd=0,ref_req=0;
reg [20:0] wa=0,ra=0;
reg [31:0] wd=0;
wire init,refresh,busy,rv;
wire [31:0] data,dq;
wire mc,ras,cas,we;
wire [10:0] addr;
wire [1:0] ba;
wire [3:0] dm;
sdr_as_ram #(.self_refresh_open(0)) core(
 .Sdr_clk(clk),.Sdr_clk_sft(shift),.Rst(rst),.App_ref_req(ref_req),
 .Sdr_init_done(init),.Sdr_init_ref_vld(refresh),.Sdr_busy(busy),
 .App_wr_en(wr),.App_wr_addr(wa),.App_wr_dm(4'b0),.App_wr_din(wd),
 .App_rd_en(rd),.App_rd_addr(ra),.Sdr_rd_en(rv),.Sdr_rd_dout(data),
 .SDRAM_CLK(mc),.SDR_RAS(ras),.SDR_CAS(cas),.SDR_WE(we),
 .SDR_BA(ba),.SDR_ADDR(addr),.SDR_DM(dm),.SDR_DQ(dq));
EG_PHY_SDRAM_2M_32 memory(.clk(mc),.ras_n(ras),.cas_n(cas),.we_n(we),
 .addr(addr),.ba(ba),.dq(dq),.cs_n(1'b0),.dm0(dm[0]),.dm1(dm[1]),
 .dm2(dm[2]),.dm3(dm[3]),.cke(1'b1));
integer cycle=0,n,got=0;
always @(posedge mc)if({ras,cas,we}!=3'b111)
 $display("PHY t=%0t cmd=%b addr=%h ba=%h dq=%h dm=%h",$time,{ras,cas,we},addr,ba,dq,dm);
always @(posedge clk)begin
 cycle=cycle+1;
 if(init && (wr||rd||rv||busy||refresh))
   $display("OBS %0d wr=%b rd=%b busy=%b refresh=%b rv=%b data=%h",cycle,wr,rd,busy,refresh,rv,data);
 if(rv)got=got+1;
end
initial begin
 repeat(8)@(negedge clk);rst=0;
 wait(init===1);repeat(40)@(negedge clk);
 for(n=0;n<8;n=n+1)begin wr=1;wa=n;wd=32'h12340000+n;@(negedge clk);end
 wr=0;repeat(60)@(negedge clk);
 rd=1;ra=0;@(negedge clk);rd=0;
 repeat(60)@(negedge clk);
 for(n=0;n<8;n=n+1)begin rd=1;ra=n;@(negedge clk);end
 rd=0;repeat(60)@(negedge clk);
 if(got==0)$display("FAIL no real SDRAM returns");
 else $display("PASS probe observed %0d returns",got);
 $finish;
end
initial begin #2000000;$display("TIMEOUT core init");$finish;end
endmodule

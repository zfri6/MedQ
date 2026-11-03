`timescale 1ns/1ps
// MedQ adaptation of the supplied BL4 application interface; not vendor code.
// Full bursts are buffered so application backpressure cannot stop physical DQ.
module medq_sdram_adapter #(parameter MEM_CLK_HZ=50000000) (
 input wire clk,clk_sdram,rst_n,
 input wire mem_req_valid,
 output wire mem_req_ready,
 input wire [21:0] mem_req_addr,
 input wire mem_req_we,
 input wire [8:0] mem_req_len,
 input wire mem_wr_valid,
 input wire [31:0] mem_wr_data,
 output wire mem_wr_ready,
 output wire mem_rd_valid,
 input wire mem_rd_ready,
 output wire [31:0] mem_rd_data,
 output wire init_done,
 output reg fault
);
 localparam IDLE=0,WC=1,LAUNCH=2,WP=3,WI=4,RI=5,TAIL=6,RP=7,RD=8,FAILED=9;
 reg [3:0] state;
 reg write_op;
 reg [20:0] base;
 reg [1:0] offset;
 reg [8:0] length,physical_length,collected,issued,received,consumed;
 reg [14:0] watchdog;
 reg [31:0] buffer[0:255];
 reg [31:0] buffer_q;
 wire [8:0] end_index={7'd0,offset}+length;
 wire [8:0] next_issued=issued+9'd1;
 wire [8:0] next_logical=next_issued-{7'd0,offset};
 wire [8:0] return_logical=received-{7'd0,offset};
 wire [8:0] next_consumed=consumed+9'd1;
 wire [7:0] read_index=state==WI ?
    ((next_issued>={7'd0,offset} && next_issued<end_index) ? next_logical[7:0] : 8'd0) :
    state==RD ? (mem_rd_ready ? next_consumed[7:0] : consumed[7:0]) : 8'd0;
 wire [22:0] request_end={1'b0,mem_req_addr}+{14'd0,mem_req_len};
 wire legal=mem_req_len!=0 && mem_req_len<=256 && !mem_req_addr[21] && request_end<=23'd2097152;
 reg request_checked,request_legal;
 wire core_busy,core_refresh,core_valid;
 wire [31:0] core_data;
 wire app_write=state==WI && rst_n;
 wire app_read=state==RI && rst_n;
 wire [20:0] app_address=base+{12'd0,issued};
 wire [3:0] app_mask=issued>={7'd0,offset} && issued<end_index ? 4'h0 : 4'hf;
 wire sdram_clk,ras_n,cas_n,we_n;
 wire [10:0] phy_addr;
 wire [1:0] bank;
 wire [3:0] mask;
 wire [31:0] dq;
 reg [2:0] refresh_state;
 reg [10:0] refresh_timer;
 reg refresh_due;
 reg [4:0] quiet;
 reg [14:0] refresh_watchdog;
 localparam REFRESH_CYCLES=MEM_CLK_HZ/64000;
 wire refresh_request=refresh_state==2;
 wire physically_quiet=!app_write && !app_read && !core_valid && !core_busy && !core_refresh;
 // The requester holds valid/address/length until ready. Check the wide address
 // sum in a separate cycle so it does not feed every master's ready/counter CE.
 assign mem_req_ready=rst_n && init_done && state==IDLE && refresh_state==0 && !refresh_due && request_checked && request_legal;
 assign mem_wr_ready=rst_n && state==WC;
 assign mem_rd_valid=rst_n && state==RD;
 assign mem_rd_data=mem_rd_valid ? buffer_q : 32'd0;

 // A single synchronous write port and a single synchronous read port.
 always @(posedge clk) begin
   if(rst_n && state==WC && mem_wr_valid) buffer[collected[7:0]]<=mem_wr_data;
   else if(rst_n && core_valid && (state==RI || state==TAIL) &&
           received>={7'd0,offset} && received<end_index)
     buffer[return_logical[7:0]]<=core_data;
   buffer_q<=buffer[read_index];
 end

 always @(posedge clk or negedge rst_n) begin
   if(!rst_n)begin
     refresh_state<=0;refresh_timer<=0;refresh_due<=0;quiet<=0;refresh_watchdog<=0;
   end else if(!init_done)begin
     refresh_state<=0;refresh_timer<=0;refresh_due<=0;quiet<=0;refresh_watchdog<=0;
   end else begin
     if(physically_quiet)begin if(quiet!=31)quiet<=quiet+1'b1;end else quiet<=0;
     if(refresh_request)begin refresh_timer<=0;refresh_due<=0;end
     else if(refresh_timer==REFRESH_CYCLES-1)refresh_due<=1;
     else if(!refresh_due)refresh_timer<=refresh_timer+1'b1;
     if(refresh_state!=0)begin
       if(refresh_watchdog!=32767)refresh_watchdog<=refresh_watchdog+1'b1;
     end else refresh_watchdog<=0;
     case(refresh_state)
       0:if(refresh_due)refresh_state<=1;
       1:if(quiet>=16)refresh_state<=2;
       2:refresh_state<=3;
       3:if(core_refresh)refresh_state<=4;
       4:if(!core_refresh)refresh_state<=0;
       default:refresh_state<=1;
     endcase
   end
 end

 always @(posedge clk or negedge rst_n) begin
   if(!rst_n)begin
     state<=IDLE;write_op<=0;base<=0;offset<=0;length<=0;physical_length<=0;
     collected<=0;issued<=0;received<=0;consumed<=0;watchdog<=0;fault<=0;
     request_checked<=0;request_legal<=0;
   end else begin
     if(state!=IDLE || !mem_req_valid)request_checked<=0;
     else if(!request_checked)begin
       request_checked<=1;request_legal<=legal;
       if(!legal)fault<=1;
     end
     if(state==LAUNCH || state==WP || state==WI || state==RI || state==TAIL)begin
       if(watchdog!=32767)watchdog<=watchdog+1'b1;
     end else watchdog<=0;
     if(core_valid && (state==RI || state==TAIL))received<=received+1'b1;
     if(refresh_watchdog==32767 || watchdog==32767)begin fault<=1;state<=FAILED;end
     else case(state)
       IDLE:if(mem_req_valid && mem_req_ready)begin
         request_checked<=0;
         base<={mem_req_addr[20:2],2'b00};offset<=mem_req_addr[1:0];length<=mem_req_len;
         physical_length<=({7'd0,mem_req_addr[1:0]}+mem_req_len+9'd3)&9'h1fc;
         write_op<=mem_req_we;collected<=0;issued<=0;received<=0;consumed<=0;
         state<=mem_req_we ? WC : LAUNCH;
       end
       WC:if(mem_wr_valid)begin
         collected<=collected+1'b1;
         if(collected+9'd1==length)state<=LAUNCH;
       end
       LAUNCH:if(!refresh_due && refresh_state==0 && quiet>=16)state<=write_op ? WP : RI;
       WP:state<=WI;
       WI,RI:begin
         issued<=issued+1'b1;
         if(issued+9'd1==physical_length)state<=TAIL;
       end
       TAIL:if(quiet>=16 && (write_op || received==physical_length))begin
         state<=write_op ? IDLE : RP;
       end
       RP:state<=RD;
       RD:if(mem_rd_ready)begin
         consumed<=consumed+1'b1;
         if(consumed+9'd1==length)state<=IDLE;
       end
       FAILED:state<=FAILED;
       default:begin state<=FAILED;fault<=1;end
     endcase
   end
 end

 sdr_as_ram #(.self_refresh_open(0)) u_core(
  .Sdr_clk(clk),.Sdr_clk_sft(clk_sdram),.Rst(!rst_n),.App_ref_req(refresh_request),
  .Sdr_init_done(init_done),.Sdr_init_ref_vld(core_refresh),.Sdr_busy(core_busy),
  .App_wr_en(app_write),.App_wr_addr(app_address),.App_wr_dm(app_mask),.App_wr_din(buffer_q),
  .App_rd_en(app_read),.App_rd_addr(app_address),.Sdr_rd_en(core_valid),.Sdr_rd_dout(core_data),
  .SDRAM_CLK(sdram_clk),.SDR_RAS(ras_n),.SDR_CAS(cas_n),.SDR_WE(we_n),
  .SDR_BA(bank),.SDR_ADDR(phy_addr),.SDR_DM(mask),.SDR_DQ(dq));
 // Original IP Generator wrapper, copied byte-for-byte.
 sdram u_device(.clk(sdram_clk),.ras_n(ras_n),.cas_n(cas_n),.we_n(we_n),
  .addr(phy_addr),.ba(bank),.dq(dq),.cs_n(1'b0),.dm0(mask[0]),.dm1(mask[1]),
  .dm2(mask[2]),.dm3(mask[3]),.cke(1'b1));
endmodule

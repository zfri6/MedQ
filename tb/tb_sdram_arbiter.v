`timescale 1ns / 1ps
module tb_sdram_arbiter;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0;
    reg [3:0] req=0,we=0,wvalid=0,rready=0;
    wire [3:0] ready,wready,rvalid;
    reg [21:0] addr[0:3];reg [8:0] len[0:3];reg [31:0] wdata[0:3];wire [31:0] rdata[0:3];
    wire mreq,mready,mwe,mwv,mwr,mrv,mrr,init_done;
    wire [21:0] ma;wire [8:0] ml;wire [31:0] mwd,mrd;
    wire ctrl_ready;
    integer cycle=0,completed=0;
    always @(posedge clk) cycle<=cycle+1;
    wire stall_request=(cycle%7)==3 || (cycle%7)==4;
    assign mready=ctrl_ready && !stall_request;
    sdram_arbiter #(.STARVE_MAX(8)) dut(.clk(clk),.rst_n(rst_n),
        .aud_req_valid(req[0]),.aud_req_ready(ready[0]),.aud_req_addr(addr[0]),.aud_req_we(we[0]),.aud_req_len(len[0]),
        .aud_wr_valid(wvalid[0]),.aud_wr_ready(wready[0]),.aud_wr_data(wdata[0]),
        .aud_rd_valid(rvalid[0]),.aud_rd_ready(rready[0]),.aud_rd_data(rdata[0]),
        .disp_req_valid(req[1]),.disp_urgent(1'b0),.disp_req_ready(ready[1]),.disp_req_addr(addr[1]),.disp_req_we(we[1]),.disp_req_len(len[1]),
        .disp_wr_valid(wvalid[1]),.disp_wr_ready(wready[1]),.disp_wr_data(wdata[1]),
        .disp_rd_valid(rvalid[1]),.disp_rd_ready(rready[1]),.disp_rd_data(rdata[1]),
        .tr_req_valid(req[2]),.tr_req_ready(ready[2]),.tr_req_addr(addr[2]),.tr_req_we(we[2]),.tr_req_len(len[2]),
        .tr_wr_valid(wvalid[2]),.tr_wr_ready(wready[2]),.tr_wr_data(wdata[2]),
        .tr_rd_valid(rvalid[2]),.tr_rd_ready(rready[2]),.tr_rd_data(rdata[2]),
        .wr_req_valid(req[3]),.wr_req_ready(ready[3]),.wr_req_addr(addr[3]),.wr_req_we(we[3]),.wr_req_len(len[3]),
        .wr_wr_valid(wvalid[3]),.wr_wr_ready(wready[3]),.wr_wr_data(wdata[3]),
        .wr_rd_valid(rvalid[3]),.wr_rd_ready(rready[3]),.wr_rd_data(rdata[3]),
        .mem_req_valid(mreq),.mem_req_ready(mready),.mem_req_addr(ma),.mem_req_we(mwe),.mem_req_len(ml),
        .mem_wr_valid(mwv),.mem_wr_ready(mwr),.mem_wr_data(mwd),.mem_rd_valid(mrv),.mem_rd_ready(mrr),.mem_rd_data(mrd));
    sdram_ctrl_wrap memory(.clk(clk),.rst_n(rst_n),.mem_req_valid(mreq && !stall_request),.mem_req_ready(ctrl_ready),
        .mem_req_addr(ma),.mem_req_we(mwe),.mem_req_len(ml),.mem_wr_valid(mwv),.mem_wr_ready(mwr),.mem_wr_data(mwd),
        .mem_rd_valid(mrv),.mem_rd_ready(mrr),.mem_rd_data(mrd),.init_done(init_done));
    reg stalled=0;reg [31:0] held_data;reg [31:0] held_request;
    reg req_stalled=0;
    always @(posedge clk)if(rst_n)begin
        if(stalled && (mrv!==1 || mrd!==held_data))$fatal(1,"ERROR read data changed under backpressure");
        stalled<=mrv && !mrr;held_data<=mrd;
        if(req_stalled && {ma,mwe,ml}!==held_request)$fatal(1,"ERROR unstable stalled request");
        req_stalled<=mreq && !mready;held_request<={ma,mwe,ml};
    end
    task automatic request_port(input integer id,input bit write_en,input [21:0] base,input integer words);
        begin
            @(negedge clk);addr[id]=base;len[id]=words;we[id]=write_en;req[id]=1;
            do @(posedge clk);while(!ready[id]);
            @(negedge clk);req[id]=0;
        end
    endtask
    task automatic write_port(input integer id,input [21:0] base,input integer words,input [31:0] seed);
        integer n;
        begin
            request_port(id,1,base,words);
            n=0;
            while(n<words)begin
                @(negedge clk);wvalid[id]=(cycle%5)!=0;wdata[id]=seed^n;
                @(posedge clk);if(wvalid[id] && wready[id])n=n+1;
            end
            @(negedge clk);wvalid[id]=0;completed=completed+1;
        end
    endtask
    task automatic read_port(input integer id,input [21:0] base,input integer words,input [31:0] seed,input integer offset);
        integer n;
        begin
            request_port(id,0,base,words);n=0;
            while(n<words)begin
                @(negedge clk);rready[id]=(cycle%5)!=id;
                @(posedge clk);if(rvalid[id] && rready[id])begin
                    if(rdata[id] !== (seed^(offset+n)))$fatal(1,"ERROR port=%0d beat=%0d exp=%h got=%h",id,n,seed^(offset+n),rdata[id]);
                    n=n+1;
                end
            end
            @(negedge clk);rready[id]=0;completed=completed+1;
        end
    endtask
    integer n;
    initial begin
        for(n=0;n<4;n=n+1)begin addr[n]=0;len[n]=0;wdata[n]=0;end
        repeat(5)@(negedge clk);rst_n=1;wait(init_done);
        write_port(3,22'h04b000,256,32'h8246ab00);
        fork
            read_port(0,22'h04b000,17,32'h8246ab00,0);
            read_port(1,22'h04b020,64,32'h8246ab00,32);
            read_port(2,22'h04b080,16,32'h8246ab00,128);
            write_port(3,22'h0e1000,13,32'h98760000);
        join
        read_port(0,22'h0e1000,13,32'h98760000,0);
        if(completed!=6)$fatal(1,"ERROR incomplete transactions %0d",completed);
        if(memory.sim_mem[0]!==0 || memory.sim_mem[22'h04b000]!==32'h8246ab00)$fatal(1,"ERROR memory alias");
        $display("PASS SDRAM: 256-beat write, four competing masters, stalls, exact data, high addresses");$finish;
    end
    initial begin #1000000;$fatal(1,"TIMEOUT SDRAM");end
endmodule

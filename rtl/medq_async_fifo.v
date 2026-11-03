`timescale 1ns / 1ps
// Dual-clock FIFO, Gray pointers cross through two synchronizer registers.
module medq_async_fifo #(parameter W=32, parameter AW=9) (
    input wire wclk, wrst_n, wvalid,
    input wire [W-1:0] wdata,
    output wire wready,
    output wire [AW:0] wlevel,
    input wire rclk, rrst_n, rready,
    output wire rvalid,
    output wire [W-1:0] rdata,
    output wire [AW:0] rlevel
);
    reg [W-1:0] mem [0:(1<<AW)-1];
    reg [AW:0] wb, rb, wg, rg;
    reg have_word;
    reg [W-1:0] read_word;
    (* ASYNC_REG = "TRUE" *) reg [AW:0] rg1, rg2, wg1, wg2;
    function [AW:0] binary;
        input [AW:0] gray;
        integer n;
        begin
            binary[AW]=gray[AW];
            for (n=AW-1;n>=0;n=n-1) binary[n]=binary[n+1]^gray[n];
        end
    endfunction
    assign wready = wg != {~rg2[AW:AW-1],rg2[AW-2:0]};
    assign rvalid = have_word;
    assign wlevel = wb-binary(rg2);
    assign rlevel = binary(wg2)-rb;
    assign rdata = read_word;
    wire [AW:0] wn = wb+1'b1;
    wire [AW:0] rn = rb+1'b1;
    wire take=have_word && rready;
    wire [AW:0] read_position=take ? rn : rb;
    wire next_available=(read_position^(read_position>>1))!=wg2;
    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin wb<=0; wg<=0; rg1<=0; rg2<=0; end
        else begin
            rg1<=rg; rg2<=rg1;
            if (wvalid && wready) begin wb<=wn; wg<=wn^(wn>>1); end
        end
    end
    always @(posedge wclk) if (wvalid && wready) mem[wb[AW-1:0]]<=wdata;
    // No reset on the memory port: true dual-clock synchronous block RAM.
    always @(posedge rclk) if(next_available) read_word<=mem[read_position[AW-1:0]];
    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin rb<=0; rg<=0; wg1<=0; wg2<=0; have_word<=0; end
        else begin
            wg1<=wg; wg2<=wg1;
            have_word<=next_available;
            if (rvalid && rready) begin rb<=rn; rg<=rn^(rn>>1); end
        end
    end
endmodule

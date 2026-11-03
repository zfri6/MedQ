`timescale 1ns / 1ps
// Behavioral regression or original controller with buffered application bridge.
module sdram_ctrl_wrap (
    input  wire        clk,
    input  wire        clk_sdram,
    input  wire        rst_n,
    input  wire        mem_req_valid,
    output wire        mem_req_ready,
    input  wire [21:0] mem_req_addr,
    input  wire        mem_req_we,
    input  wire [8:0]  mem_req_len,
    input  wire        mem_wr_valid,
    input  wire [31:0] mem_wr_data,
    output wire        mem_wr_ready,
    output wire        mem_rd_valid,
    input  wire        mem_rd_ready,
    output wire [31:0] mem_rd_data,

    output wire        init_done,
    output wire        fault
);


`ifdef SIMULATION
`ifndef MEDQ_REAL_SDRAM
`define MEDQ_BEHAVIORAL_SDRAM
`endif
`endif
`ifdef MEDQ_BEHAVIORAL_SDRAM
    assign fault=1'b0;
    // Full 8 MiB map, deliberately no address truncation or aliasing.
    reg [31:0] sim_mem [0:2097151];
    integer k;
    initial for (k=0;k<2097152;k=k+1) sim_mem[k]=0;
    localparam IDLE=0, READ=1, WRITE=2;
    reg [1:0] state;
    reg [21:0] addr;
    reg [8:0] remaining;
    reg [3:0] delay_count;
    reg [4:0] init_count;
    assign init_done = init_count==31;
    assign mem_req_ready = rst_n && init_done && state==IDLE;
    assign mem_wr_ready = rst_n && state==WRITE;
    assign mem_rd_valid = rst_n && state==READ && delay_count==0;
    assign mem_rd_data = mem_rd_valid ? sim_mem[addr] : 32'd0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; addr<=0; remaining<=0; delay_count<=0; init_count<=0;
        end else begin
            if (!init_done) init_count<=init_count+1'b1;
            case (state)
                IDLE: if (mem_req_valid && mem_req_ready) begin
                    addr<=mem_req_addr; remaining<=mem_req_len;
                    state<=mem_req_we ? WRITE : READ;
                    delay_count<=4;
                end
                READ: if (delay_count!=0) delay_count<=delay_count-1'b1;
                    else if (mem_rd_valid && mem_rd_ready) begin
                        addr<=addr+1'b1; remaining<=remaining-1'b1;
                        if (remaining==1) state<=IDLE;
                    end
                WRITE: if (mem_wr_valid && mem_wr_ready) begin
                    sim_mem[addr]<=mem_wr_data;
                    addr<=addr+1'b1; remaining<=remaining-1'b1;
                    if (remaining==1) state<=IDLE;
                end
                default: state<=IDLE;
            endcase
        end
    end
`else
    medq_sdram_adapter u_hardware(
      .clk(clk),.clk_sdram(clk_sdram),.rst_n(rst_n),
      .mem_req_valid(mem_req_valid),.mem_req_ready(mem_req_ready),
      .mem_req_addr(mem_req_addr),.mem_req_we(mem_req_we),.mem_req_len(mem_req_len),
      .mem_wr_valid(mem_wr_valid),.mem_wr_data(mem_wr_data),.mem_wr_ready(mem_wr_ready),
      .mem_rd_valid(mem_rd_valid),.mem_rd_ready(mem_rd_ready),.mem_rd_data(mem_rd_data),
      .init_done(init_done),.fault(fault));
`endif
`ifdef MEDQ_BEHAVIORAL_SDRAM
`undef MEDQ_BEHAVIORAL_SDRAM
`endif
endmodule

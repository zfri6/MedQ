`timescale 1ns / 1ps
// Sequential framebuffer prefetch in clk_mem; pixels consumed in clk_pix.
module frame_reader (
    input wire clk_pix, rst_n_pix, clk_mem, rst_n_mem,
    input wire [21:0] fb_base,
    input wire frame_start, line_start, de,
    output reg [23:0] px_rgb,
    output reg underrun,
    output wire primed,
    output reg urgent,
    output wire disp_req_valid,
    input wire disp_req_ready,
    output wire [21:0] disp_req_addr,
    output wire disp_req_we,
    output wire [8:0] disp_req_len,
    output wire disp_wr_valid,
    input wire disp_wr_ready,
    output wire [31:0] disp_wr_data,
    input wire disp_rd_valid,
    output wire disp_rd_ready,
    input wire [31:0] disp_rd_data
);
    localparam IDLE=0, REQUEST=1, READ=2;
    reg [1:0] state;
    reg [21:0] offset, base;
    reg [8:0] received;
    wire fifo_ready, fifo_valid;
    wire [31:0] fifo_data;
    wire [11:0] wlevel, rlevel;
    // Pixel-domain readiness: enough data to absorb burst/refresh arbitration.
    assign primed = rlevel>=12'd1536;
    always @(posedge clk_mem or negedge rst_n_mem)begin
        if(!rst_n_mem)urgent<=1;
        else urgent<=wlevel<12'd1536;
    end
    medq_async_fifo #(.W(32),.AW(11)) pixels (
        .wclk(clk_mem),.wrst_n(rst_n_mem),.wvalid(disp_rd_valid && state==READ),
        .wdata(disp_rd_data),.wready(fifo_ready),.wlevel(wlevel),
        .rclk(clk_pix),.rrst_n(rst_n_pix),.rready(de),
        .rvalid(fifo_valid),.rdata(fifo_data),.rlevel(rlevel));
    assign disp_req_valid=state==REQUEST;
    assign disp_req_addr=base+offset;
    assign disp_req_we=0;
    assign disp_req_len=9'd256;
    assign disp_wr_valid=0;
    assign disp_wr_data=0;
    assign disp_rd_ready=state==READ && fifo_ready;
    // The whole 640*480 frame is a multiple of 256. Backpressure bounds
    // prefetch to the FIFO capacity; the stream wraps at the frame boundary.
    always @(posedge clk_mem or negedge rst_n_mem) begin
        if (!rst_n_mem) begin state<=IDLE; offset<=0; base<=0; received<=0; end
        else case (state)
            IDLE: if (wlevel<=1792) begin
                if (offset==0) base<=fb_base;
                state<=REQUEST;
            end
            REQUEST: if (disp_req_ready) begin state<=READ; received<=0; end
            READ: if (disp_rd_valid && disp_rd_ready) begin
                received<=received+1'b1;
                if (received==255) begin
                    offset<=offset==22'd306944 ? 22'd0 : offset+22'd256;
                    state<=IDLE;
                end
            end
            default: state<=IDLE;
        endcase
    end
    always @(posedge clk_pix or negedge rst_n_pix) begin
        if (!rst_n_pix) begin px_rgb<=0; underrun<=0; end
        else begin
            if (line_start) underrun<=0;
            if (de) begin
                px_rgb<=fifo_valid ? fifo_data[23:0] : 24'hff00ff;
                if (!fifo_valid) underrun<=1;
            end else px_rgb<=0;
        end
    end
endmodule

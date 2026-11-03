`timescale 1ns / 1ps
// Streaming BMP BI_RGB decoder; accepts back-to-back bytes and skips row padding.
module bmp_parser (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start,       // single-cycle pulse to start parsing
    input  wire       in_valid,
    input  wire [7:0] in_data,
    output reg        hdr_valid,
    output reg  [10:0] img_width,
    output reg  [10:0] img_height,
    output reg  [5:0] img_bpp,
    output reg        img_topdown,
    output reg        px_valid,
    output reg  [23:0] px_rgb,
    output reg  [10:0] px_x,
    output reg  [10:0] px_y,
    output reg        done,
    output reg        err,
    output reg  [3:0] err_code
);


    localparam IDLE=0, HEADER=1, SKIP=2, PIXELS=3;
    reg [1:0] state;
    reg [7:0] hdr_buf [0:53];
    reg [5:0] index;
    reg [31:0] skip_left, stride, row_byte;
    reg [10:0] row, col;
    reg [1:0] component;
    reg [7:0] blue,green,red;
    wire [31:0] offbits={hdr_buf[13],hdr_buf[12],hdr_buf[11],hdr_buf[10]};
    wire [31:0] width_value={hdr_buf[21],hdr_buf[20],hdr_buf[19],hdr_buf[18]};
    wire [31:0] height_value={hdr_buf[25],hdr_buf[24],hdr_buf[23],hdr_buf[22]};
    wire [31:0] height_abs=height_value[31] ? -height_value : height_value;
    wire [15:0] bpp={hdr_buf[29],hdr_buf[28]};
    wire [31:0] compression={hdr_buf[33],hdr_buf[32],hdr_buf[31],hdr_buf[30]};
    reg [3:0] header_error;
    always @* begin
        header_error=0;
        if (hdr_buf[0]!=8'h42 || hdr_buf[1]!=8'h4d) header_error=1;
        else if (compression!=0) header_error=2;
        else if (bpp!=24 && bpp!=32) header_error=3;
        else if (width_value==0 || width_value>1024 || height_abs==0 || height_abs>1024) header_error=4;
        else if (offbits<54 || {hdr_buf[27],hdr_buf[26]}!=16'd1) header_error=5;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; index<=0; skip_left<=0; stride<=0; row_byte<=0;
            row<=0; col<=0; component<=0; blue<=0; green<=0; red<=0;
            hdr_valid<=0; img_width<=0; img_height<=0; img_bpp<=0; img_topdown<=0;
            px_valid<=0; px_rgb<=0; px_x<=0; px_y<=0; done<=0; err<=0; err_code<=0;
        end else begin
            hdr_valid<=0; px_valid<=0; done<=0; err<=0;
            if (start) begin
                state<=HEADER; index<=0; row<=0; col<=0; row_byte<=0; component<=0; err_code<=0;
            end else if (in_valid) case (state)
                HEADER: begin
                    hdr_buf[index]<=in_data;
                    if (index==53) begin
                        if (header_error!=0) begin
                            err<=1; err_code<=header_error; state<=IDLE;
                        end else begin
                            img_width<=width_value[10:0]; img_height<=height_abs[10:0];
                            img_bpp<=bpp[5:0]; img_topdown<=height_value[31]; hdr_valid<=1;
                            stride<=((width_value*(bpp/8))+3)&32'hfffffffc;
                            skip_left<=offbits-54;
                            state<=offbits==54 ? PIXELS : SKIP;
                        end
                    end else index<=index+1'b1;
                end
                SKIP: begin
                    skip_left<=skip_left-1'b1;
                    if (skip_left==1) state<=PIXELS;
                end
                PIXELS: begin
                    if (row_byte<img_width*(img_bpp/8)) begin
                        case (component)
                            0: blue<=in_data;
                            1: green<=in_data;
                            2: red<=in_data;
                            default: red<=red;
                        endcase
                        if ((img_bpp==24 && component==2) || component==3) begin
                            px_valid<=1;
                            px_rgb<=img_bpp==24 ? {in_data,green,blue} : {red,green,blue};
                            px_x<=col; px_y<=img_topdown ? row : img_height-1'b1-row;
                            col<=col+1'b1; component<=0;
                        end else component<=component+1'b1;
                    end
                    if (row_byte==stride-1) begin
                        row_byte<=0; col<=0; component<=0; row<=row+1'b1;
                        if (row==img_height-1) begin state<=IDLE; done<=1; end
                    end else row_byte<=row_byte+1'b1;
                end
                default: state<=IDLE;
            endcase
        end
    end
endmodule

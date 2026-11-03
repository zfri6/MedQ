`timescale 1ns / 1ps
// frame_reader + transition: two registers; OSD: ROM plus output register.
// spectrum_render has one register, so its output needs one extra delay.
module medq_video_align (
    input wire clk,rst_n,de,hs,vs,
    input wire [23:0] spec_rgb,
    input wire [7:0] spec_alpha,
    output wire de_out,hs_out,vs_out,
    output reg [23:0] spec_rgb_out,
    output reg [7:0] spec_alpha_out
);
    reg [1:0] de_pipe,hs_pipe,vs_pipe;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin de_pipe<=0; hs_pipe<=3; vs_pipe<=3; spec_rgb_out<=0; spec_alpha_out<=0; end
        else begin
            de_pipe<={de_pipe[0],de}; hs_pipe<={hs_pipe[0],hs}; vs_pipe<={vs_pipe[0],vs};
            spec_rgb_out<=spec_rgb; spec_alpha_out<=spec_alpha;
        end
    end
    assign de_out=de_pipe[1]; assign hs_out=hs_pipe[1]; assign vs_out=vs_pipe[1];
endmodule

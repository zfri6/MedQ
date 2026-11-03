`timescale 1ns / 1ps
// Neutral BC=128/128. Saturating BC followed by two exact /255 alpha blends.
module osd_compositor_reference (
    input wire clk,rst_n,de_in,hs_in,vs_in,
    input wire [23:0] rgb_base,osd_rgb,
    input wire [7:0] osd_alpha,
    input wire [23:0] spec_rgb,
    input wire [7:0] spec_alpha,
    input wire [63:0] param,
    output reg de_out,hs_out,vs_out,
    output reg [23:0] rgb_out
);
    function [7:0] bc;
        input [7:0] pixel,brightness,contrast;
        integer value;
        begin
            value=(pixel*contrast)/128+brightness-128;
            bc=value<0 ? 8'd0 : value>255 ? 8'd255 : value[7:0];
        end
    endfunction
    function [23:0] blend;
        input [23:0] base,over;
        input [7:0] alpha;
        integer j;
        reg [16:0] total;
        begin
            for (j=0;j<3;j=j+1) begin
                total=base[j*8+:8]*(255-alpha)+over[j*8+:8]*alpha+127;
                blend[j*8+:8]=total/255;
            end
        end
    endfunction
    wire [23:0] adjusted={bc(rgb_base[23:16],param[7:0],param[15:8]),
                          bc(rgb_base[15:8],param[7:0],param[15:8]),
                          bc(rgb_base[7:0],param[7:0],param[15:8])};
    wire [23:0] text_pixel=blend(adjusted,osd_rgb,osd_alpha);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin de_out<=0; hs_out<=1; vs_out<=1; rgb_out<=0; end
        else begin
            de_out<=de_in; hs_out<=hs_in; vs_out<=vs_in;
            rgb_out<=blend(text_pixel,spec_rgb,spec_alpha);
        end
    end
endmodule

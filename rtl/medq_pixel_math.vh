// Local module function. Exact floor(value/255) for pixel-blend totals
// 0..65152 (255*255 + rounding bias 127). No pixel approximation.
function [7:0] medq_div255;
    input [15:0] value;
    reg [16:0] folded;
    begin
        folded={1'b0,value}+17'd1+{9'd0,value[15:8]};
        medq_div255=folded[15:8];
    end
endfunction

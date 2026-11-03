`timescale 1ns / 1ps
module hdmi_terc4_encoder(input wire [3:0] din,output reg [9:0] dout);
    always @* case(din)
        4'd0: dout=10'b1010011100;
        4'd1: dout=10'b1001100011;
        4'd2: dout=10'b1011100100;
        4'd3: dout=10'b1011100010;
        4'd4: dout=10'b0101110001;
        4'd5: dout=10'b0100011110;
        4'd6: dout=10'b0110001110;
        4'd7: dout=10'b0100111100;
        4'd8: dout=10'b1011001100;
        4'd9: dout=10'b0100111001;
        4'd10: dout=10'b0110011100;
        4'd11: dout=10'b1011000110;
        4'd12: dout=10'b1010001110;
        4'd13: dout=10'b1001110001;
        4'd14: dout=10'b0101100011;
        4'd15: dout=10'b1011000011;
        default:dout=10'b1010011100;
    endcase
endmodule

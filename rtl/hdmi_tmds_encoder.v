`timescale 1ns / 1ps
// DVI 1.0 TMDS transition minimization and running disparity, one cycle.
module hdmi_tmds_encoder (
    input wire clk, rst_n,
    input wire [7:0] din,
    input wire [1:0] c,
    input wire de,
    output reg [9:0] dout
);
    reg signed [5:0] cnt;
    reg [8:0] qm;
    reg [9:0] symbol;
    integer ones, balance, i;
    always @* begin
        ones = 0;
        for (i=0; i<8; i=i+1) ones = ones + din[i];
        qm[0] = din[0];
        qm[8] = !(ones > 4 || (ones == 4 && !din[0]));
        for (i=1; i<8; i=i+1)
            qm[i] = qm[8] ? (qm[i-1] ^ din[i]) : ~(qm[i-1] ^ din[i]);
        ones = 0;
        for (i=0; i<8; i=i+1) ones = ones + qm[i];
        balance = 2*ones - 8;
        if (cnt == 0 || balance == 0)
            symbol = {~qm[8], qm[8], qm[8] ? qm[7:0] : ~qm[7:0]};
        else if ((cnt > 0 && balance > 0) || (cnt < 0 && balance < 0))
            symbol = {1'b1, qm[8], ~qm[7:0]};
        else
            symbol = {1'b0, qm[8], qm[7:0]};
    end
    integer delta, j;
    always @* begin
        delta = -10;
        for (j=0; j<10; j=j+1) delta = delta + 2*symbol[j];
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt <= 0;
            dout <= 10'b1101010100;
        end else if (!de) begin
            cnt <= 0;
            case (c)
                2'b00: dout <= 10'b1101010100;
                2'b01: dout <= 10'b0010101011;
                2'b10: dout <= 10'b0101010100;
                2'b11: dout <= 10'b1010101011;
            endcase
        end else begin
            cnt <= cnt + delta;
            dout <= symbol;
        end
    end
endmodule

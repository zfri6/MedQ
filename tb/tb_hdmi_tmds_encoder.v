`timescale 1ns / 1ps
module tb_hdmi_tmds_encoder;
    reg clk=0;always #20 clk=~clk;
    reg rst_n=0,de=0;
    reg [7:0] din=0;
    reg [1:0] c=0;
    wire [9:0] dout;
    integer n,j,ones,disparity=0;
    reg [7:0] q,decoded;
    reg [9:0] control[0:3];
    reg [31:0] random_state=32'h78563412;
    hdmi_tmds_encoder dut(.clk(clk),.rst_n(rst_n),.din(din),.c(c),.de(de),.dout(dout));
    initial begin
        control[0]=10'b1101010100;control[1]=10'b0010101011;
        control[2]=10'b0101010100;control[3]=10'b1010101011;
        repeat(4)@(negedge clk);rst_n=1;
        for(n=0;n<4;n=n+1)begin
            @(negedge clk);c=n;@(posedge clk);#1;
            if(dout!==control[n])$fatal(1,"ERROR control %0d",n);
        end
        @(negedge clk);de=1;din=0;@(posedge clk);#1;
        if(dout!==10'b0100000000)$fatal(1,"ERROR known zero vector");
        disparity=-8;
        for(n=0;n<8192;n=n+1)begin
            @(negedge clk);
            random_state=random_state^(random_state<<13);random_state=random_state^(random_state>>17);random_state=random_state^(random_state<<5);
            din=n<256 ? n[7:0] : n<512 ? 8'haa : n<768 ? 8'hff : random_state[7:0];
            @(posedge clk);#1;
            if(^dout===1'bx)$fatal(1,"ERROR X TMDS");
            q=dout[9] ? ~dout[7:0] : dout[7:0];
            decoded[0]=q[0];
            for(j=1;j<8;j=j+1)decoded[j]=dout[8] ? q[j]^q[j-1] : ~(q[j]^q[j-1]);
            if(decoded!==din)$fatal(1,"ERROR roundtrip n=%0d exp=%h got=%h",n,din,decoded);
            ones=0;for(j=0;j<10;j=j+1)ones=ones+dout[j];
            disparity=disparity+2*ones-10;
            if(disparity>10 || disparity< -10)$fatal(1,"ERROR DC disparity %0d",disparity);
        end
        $display("PASS TMDS: four control codes, 8193 video symbols, decode and DC bound");$finish;
    end
    initial begin #1000000;$fatal(1,"TIMEOUT TMDS");end
endmodule

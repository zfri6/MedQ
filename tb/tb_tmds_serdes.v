`timescale 1ns / 1ps
module tb_tmds_serdes;
    reg pix=0,ser=0,rst=0;always #20 pix=~pix;always #4 ser=~ser;
    reg [9:0] din=0;wire serial;
    reg [9:0] words[0:255];integer written=0,n,j;
    tmds_serdes dut(.clk_pix(pix),.clk_ser(ser),.rst_n(rst),.din(din),.sdata_p(serial));
    always @(negedge pix)if(rst)din=(din+10'd139)^10'h2a5;
    always @(posedge pix)if(rst)begin words[written]=din;written=written+1;end
    initial begin
        repeat(2)@(negedge pix);rst=1;
        @(posedge pix);#1;
        for(n=0;n<128;n=n+1)for(j=0;j<10;j=j+1)begin
            @(ser);#1;
            if(serial!==words[n][j])$fatal(1,"ERROR serializer word=%0d bit=%0d exp=%b got=%b",n,j,words[n][j],serial);
        end
        $display("PASS serializer: 128 consecutive words, ten DDR bits per pixel, LSB first");$finish;
    end
    initial begin #10000;$fatal(1,"TIMEOUT serializer");end
endmodule

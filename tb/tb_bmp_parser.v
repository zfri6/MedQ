`timescale 1ns / 1ps
module tb_bmp_parser;
    reg clk=0;always #10 clk=~clk;
    reg rst=0,start=0,valid=0;reg [7:0] data=0,bytes[0:127];
    wire hv,pv,done,err,topdown;wire [3:0] code;wire [10:0] width,height,px,py;wire [5:0] bpp;wire [23:0] rgb;
    reg [23:0] expect_rgb[0:1];reg [10:0] expect_x[0:1],expect_y[0:1];
    integer received=0,done_count=0,errors=0,i;
    bmp_parser dut(.clk(clk),.rst_n(rst),.start(start),.in_valid(valid),.in_data(data),.hdr_valid(hv),
        .img_width(width),.img_height(height),.img_bpp(bpp),.img_topdown(topdown),
        .px_valid(pv),.px_rgb(rgb),.px_x(px),.px_y(py),.done(done),.err(err),.err_code(code));
    always @(posedge clk)begin #1;
        if(pv)begin
            if(received>=2 || rgb!==expect_rgb[received] || px!==expect_x[received] || py!==expect_y[received])
                $fatal(1,"ERROR BMP pixel %0d rgb=%h x=%0d y=%0d",received,rgb,px,py);
            received=received+1;
        end
        if(done)done_count=done_count+1;
        if(err)errors=errors+1;
    end
    task u32(input integer offset,input [31:0] value);
        integer j;begin for(j=0;j<4;j=j+1)bytes[offset+j]=value[j*8+:8];end
    endtask
    task header(input integer w,input integer h,input integer depth,input integer off);
        begin
            for(i=0;i<128;i=i+1)bytes[i]=0;
            bytes[0]=8'h42;bytes[1]=8'h4d;u32(10,off);u32(14,40);u32(18,w);u32(22,h);bytes[26]=1;bytes[28]=depth;
        end
    endtask
    task send(input integer length);
        begin
            received=0;done_count=0;errors=0;
            @(negedge clk);start=1;@(negedge clk);start=0;
            for(i=0;i<length;i=i+1)begin data=bytes[i];valid=1;@(negedge clk);end
            valid=0;repeat(4)@(negedge clk);
        end
    endtask
    initial begin
        repeat(4)@(negedge clk);rst=1;
        header(1,2,24,58);bytes[58]=3;bytes[59]=2;bytes[60]=1;bytes[61]=8'hee;
        bytes[62]=6;bytes[63]=5;bytes[64]=4;bytes[65]=8'hdd;
        expect_rgb[0]=24'h010203;expect_rgb[1]=24'h040506;
        expect_x[0]=0;expect_x[1]=0;expect_y[0]=1;expect_y[1]=0;
        send(66);if(received!=2 || done_count!=1 || errors!=0)$fatal(1,"ERROR BMP24 completion");
        header(2,-1,32,54);bytes[54]=8'h11;bytes[55]=8'h22;bytes[56]=8'h33;bytes[57]=8'h44;
        bytes[58]=8'haa;bytes[59]=8'hbb;bytes[60]=8'hcc;bytes[61]=8'hdd;
        expect_rgb[0]=24'h332211;expect_rgb[1]=24'hccbbaa;expect_x[1]=1;expect_y[0]=0;
        send(62);if(received!=2 || done_count!=1 || errors!=0)$fatal(1,"ERROR BMP32 completion");
        header(2,1,24,54);u32(30,1);send(54);if(errors!=1 || code!==2)$fatal(1,"ERROR compression rejection");
        header(2,1,24,20);send(54);if(errors!=1 || code!==5)$fatal(1,"ERROR invalid offset rejection");
        header(0,1,24,54);send(54);if(errors!=1 || code!==4)$fatal(1,"ERROR zero width rejection");
        $display("PASS BMP: continuous bytes, 24/32 bpp, padding, orientation, offsets, malformed headers");$finish;
    end
    initial begin #100000;$fatal(1,"TIMEOUT BMP");end
endmodule

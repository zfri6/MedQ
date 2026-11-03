`timescale 1ns / 1ps
module tb_osd_renderer;
    reg clk=0;always #20 clk=~clk;
    reg rst=0,de=0,cfg_we=0;reg [9:0] x=0,y=20,cfg_addr=0;reg [31:0] cfg_wdata=0;
    reg [63:0] param=64'h00000f0000c88080;
    wire [13:0] font_addr;reg [31:0] font_data=0;
    wire [23:0] rgb;wire [7:0] alpha;
    integer n;
    osd_renderer dut(.clk(clk),.rst_n(rst),.x(x),.y(y),.de(de),.line_start(1'b0),.frame_start(1'b0),.frame_cnt(16'd0),
        .qstate(128'd0),.param(param),.cfg_we(cfg_we),.cfg_addr(cfg_addr),.cfg_wdata(cfg_wdata),
        .font_addr(font_addr),.font_dout(font_data),.osd_rgb(rgb),.osd_alpha(alpha));
    always @(posedge clk)font_data<=32'h80000000;
    task write_cfg(input [9:0] addr,input [31:0] data);
        begin @(negedge clk);cfg_addr=addr;cfg_wdata=data;cfg_we=1;@(negedge clk);cfg_we=0;end
    endtask
    task scan(input integer scale);
        begin
            @(negedge clk);de=0;repeat(3)@(negedge clk);
            for(n=0;n<32;n=n+1)begin
                @(negedge clk);x=n;de=1;
                @(posedge clk);#1;
                if(n>0)begin
                    if(n-1>=10 && n-1<10+scale)begin
                        if(alpha!==255 || rgb!==24'h123456)$fatal(1,"ERROR OSD position/color x=%0d",n-1);
                    end else if(alpha!==0)$fatal(1,"ERROR OSD transparent boundary x=%0d",n-1);
                end
            end
        end
    endtask
    initial begin
        repeat(4)@(negedge clk);rst=1;
        write_cfg(768,0);
        write_cfg(512,0);write_cfg(513,0);write_cfg(0,0);write_cfg(640,32'hff123456);
        write_cfg(512,1|(10<<1)|(20<<11)|(1<<23));scan(1);
        write_cfg(512,1|(10<<1)|(20<<11)|(1<<21)|(1<<23));scan(2);
        @(negedge clk);param[40]=0;repeat(4)@(negedge clk);if(alpha!==0)$fatal(1,"ERROR OSD disable");
        $display("PASS OSD: configured field, ROM latency, color, scaling, transparency, layer disable");$finish;
    end
    initial begin #100000;$fatal(1,"TIMEOUT OSD");end
endmodule

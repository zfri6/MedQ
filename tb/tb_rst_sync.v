`timescale 1ns / 1ps
module tb_rst_sync;
    reg clk=0;always #10 clk=~clk;
    reg ext=0,locked=0;
    wire rst;
    rst_sync #(.POR_CYCLES(8)) dut(.clk(clk),.ext_rst_n(ext),.pll_locked(locked),.rst_n_out(rst));
    initial begin
        repeat(3)@(negedge clk);ext=1;
        repeat(7)begin @(posedge clk);#1;if(rst!==0)$fatal(1,"ERROR POR early");end
        repeat(3)@(negedge clk);if(rst!==1)$fatal(1,"ERROR actual POR expiry");
        locked=1;repeat(2)@(negedge clk);
        #3;ext=0;#1;if(rst!==0)$fatal(1,"ERROR async ext reset while PLL locked");
        @(negedge clk);ext=1;
        @(posedge clk);#1;if(rst!==0)$fatal(1,"ERROR release first FF");
        @(posedge clk);#1;if(rst!==1)$fatal(1,"ERROR release second FF");
        @(negedge clk);locked=0;#1;if(rst!==0)$fatal(1,"ERROR unlock reset");
        $display("PASS reset: real POR expiry, external assertion, PLL loss, two-cycle release");$finish;
    end
    initial begin #10000;$fatal(1,"TIMEOUT reset");end
endmodule

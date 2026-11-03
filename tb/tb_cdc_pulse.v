`timescale 1ns / 1ps
module tb_cdc_pulse;
    reg src=0,dst=0,rst=0,pulse=0;always #7 src=~src;always #19 dst=~dst;
    wire busy,out_pulse;
    integer sent=0,received=0,n;
    reg prior=0;
    cdc_pulse dut(.src_clk(src),.src_rst_n(rst),.src_pulse(pulse),.src_busy(busy),.dst_clk(dst),.dst_rst_n(rst),.dst_pulse(out_pulse));
    always @(posedge dst)if(rst)begin
        if(out_pulse && prior)$fatal(1,"ERROR multi-cycle CDC event");
        if(out_pulse)received=received+1;
        prior=out_pulse;
    end
    initial begin
        repeat(5)@(negedge src);rst=1;
        for(n=0;n<12;n=n+1)begin
            wait(!busy);@(negedge src);pulse=1;sent=sent+1;@(negedge src);pulse=0;
            wait(busy);wait(!busy);
        end
        repeat(5)@(negedge dst);
        if(received!=sent)$fatal(1,"ERROR lost CDC toggle sent=%0d got=%0d",sent,received);
        $display("PASS pulse CDC: both toggle polarities, 12 acknowledged single-cycle events");$finish;
    end
    initial begin #10000;$fatal(1,"TIMEOUT CDC pulse");end
endmodule

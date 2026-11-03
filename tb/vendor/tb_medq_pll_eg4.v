`timescale 1ns / 1ps
// Real generated wrapper and original EG4 PLL/glbl models, no SIMULATION.
module tb_medq_pll_eg4;
    reg refclk=0,reset=1;
    always #10 refclk=~refclk;
    wire lock,ser,pix,mem;
    medq_pll dut(refclk,reset,lock,ser,pix,mem);
    wire memory_lock,memory_clk,memory_shift,system_clk;
    sys_pll memory_dut(refclk,reset,memory_lock,system_clk,memory_clk,memory_shift);
    realtime last_memory=0,last_shift=0;
    integer memory_count=0,shift_count=0;
    always @(posedge memory_clk)if(memory_lock && !reset)begin
        if(last_memory!=0)begin
            if($realtime-last_memory<19.99 || $realtime-last_memory>20.01)$fatal(1,"ERROR memory PLL period");
            if(system_clk!==1'b1)$fatal(1,"ERROR system/memory PLL phase");
            memory_count=memory_count+1;
        end
        last_memory=$realtime;
    end
    always @(posedge memory_shift)if(memory_lock && !reset && last_memory!=0)begin
        if($realtime-last_memory<7.99 || $realtime-last_memory>8.01)$fatal(1,"ERROR memory PLL phase measured=%0.3f ns",$realtime-last_memory);
        shift_count=shift_count+1;
    end
    realtime last_ser=0,last_pix=0,last_mem=0,period;
    integer ser_count=0,pix_count=0,mem_count=0,epoch;
    always @(posedge ser) if(lock && !reset) begin
        if(last_ser!=0) begin
            period=$realtime-last_ser;
            if(period<7.99 || period>8.01) $fatal(1,"ERROR real PLL serial period %f",period);
            ser_count=ser_count+1;
        end
        last_ser=$realtime;
    end
    always @(posedge pix) if(lock && !reset) begin
        if(last_pix!=0) begin
            period=$realtime-last_pix;
            if(period<39.99 || period>40.01) $fatal(1,"ERROR real PLL pixel period %f",period);
            pix_count=pix_count+1;
        end
        last_pix=$realtime;
    end
    always @(posedge mem) if(lock && !reset) begin
        if(last_mem!=0) begin
            period=$realtime-last_mem;
            if(period<9.99 || period>10.01) $fatal(1,"ERROR real PLL memory period %f",period);
            mem_count=mem_count+1;
        end
        last_mem=$realtime;
    end
    initial begin
        #200;
        for(epoch=0;epoch<2;epoch=epoch+1) begin
            reset=0;
            wait(lock===1'b1);
            wait(ser_count>=100 && pix_count>=100 && mem_count>=100 && memory_count>=100 && shift_count>=100);
            #3;reset=1;
            #100;
            if(lock!==0) $fatal(1,"ERROR real PLL lock did not clear on reset");
            if(memory_lock!==0)$fatal(1,"ERROR memory PLL lock reset");
            last_ser=0;last_pix=0;last_mem=0;
            ser_count=0;pix_count=0;mem_count=0;
            last_memory=0;memory_count=0;shift_count=0;
        end
        $display("PASS EG4 PLL: video 125/25 MHz, system/memory 50 MHz, SDRAM +8ns/144deg, lock/reset/relock, 100 measured periods per output per epoch");
        $finish;
    end
    initial begin #200000;$fatal(1,"TIMEOUT real EG4 PLL lock/frequency");end
endmodule

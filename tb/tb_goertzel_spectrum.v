`timescale 1ns / 1ps
module tb_goertzel_spectrum;
    reg clk=0;always #20 clk=~clk;
    reg rst=0,stb=0;reg [15:0] sample=0;
    wire valid;wire [3:0] index;wire [7:0] mag,level;
    goertzel_spectrum dut(clk,rst,stb,sample,valid,index,mag,level);
    reg [15:0] samples[0:3071];reg [7:0] expected[0:191];
    integer results=0,level_ref=0,block,n,ticks=0,last_valid=-1;
    task push;
        input [15:0] value;
        begin
            @(negedge clk);sample=value;stb=1;
            @(negedge clk);stb=0;
            if(block==4 && n==255)begin
                // Deliberate extra strobes during recurrence and power output
                // must be ignored; the independent block result stays intact.
                repeat(8)@(negedge clk);sample=16'hdead;stb=1;
                @(negedge clk);stb=0;
                repeat(40)@(negedge clk);sample=16'h1234;stb=1;
                @(negedge clk);stb=0;
                repeat(468)@(negedge clk);
            end else repeat(518)@(negedge clk);
        end
    endtask
    always @(posedge clk)begin
        ticks=ticks+1;
        if(!rst)level_ref=0;
        else if(valid)begin
            if(mag>level_ref)level_ref=(7*mag+level_ref)/8;
            else if(level_ref!=0)level_ref=level_ref-(level_ref>=64 ? level_ref/64 : 1);
        end
        #1;
        if(level!==8'(level_ref))$fatal(1,"ERROR spectrum envelope result=%0d",results);
        if(rst && (^{valid,index,mag,level})===1'bx)$fatal(1,"ERROR spectrum unknown output");
        if(rst && valid)begin
            if(results>=192 || index!==4'(results%16) || mag!==expected[results])
                $fatal(1,"ERROR spectrum bin=%0d index=%0d expected=%0d got=%0d",results,index,expected[results],mag);
            if(index!=0 && ticks-last_valid!=8)$fatal(1,"ERROR spectrum TDM result spacing");
            results=results+1;last_valid=ticks;
        end
    end
    initial begin
        $readmemh("medq_spectrum_samples.hex",samples);$readmemh("medq_spectrum_expected.hex",expected);
        repeat(4)@(negedge clk);rst=1;
        for(block=0;block<12;block=block+1)begin
            if(block==3)begin
                // Abandon a partial block: no result may escape after reset.
                for(n=0;n<32;n=n+1)push(16'(n*777));
                @(negedge clk);rst=0;repeat(3)@(negedge clk);rst=1;
            end
            for(n=0;n<256;n=n+1)push(samples[block*256+n]);
            if(results!=(block+1)*16)$fatal(1,"ERROR spectrum block count %0d",block);
        end
        repeat(200)@(negedge clk);
        if(results!=192)$fatal(1,"ERROR spectrum missing/extra output");
        $display("PASS shared Goertzel: 12 blocks/192 bins vs independent fixed-point reference; silence, full-scale DC, tones, noise, reset, busy strobes, TDM and envelope");$finish;
    end
    initial begin #100000000;$fatal(1,"TIMEOUT Goertzel");end
endmodule

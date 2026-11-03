`timescale 1ns / 1ps
module tb_spectrum_render_equivalence;
    reg clk=0;always #20 clk=~clk;
    reg rst=0,de=1,frame_start=0,bin_valid=0,stb=0;
    reg [9:0] x=0,y=0;reg [3:0] mode=0,bin_idx=0;
    reg [7:0] bin_mag=0,level=0;reg [15:0] sample=0;
    wire [23:0] actual,expected;wire [7:0] aa,ea;
    spectrum_render dut(clk,rst,x,y,de,frame_start,mode,bin_valid,bin_idx,bin_mag,level,sample,stb,actual,aa);
    spectrum_render_reference golden(clk,rst,x,y,de,frame_start,mode,bin_valid,bin_idx,bin_mag,level,sample,stb,expected,ea);
    wire signed [16:0] old_offset={1'b0,sample}-17'd32768;
    wire signed [9:0] old_projected=(old_offset*17'd40)>>>16;
    wire [9:0] old_y=10'd432+old_projected;
    integer i;
    initial begin
        repeat(3)@(negedge clk);rst=1;
        for(i=0;i<65536;i=i+1)begin
            @(negedge clk);
            rst=i!=32768;sample=i[15:0];stb=1;
            x=440+i%208;y=384+(i/208)%96;mode=(i>>12)&3;
            bin_valid=(i%16)==0;bin_idx=(i>>4)&15;bin_mag=i[7:0]^8'ha5;level=i[7:0];frame_start=(i%1000)==0;
            #1;if(dut.sample_y(sample)!==old_y)$fatal(1,"ERROR waveform projection input=%0d",i);
            @(posedge clk);#1;
            if(actual!==expected || aa!==ea)$fatal(1,"ERROR spectrum output cycle=%0d mode=%0d",i,mode);
        end
        $display("PASS waveform compaction: all 65536 samples, ring wrap, all modes, reset; exact frozen-RTL output");$finish;
    end
    initial begin #4000000;$fatal(1,"TIMEOUT spectrum equivalence");end
endmodule

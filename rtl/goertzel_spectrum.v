`timescale 1ns / 1ps
// 16-bin fixed-point Goertzel, 48 kHz input / 25 MHz processing clock.
// One registered 32x32 multiplier is shared by recurrence and energy phases.
// Physical DSP count is determined by TD (one arithmetic operator can use
// several device DSP blocks). No parallel per-bin multiplier array.
module goertzel_spectrum #(
    parameter integer BINS=16,
    parameter integer BLOCK_N=256
)(
    input wire clk,rst_n,stb,
    input wire [15:0] sample,
    output reg bin_valid,
    output reg [3:0] bin_idx,
    output reg [7:0] bin_mag,
    output wire [7:0] level
);
    // Q2.14: round(2*cos(2*pi*(k+1)/256)*16384), fixed 256-point grid.
    function [15:0] get_coef;
        input [3:0] k;
        begin
            case(k)
                0:get_coef=32758;1:get_coef=32729;2:get_coef=32679;3:get_coef=32610;
                4:get_coef=32522;5:get_coef=32413;6:get_coef=32286;7:get_coef=32138;
                8:get_coef=31972;9:get_coef=31786;10:get_coef=31581;11:get_coef=31357;
                12:get_coef=31114;13:get_coef=30853;14:get_coef=30572;default:get_coef=30274;
            endcase
        end
    endfunction
    localparam IDLE=0,REC_ISSUE=1,REC_COMMIT=2,SQ1_ISSUE=3,SQ1_CAPTURE=4,
               SQ2_ISSUE=5,SQ2_CAPTURE=6,COEF_ISSUE=7,COEF_CAPTURE=8,
               CROSS_ISSUE=9,CROSS_COMMIT=10;
    reg [3:0] state,bin_index;
    reg [8:0] sample_count;
    reg last_sample;
    reg signed [31:0] s1[0:15],s2[0:15];
    reg signed [31:0] sample_hold,coef_s2;
    reg signed [31:0] ma,mb;
    reg signed [63:0] product,square1,square2;
    reg [15:0] state_valid;
    reg signed [31:0] q1,q2,forward1,forward2;
    reg forwarded;
    wire advance=state==REC_COMMIT || state==CROSS_COMMIT;
    wire [3:0] read_index=advance ? (bin_index==BINS-1 ? 4'd0 : bin_index+4'd1) : bin_index;
    wire signed [31:0] value1=state_valid[bin_index] ? (forwarded ? forward1 : q1) : 32'sd0;
    wire signed [31:0] value2=state_valid[bin_index] ? (forwarded ? forward2 : q2) : 32'sd0;
    wire [15:0] coefficient=get_coef(bin_index);
    always @* begin
        ma=0;mb=0;
        case(state)
            REC_ISSUE:begin ma=$signed({{16{coefficient[15]}},coefficient});mb=value1;end
            SQ1_ISSUE:begin ma=value1;mb=value1;end
            SQ2_ISSUE:begin ma=value2;mb=value2;end
            COEF_ISSUE:begin ma=$signed({{16{coefficient[15]}},coefficient});mb=value2;end
            CROSS_ISSUE:begin ma=value1;mb=coef_s2;end
            default:begin end
        endcase
    end
    always @(posedge clk) product<=ma*mb;
    wire signed [63:0] recurrence=$signed({{32{sample_hold[31]}},sample_hold})+
                                  (product>>>14)-$signed({{32{value2[31]}},value2});
    wire signed [65:0] energy={{2{square1[63]}},square1}+{{2{square2[63]}},square2}-{{2{product[63]}},product};
    // Normalize energy by 2^16, then floor(log2) * 8, saturating at 248.
    // This covers full-scale 16-bit input without truncating power to 32 bits.
    function [7:0] log_energy;
        input [65:0] value;
        integer bit_index;
        begin
            log_energy=0;
            if(!value[65])begin
                for(bit_index=16;bit_index<65;bit_index=bit_index+1)
                    if(value[bit_index])log_energy=bit_index>=47 ? 8'd248 : (bit_index-16)*8;
            end
        end
    endfunction
    always @(posedge clk)begin
        q1<=s1[read_index];q2<=s2[read_index];
        if(rst_n && state==REC_COMMIT)begin
            s1[bin_index]<=recurrence[31:0];s2[bin_index]<=value1;
        end
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin state_valid<=0;forwarded<=0;forward1<=0;forward2<=0;end
        else begin
            forwarded<=state==REC_COMMIT && read_index==bin_index;
            forward1<=recurrence[31:0];forward2<=value1;
            if(state==REC_COMMIT)state_valid[bin_index]<=1;
            if(state==CROSS_COMMIT)state_valid[bin_index]<=0;
        end
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;bin_index<=0;sample_count<=0;last_sample<=0;
            sample_hold<=0;coef_s2<=0;square1<=0;square2<=0;
            bin_valid<=0;bin_idx<=0;bin_mag<=0;
        end else begin
            bin_valid<=0;
            case(state)
                IDLE:if(stb)begin
                    sample_hold<={{16{sample[15]}},sample};
                    last_sample<=sample_count==BLOCK_N-1;
                    bin_index<=0;state<=REC_ISSUE;
                end
                REC_ISSUE:state<=REC_COMMIT;
                REC_COMMIT:begin
                    if(bin_index==BINS-1)begin
                        bin_index<=0;
                        if(last_sample)begin sample_count<=0;state<=SQ1_ISSUE;end
                        else begin sample_count<=sample_count+1'b1;state<=IDLE;end
                    end else begin bin_index<=bin_index+1'b1;state<=REC_ISSUE;end
                end
                SQ1_ISSUE:state<=SQ1_CAPTURE;
                SQ1_CAPTURE:begin square1<=product;state<=SQ2_ISSUE;end
                SQ2_ISSUE:state<=SQ2_CAPTURE;
                SQ2_CAPTURE:begin square2<=product;state<=COEF_ISSUE;end
                COEF_ISSUE:state<=COEF_CAPTURE;
                COEF_CAPTURE:begin coef_s2<=product>>>14;state<=CROSS_ISSUE;end
                CROSS_ISSUE:state<=CROSS_COMMIT;
                CROSS_COMMIT:begin
                    bin_valid<=1;bin_idx<=bin_index;bin_mag<=log_energy(energy);
                    // Each completed block starts a fresh Goertzel window.
                    if(bin_index==BINS-1)begin bin_index<=0;state<=IDLE;end
                    else begin bin_index<=bin_index+1'b1;state<=SQ1_ISSUE;end
                end
                default:state<=IDLE;
            endcase
        end
    end
    reg [7:0] level_reg;
    wire [10:0] attack_sum={bin_mag,3'b000}-{3'b000,bin_mag}+{3'b000,level_reg};
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)level_reg<=0;
        else if(bin_valid)begin
            if(bin_mag>level_reg)level_reg<=attack_sum[10:3];
            else if(level_reg!=0)level_reg<=level_reg-(level_reg>=64 ? (level_reg>>6) : 8'd1);
        end
    end
    assign level=level_reg;
endmodule

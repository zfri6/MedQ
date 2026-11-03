`timescale 1ns / 1ps
module tb_video_pipeline;
    reg clk=0;always #20 clk=~clk;
    reg rst=0;
    wire de,hs,vs,fs,ls;wire [9:0] x,y;wire [15:0] frame_count;
    video_timing timing(.clk(clk),.rst_n(rst),.de(de),.hs(hs),.vs(vs),.x(x),.y(y),.frame_start(fs),.line_start(ls),.frame_cnt(frame_count));
    reg cde=0,chs=1,cvs=1;reg [23:0] base=0,text_rgb=0,spec_rgb=0;
    reg [7:0] text_alpha=0,spec_alpha=0;reg [63:0] param=64'h8080;
    wire ode,ohs,ovs;wire [23:0] rgb;
    osd_compositor compositor(.clk(clk),.rst_n(rst),.de_in(cde),.hs_in(chs),.vs_in(cvs),.rgb_base(base),
        .osd_rgb(text_rgb),.osd_alpha(text_alpha),.spec_rgb(spec_rgb),.spec_alpha(spec_alpha),.param(param),
        .de_out(ode),.hs_out(ohs),.vs_out(ovs),.rgb_out(rgb));
    task check_color(input [23:0] b,input [23:0] t,input [7:0] a,input [23:0] expected);
        begin @(negedge clk);base=b;text_rgb=t;text_alpha=a;cde=1;chs=0;cvs=1;
            @(posedge clk);#1;if(rgb!==expected || {ode,ohs,ovs}!==3'b101)$fatal(1,"ERROR compositor expected %h got %h",expected,rgb);
        end
    endtask
    integer cycle=0,last_line=0,last_frame=0,frames=0,active=0,hs_low=0,vs_low=0;
    reg counting=0;
    always @(posedge clk) if(rst)begin
        cycle=cycle+1;
        if(fs)begin
            if(last_frame!=0 && cycle-last_frame!=420000)$fatal(1,"ERROR frame period");
            last_frame=cycle;
            if(counting)begin
                if(active!=307200 || hs_low!=50400 || vs_low!=1600)$fatal(1,"ERROR frame counts de=%0d hs=%0d vs=%0d",active,hs_low,vs_low);
                frames=frames+1;
            end
            active=0;hs_low=0;vs_low=0;counting=1;
        end
        if(ls)begin if(last_line!=0 && cycle-last_line!=800)$fatal(1,"ERROR line period");last_line=cycle;end
        if(counting)begin if(de)active=active+1;if(!hs)hs_low=hs_low+1;if(!vs)vs_low=vs_low+1;end
        #1;if(de && (x>639 || y>479))$fatal(1,"ERROR active coordinates");
    end
    initial begin
        repeat(5)@(negedge clk);rst=1;
        check_color(24'h123456,24'hffffff,0,24'h123456);
        check_color(24'hffffff,24'h102030,255,24'h102030);
        check_color(24'h000000,24'hffffff,128,24'h808080);
        @(negedge clk);param[7:0]=0;text_alpha=0;
        check_color(24'h102030,0,0,0);
        @(negedge clk);param[7:0]=255;
        check_color(24'hf0f0f0,0,0,24'hffffff);
        wait(frames==2);
        $display("PASS video: two full 800x525 frames, 640x480 active pixels, HS/VS widths, exact alpha and saturation");$finish;
    end
    initial begin #40000000;$fatal(1,"TIMEOUT video");end
endmodule

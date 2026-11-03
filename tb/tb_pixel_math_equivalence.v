`timescale 1ns / 1ps
// Golden functions are frozen pre-optimization RTL, not the new implementation.
module tb_pixel_math_equivalence;
    osd_renderer dut(.clk(1'b0),.rst_n(1'b0),.x(10'd0),.y(10'd0),.de(1'b0),.line_start(1'b0),.frame_start(1'b0),
        .frame_cnt(16'd0),.qstate(128'd0),.param(64'd0),.cfg_we(1'b0),.cfg_addr(10'd0),.cfg_wdata(32'd0),.font_addr(),.font_dout(32'd0),.osd_rgb(),.osd_alpha());
    osd_renderer_reference golden(.clk(1'b0),.rst_n(1'b0),.x(10'd0),.y(10'd0),.de(1'b0),.line_start(1'b0),.frame_start(1'b0),
        .frame_cnt(16'd0),.qstate(128'd0),.param(64'd0),.cfg_we(1'b0),.cfg_addr(10'd0),.cfg_wdata(32'd0),.font_addr(),.font_dout(32'd0),.osd_rgb(),.osd_alpha());
    osd_compositor comp(.clk(1'b0),.rst_n(1'b0),.de_in(1'b0),.hs_in(1'b0),.vs_in(1'b0),.rgb_base(24'd0),.osd_rgb(24'd0),.osd_alpha(8'd0),
        .spec_rgb(24'd0),.spec_alpha(8'd0),.param(64'd0),.de_out(),.hs_out(),.vs_out(),.rgb_out());
    osd_compositor_reference comp_ref(.clk(1'b0),.rst_n(1'b0),.de_in(1'b0),.hs_in(1'b0),.vs_in(1'b0),.rgb_base(24'd0),.osd_rgb(24'd0),.osd_alpha(8'd0),
        .spec_rgb(24'd0),.spec_alpha(8'd0),.param(64'd0),.de_out(),.hs_out(),.vs_out(),.rgb_out());
    integer v,c,o,b,a,f,k,contrast,brightness,checks=0;
    reg [23:0] bg,fg;
    initial begin
        for(v=0;v<=65152;v=v+1)begin
            if(dut.medq_div255(v[15:0])!==8'(v/255))$fatal(1,"ERROR exact /255 input=%0d",v);
            checks=checks+1;
        end
        for(c=0;c<4;c=c+1)for(o=0;o<256;o=o+1)for(b=0;b<256;b=b+1)begin
            bg={8'(b),8'(255-b),8'(b^165)};fg={8'(b*73),8'(b+57),8'(255-b)};
            if(dut.covered(bg,fg,c[1:0],o[7:0])!==golden.covered(bg,fg,c[1:0],o[7:0]))
                $fatal(1,"ERROR covered coverage=%0d opacity=%0d base=%0d",c,o,b);
            checks=checks+1;
        end
        for(b=0;b<256;b=b+1)for(a=0;a<256;a=a+1)for(k=0;k<3;k=k+1)begin
            f=k==0 ? 0 : k==1 ? 255 : 255-b;
            bg={3{b[7:0]}};fg={3{f[7:0]}};
            if(comp.blend(bg,fg,a[7:0])!==comp_ref.blend(bg,fg,a[7:0]))$fatal(1,"ERROR blend b=%0d f=%0d a=%0d",b,f,a);
            checks=checks+1;
        end
        for(b=0;b<256;b=b+1)for(contrast=0;contrast<256;contrast=contrast+1)for(k=0;k<6;k=k+1)begin
            case(k)0:brightness=0;1:brightness=1;2:brightness=127;3:brightness=128;4:brightness=254;default:brightness=255;endcase
            if(comp.bc(b[7:0],brightness[7:0],contrast[7:0])!==comp_ref.bc(b[7:0],brightness[7:0],contrast[7:0]))
                $fatal(1,"ERROR BC p=%0d b=%0d c=%0d",b,brightness,contrast);
            checks=checks+1;
        end
        $display("PASS exact pixel math: %0d frozen-reference comparisons and exhaustive /255 range",checks);$finish;
    end
endmodule

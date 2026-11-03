`timescale 1ns / 1ps
// Real OSD + synchronous font ROM. Only input snapshots/frame events are driven.
module tb_medq_ui;
    reg clk=0;always #20 clk=~clk;
    reg rst=0,de=0,fs=0;
    reg [9:0] x=0,y=0;
    reg [127:0] state=0;
    reg [7:0] service_status=8'hf1;
    reg [63:0] param=64'h00000f0000c88080;
    reg [31:0] fake_word=0;
    reg use_fake=0;
    wire [13:0] addr;
    wire [31:0] data;
    wire [23:0] rgb;
    wire [7:0] alpha;
    font_rom rom(.clk(clk),.addr(addr),.dout(data));
    osd_renderer #(.LIVE_STATUS(1)) dut(.clk(clk),.rst_n(rst),.x(x),.y(y),.de(de),.line_start(1'b0),.frame_start(fs),.frame_cnt(16'd0),
        .qstate(state),.param(param),.service_status(service_status),.cfg_we(1'b0),.cfg_addr(10'd0),.cfg_wdata(32'd0),
        .font_addr(addr),.font_dout(use_fake ? fake_word : data),.osd_rgb(rgb),.osd_alpha(alpha));
    integer checked=0;
    always @(posedge clk) if(rst && de)begin
        if(addr<8192 || addr>16383)$fatal(1,"ERROR UI atlas address %0d",addr);
        if((^{addr,rgb,alpha})===1'bx)$fatal(1,"ERROR unknown UI output");
    end
    task frame;
        begin @(negedge clk);de=0;fs=1;@(negedge clk);fs=0;end
    endtask
    task pixel(input integer px,py,input [23:0] expected);
        begin
            @(negedge clk);x=px;y=py;de=1;
            repeat(2)@(posedge clk);#1;
            if(rgb!==expected || alpha!==255)$fatal(1,"ERROR UI pixel (%0d,%0d) expected=%h got=%h alpha=%0d",px,py,expected,rgb,alpha);
            checked=checked+1;
        end
    endtask
    task capture(input integer index);
        integer fd,px,py;
        reg [23:0] saved;
        begin
            fd=$fopen($sformatf("ui_frame_%02d.ppm",index),"wb");
            if(fd==0)$fatal(1,"ERROR opening UI capture");
            $fwrite(fd,"P6\n640 480\n255\n");
            @(negedge clk);de=0;repeat(3)@(negedge clk);
            for(py=0;py<480;py=py+1)begin
                for(px=0;px<641;px=px+1)begin
                    x=px<640 ? px : 0;y=py;de=px<640;
                    @(posedge clk);#1;
                    if(px>0)begin
                        if(alpha!==255)$fatal(1,"ERROR UI raster gap x=%0d y=%0d",px-1,py);
                        $fwrite(fd,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);
                    end
                    @(negedge clk);
                end
            end
            de=0;$fclose(fd);
        end
    endtask
    integer i,previous_ease;
    initial begin
        repeat(4)@(negedge clk);rst=1;frame;
        pixel(0,100,24'hecf3f7);pixel(0,20,24'hffffff);
        pixel(30,160,24'hffffff);pixel(24,20,24'hffffff);
        pixel(42,40,24'hffffff);pixel(30,42,24'h078a86);
        use_fake=1;fake_word=0;pixel(50,230,24'hffffff);
        fake_word=32'h55555555;pixel(50,230,24'hb1bbc3);
        fake_word=32'haaaaaaaa;pixel(50,230,24'h647686);
        fake_word=32'hffffffff;pixel(50,230,24'h16324a);use_fake=0;
        // Snapshot stays unchanged through a scan, including an arrival update.
        state[23:16]=8'h41;state[15:0]=16'h0128;state[27:24]=3;state[43:36]=12;
        repeat(20)@(negedge clk);
        if(dut.u_scene.display_state!==0)$fatal(1,"ERROR UI state changed mid-frame");
        service_status=8'h32;
        if(dut.u_scene.display_service!==8'hf1)$fatal(1,"ERROR service changed midframe");
        capture(0);service_status=8'hf1;frame;
        if(dut.u_scene.display_state!==state || dut.u_scene.call_age!==0)$fatal(1,"ERROR frame snapshot/call start");
        capture(1);previous_ease=0;
        for(i=1;i<=16;i=i+1)begin
            frame;
            if(dut.u_scene.ease<previous_ease)$fatal(1,"ERROR nonmonotonic easing");
            previous_ease=dut.u_scene.ease;
            capture(i+1);
        end
        if(previous_ease!=255)$fatal(1,"ERROR UI easing endpoint");
        state[31:28]=2;state[33]=1;frame;
        if(dut.u_scene.call_age!=0)$fatal(1,"ERROR recall animation did not restart");
        for(i=0;i<16;i=i+1)frame;capture(18);
        state[23:16]=8'h50;state[15:0]=16'h0086;state[27:24]=2;state[32]=1;state[33]=0;state[34]=1;state[43:36]=255;
        frame;for(i=0;i<16;i=i+1)frame;capture(19);
        for(i=0;i<125;i=i+1)begin
            frame;
            if(dut.u_scene.breath_phase>119)$fatal(1,"ERROR breathing wrap");
        end
        service_status=8'hf2;frame;capture(20);
        if(dut.u_scene.display_service!==8'hf2)$fatal(1,"ERROR basic status snapshot");
        service_status=8'hf3;frame;capture(21);
        state[35]=1;service_status=8'hf1;frame;
        if(dut.u_scene.lift!=0 || dut.u_scene.ease!=255)$fatal(1,"ERROR reduced motion");
        capture(22);repeat(30)frame;capture(23);
        state[35]=0;service_status=8'h80;frame;capture(24);
        service_status=8'hf9;frame;capture(25);
        @(negedge clk);param[40]=0;
        repeat(3)@(posedge clk);#1;if(alpha!==0)$fatal(1,"ERROR layer disable");
        $display("PASS UI: frame-atomic snapshots, 16-frame monotonic ease-out, recall retrigger, 120-frame breathing, four coverage levels, raster/ROM alignment, 26 captures including service modes and reduced motion, %0d exact pixels",checked);$finish;
    end
    initial begin #400000000;$fatal(1,"TIMEOUT UI");end
endmodule

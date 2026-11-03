`timescale 1ns / 1ps
module tb_asset_loader;
    reg clk_sys=0,clk_mem=0;always #10 clk_sys=~clk_sys;always #5 clk_mem=~clk_mem;
    reg rst=0,load_req=0;reg [1:0] fb_sel=0;
    wire load_done,load_err,assets_ok,load_busy;
    wire [5:0] img_count;wire [6:0] pcm_count;
    wire [3:0] progress;
    reg [5:0] clip_sel=0;wire [21:0] clip_base,clip_samples;
    wire sclk,mosi,miso,cs_n,req,ready,we,wv,wr,rv,rr,init_done;
    wire [21:0] addr;wire [8:0] len;wire [31:0] wd,rd;
    asset_loader #(.SD_INIT_DIV(0),.SD_DATA_DIV(0),.SD_RESPONSE_LIMIT(8)) dut(
        .clk_sys(clk_sys),.rst_n_sys(rst),.clk_mem(clk_mem),.rst_n_mem(rst),
        .load_req(load_req),.img_sel(5'd0),.fb_sel(fb_sel),.load_busy(load_busy),.load_done(load_done),.load_err(load_err),
        .img_count(img_count),.pcm_count(pcm_count),.assets_ok(assets_ok),.progress(progress),
        .clip_sel(clip_sel),.clip_base(clip_base),.clip_samples(clip_samples),
        .sd_spi_sclk(sclk),.sd_spi_mosi(mosi),.sd_spi_miso(miso),.sd_spi_cs_n(cs_n),
        .wr_req_valid(req),.wr_req_ready(ready),.wr_req_addr(addr),.wr_req_we(we),.wr_req_len(len),
        .wr_wr_valid(wv),.wr_wr_ready(wr),.wr_wr_data(wd),.wr_rd_valid(rv),.wr_rd_ready(rr),.wr_rd_data(rd));
    sd_card_model card(.sclk(sclk),.mosi(mosi),.miso(miso),.cs_n(cs_n));
    sdram_ctrl_wrap memory(.clk(clk_mem),.rst_n(rst),.mem_req_valid(req),.mem_req_ready(ready),
        .mem_req_addr(addr),.mem_req_we(we),.mem_req_len(len),.mem_wr_valid(wv),.mem_wr_ready(wr),.mem_wr_data(wd),
        .mem_rd_valid(rv),.mem_rd_ready(rr),.mem_rd_data(rd),.init_done(init_done));
    integer x,y,index,fx,fy,top_r,bottom_g,r,g,b;
    reg [31:0] expected;
    initial $display("INFO SD div=%0d/%0d",dut.u_sd_card_ctrl.INIT_CLK_DIV,dut.u_sd_card_ctrl.DATA_CLK_DIV);
    always @(posedge clk_sys) if(dut.mount_err)
        $display("ERROR [mount] bytes=%0d b0=%h signature=%h card_ready=%b reads=%0d commands=%0d",dut.u_fat32.byte_count,dut.u_fat32.sector0[0],dut.u_fat32.boot_signature,dut.sd_ready,card.read_count,card.command_count);
    always @(posedge clk_sys) if(rst && dut.state==6)
        $display("INFO select pcm=%0d/%0d size=%0d pool=%h images=%0d",dut.pcm_index,pcm_count,dut.aud_size_r[dut.pcm_index],dut.pool_pointer,img_count);
    always @(posedge clk_sys) if(rst && (dut.read_err || dut.bp_error || dut.pixel_count>15 || (dut.word_push && !dut.word_ready && !dut.image_mode)))
        $display("ERROR [asset_cause] state=%0d image=%b pcm=%0d FATerr=%b BMPerr=%b code=%d pixels=%0d fifo=%0d",dut.state,dut.image_mode,dut.pcm_index,dut.read_err,dut.bp_error,dut.u_bmp.err_code,dut.pixel_count,dut.word_wlevel);
    always @(posedge clk_sys) if(rst && load_err)$fatal(1,"ERROR loader state=%0d FAT=%0d SD=%0d pixel_count=%0d",dut.state,dut.u_fat32.state,dut.u_sd_card_ctrl.state,dut.pixel_count);
    initial begin
        repeat(8)@(negedge clk_sys);rst=1;
        wait(load_done);#1;
        if(!assets_ok || img_count!==1 || pcm_count!==54 || progress!==15)$fatal(1,"ERROR asset counts");
        for(index=0;index<54;index=index+1)begin
            clip_sel=index;repeat(2)@(negedge clk_sys);#1;
            if(clip_samples!==3 || clip_base!==(22'he1000+2*index))$fatal(1,"ERROR clip query %0d",index);
            expected={16'(-200-index),16'(100+index)};
            if(memory.sim_mem[clip_base]!==expected || memory.sim_mem[clip_base+1]!==32'(300+index))$fatal(1,"ERROR PCM preload %0d",index);
        end
        for(y=0;y<480;y=y+1)for(x=0;x<640;x=x+1)begin
            fx=65536*x/639;fy=65536*y/479;
            top_r=(255*fx+32768)>>16;bottom_g=(255*(65536-fx)+32768)>>16;
            r=(top_r*(65536-fy)+32768)>>16;g=(bottom_g*fy+32768)>>16;b=(top_r*fy+32768)>>16;
            expected={8'd0,r[7:0],g[7:0],b[7:0]};
            if(memory.sim_mem[y*640+x]!==expected)$fatal(1,"ERROR BMP/scaler/write x=%0d y=%0d exp=%h got=%h",x,y,expected,memory.sim_mem[y*640+x]);
        end
        $display("INFO full 307200-pixel framebuffer and all 54 PCM clips matched");
        @(negedge clk_sys);fb_sel=1;load_req=1;@(negedge clk_sys);load_req=0;
        wait(load_busy);wait(load_done);#1;
        if(memory.sim_mem[22'h04b27f]!==32'h00ff0000 || memory.sim_mem[22'h095d80]!==32'h0000ff00 || memory.sim_mem[22'h095fff]!==32'h000000ff)
            $fatal(1,"ERROR framebuffer B reload/addressing");
        if(card.read_count<25)$fatal(1,"ERROR too few SD transactions");
        $display("PASS assets: SDHC SPI initialization, FAT32 two-sector root, PCM preload, bilinear 2x2 to VGA, reload FB1");$finish;
    end
    initial begin #200000000;$fatal(1,"TIMEOUT assets state=%0d FAT=%0d SD=%0d fifo=%0d pix=%0d scaler=%0d",dut.state,dut.u_fat32.state,dut.u_sd_card_ctrl.state,dut.word_rlevel,dut.pixel_count,dut.g_legacy_scaler.u_scaler.state);end
endmodule

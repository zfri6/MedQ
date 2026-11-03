`timescale 1ns / 1ps
module tb_patient_pcm_path;
    reg clk_sys=0,clk_mem=0;always #10 clk_sys=~clk_sys;always #5 clk_mem=~clk_mem;
    reg rst=0,load_req=0;reg [1:0] fb_sel=0;
    wire load_done,load_err,assets_ok,load_busy;
    wire [5:0] img_count;wire [6:0] pcm_count;
    wire [3:0] progress;
    wire [5:0] clip_sel;wire [21:0] clip_base,clip_samples;
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
    wire preq,pbusy,pdone,pabort,announcing;wire [21:0] pbase,psamples;
    wire ar,ardy,awe,awv,arr,arv;wire [21:0] aa;wire [8:0] al;wire [31:0] awd,ard;
    wire [15:0] sample;wire underrun;reg stb=0;integer div=0;
    always @(posedge clk_sys)begin div<=div==15 ? 0 : div+1;stb<=div==15;end
    reg [1:0] requests=0,returns=0;reg [15:0] tickets=0;reg [127:0] q=0;
    wire [1:0] grant,started;
    medq_dual_announcer announcer(.clk(clk_sys),.rst_n(rst),.running(2'b11),.voice_ready(assets_ok),.request(requests),.doctor_event(2'b00),
     .request_ticket(tickets),.request_return(returns),.qstate(q),.grant(grant),.announcement_start(started),.clip_sel(clip_sel),.clip_base(clip_base),.clip_samples(clip_samples),
     .play_req(preq),.play_base(pbase),.play_samples(psamples),.play_busy(pbusy),.play_done(pdone),.pcm_abort(pabort),.fallback_tone(),.announcing(announcing),.active_room(),.active_ticket());
    audio_pcm_player #(.CONTROLLED(1)) player(.clk_pix(clk_sys),.rst_n_pix(rst),.clk_mem(clk_mem),.rst_n_mem(rst),.stb(stb),.run_enable(1'b1),.abort_play(pabort),
     .play_req(preq),.play_base(pbase),.play_samples(psamples),.play_busy(pbusy),.play_done(pdone),.sample(sample),.underrun(underrun),
     .aud_req_valid(ar),.aud_req_ready(ardy),.aud_req_addr(aa),.aud_req_we(awe),.aud_req_len(al),.aud_wr_valid(awv),.aud_wr_ready(1'b0),.aud_wr_data(awd),
     .aud_rd_valid(arv),.aud_rd_ready(arr),.aud_rd_data(ard));
    wire mready,mrv;wire [31:0] mdata;assign ready=mready && !assets_ok;assign ardy=mready && assets_ok;
    assign rv=mrv && !assets_ok;assign arv=mrv && assets_ok;assign rd=mdata;assign ard=mdata;
    sdram_ctrl_wrap memory(.clk(clk_mem),.rst_n(rst),.mem_req_valid(assets_ok ? ar : req),.mem_req_ready(mready),
        .mem_req_addr(assets_ok ? aa : addr),.mem_req_we(assets_ok ? awe : we),.mem_req_len(assets_ok ? al : len),.mem_wr_valid(wv),.mem_wr_ready(wr),.mem_wr_data(wd),
        .mem_rd_valid(mrv),.mem_rd_ready(assets_ok ? arr : rr),.mem_rd_data(mdata),.init_done(init_done));
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
    integer room,ret,n,bcd,nameclip,ix=0,outputs=0,current_clip,phase,expected_sample,expected_clip,checked=0,sentences=0;
    always @(posedge clk_sys)if(rst && assets_ok)begin
      if(preq)begin
        case(ix)
         0:expected_clip=1;1:expected_clip=ret ? (room ? 20 : 19) : (room ? 17 : 2);
         2:expected_clip=3+n/10;3:expected_clip=3+n%10;4:expected_clip=51;5:expected_clip=nameclip;
         6:expected_clip=52;7:expected_clip=room ? 15 : 14;8:expected_clip=18;default:expected_clip=-1;
        endcase
        if(clip_sel!==expected_clip || pbase!==(22'he1000+2*expected_clip) || psamples!=3)
          $fatal(1,"ERROR actual FAT/query/announcer number=%0d ix=%0d clip=%0d/%0d",n,ix,clip_sel,expected_clip);
        current_clip=expected_clip;ix=ix+1;outputs=0;
      end
      if(stb && pbusy)begin
       phase=outputs%3;
       case(outputs/3)
        0:expected_sample=100+current_clip+(-300-2*current_clip)*phase/3;
        1:expected_sample=-200-current_clip+(500+2*current_clip)*phase/3;
        2:expected_sample=300+current_clip;
        default:$fatal(1,"ERROR extra PCM output");
       endcase
       #1;if(sample!==expected_sample[15:0])$fatal(1,"ERROR actual numbered PCM sample clip=%0d output=%0d got=%0d expected=%0d",current_clip,outputs,$signed(sample),expected_sample);
       checked=checked+1;outputs=outputs+1;
      end
      if(underrun)$fatal(1,"ERROR patient audio underrun");
    end
    initial begin
      repeat(8)@(negedge clk_sys);rst=1;wait(load_done);@(negedge clk_sys);
      if(!assets_ok || pcm_count!=54)$fatal(1,"ERROR actual named asset load");
      for(room=0;room<2;room=room+1)for(ret=0;ret<2;ret=ret+1)for(n=1;n<=99;n=n+1)begin
       bcd=(n/10)*16+n%10;ix=0;nameclip=53;
       if(ret && n<=5)nameclip=21+room*15+n-1;
       if(!ret && n<=10)nameclip=26+room*15+n-1;
       @(negedge clk_sys);q=0;tickets=0;returns=0;
       q[room*32+:8]=bcd;q[room*32+18+:2]=1;q[room*32+22]=ret;
       tickets[room*8+:8]=bcd;returns[room]=ret;requests=1<<room;
       @(posedge clk_sys);if(grant!==(1<<room))$fatal(1,"ERROR actual PCM admission");
       @(negedge clk_sys);requests=0;wait(!announcing && !pbusy);@(negedge clk_sys);
       if(ix!=9 || outputs!=9)$fatal(1,"ERROR incomplete actual PCM speech");sentences=sentences+1;
      end
      if(checked!=32076 || sentences!=396)$fatal(1,"ERROR actual speech coverage");
      $display("PASS actual pin SPI/FAT reverse-directory -> preload SDRAM -> registered clip query -> dual announcer -> real dual-clock PCM: 396 A/B/C/D 01..99 sentences, 3564 clips, 32076 exact signed output samples, all 30 full-name IDs, no constant-digit alias");$finish;
    end
    initial begin #200000000;$fatal(1,"TIMEOUT assets state=%0d FAT=%0d SD=%0d fifo=%0d pix=%0d scaler=%0d",dut.state,dut.u_fat32.state,dut.u_sd_card_ctrl.state,dut.word_rlevel,dut.pixel_count,dut.g_legacy_scaler.u_scaler.state);end
endmodule

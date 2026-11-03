`timescale 1ns / 1ps
// Full board-pin test. Only external clock, switches, keys, UART and SD are driven.
module tb_top;
    reg clk=0;always #10 clk=~clk;
    reg [3:0] KEY=15,SW=12;
    reg uart_rx=1;
    wire uart_tx,sclk,mosi,miso,cs_n,buzzer,hclk,h0,h1,h2;
    wire [3:0] led;wire [7:0] seg,sel;
    top #(.SD_INIT_DIV(0),.SD_DATA_DIV(0),.SD_RESPONSE_LIMIT(8)) dut(
        .clk50mhz(clk),.KEY(KEY),.SW(SW),.LED(led),.SEG_DATA(seg),.SEG_SEL(sel),.BUZZER(buzzer),
        .UART_RX(uart_rx),.UART_TX(uart_tx),.SD_SCLK(sclk),.SD_MOSI(mosi),.SD_MISO(miso),.SD_nCS(cs_n),
        .HDMI_CLK_P(hclk),.HDMI_D0_P(h0),.HDMI_D1_P(h1),.HDMI_D2_P(h2));
    sd_card_model card(.sclk(sclk),.mosi(mosi),.miso(miso),.cs_n(cs_n));
`ifdef MEDQ_REAL_SDRAM
    wire [31:0] device_errors,physical_refreshes;
    medq_sdram_device_model physical_memory(
      .clk(dut.u_sdram_ctrl_wrap.u_hardware.sdram_clk),.rst_n(dut.rst_n_mem),.initialized(dut.sdram_init_done),
      .ras_n(dut.u_sdram_ctrl_wrap.u_hardware.ras_n),.cas_n(dut.u_sdram_ctrl_wrap.u_hardware.cas_n),
      .we_n(dut.u_sdram_ctrl_wrap.u_hardware.we_n),.addr(dut.u_sdram_ctrl_wrap.u_hardware.phy_addr),
      .ba(dut.u_sdram_ctrl_wrap.u_hardware.bank),.dm(dut.u_sdram_ctrl_wrap.u_hardware.mask),
      .dq(dut.u_sdram_ctrl_wrap.u_hardware.dq),.errors(device_errors),.refresh_count(physical_refreshes));
    always @(posedge dut.clk_pix)if(dut.rst_n_pix && dut.co_de && (^dut.co_rgb===1'bx))
      $fatal(1,"ERROR first unknown active RGB base=%h rgb_trans=%h osd=%h/%h spec=%h/%h mem_init=%b",dut.rgb_cur,dut.rgb_trans,dut.osd_rgb,dut.osd_alpha,dut.spec_rgb,dut.spec_alpha,dut.sdram_init_done);
    always @(posedge dut.clk_mem)if(dut.rst_n_mem && dut.u_sdram_ctrl_wrap.u_hardware.core_valid && (^dut.u_sdram_ctrl_wrap.u_hardware.core_data===1'bx))
      $fatal(1,"ERROR unknown physical read data address=%h beat=%0d",dut.u_sdram_ctrl_wrap.u_hardware.base,dut.u_sdram_ctrl_wrap.u_hardware.received);
`endif
    localparam BIT_NS=8680;
    reg [7:0] acknowledgements[0:31],ack_byte;
    integer ack_count=0,j;
    always @(negedge uart_tx)if(dut.rst_n_sys)begin
        #(BIT_NS+BIT_NS/2);
        for(j=0;j<8;j=j+1)begin ack_byte[j]=uart_tx;#BIT_NS;end
        if(uart_tx!==1)$fatal(1,"ERROR UART ACK stop bit");
        acknowledgements[ack_count]=ack_byte;ack_count=ack_count+1;
    end
    function [7:0] crc_byte(input [7:0] previous,input [7:0] value);
        reg [7:0] work;integer k;
        begin work=previous^value;for(k=0;k<8;k=k+1)work=work[7] ? (work<<1)^8'h07 : work<<1;crc_byte=work;end
    endfunction
    task send_byte(input [7:0] value);
        integer k;
        begin uart_rx=0;#BIT_NS;for(k=0;k<8;k=k+1)begin uart_rx=value[k];#BIT_NS;end uart_rx=1;#BIT_NS;end
    endtask
    task command(input [7:0] code,input [7:0] selector,input [7:0] value,input bit corrupt);
        reg [7:0] crc;integer before_ack;
        begin
            before_ack=ack_count;
            crc=crc_byte(0,code);crc=crc_byte(crc,selector);crc=crc_byte(crc,0);crc=crc_byte(crc,0);crc=crc_byte(crc,value);
            @(negedge clk);send_byte(8'h55);send_byte(8'haa);send_byte(code);send_byte(selector);send_byte(0);send_byte(0);send_byte(value);send_byte(crc^(corrupt ? 8'h01 : 0));
            wait(ack_count>before_ack);
            if(acknowledgements[before_ack] !== (corrupt ? 8'h15 : 8'h06))$fatal(1,"ERROR UART ACK/NAK %h",acknowledgements[before_ack]);
            #(BIT_NS*2);
        end
    endtask
    integer calls=0,pix_calls=0,pcm_requests=0,mem_requests=0,osd_pixels=0,audio_samples=0;
    integer frames=0,frame_pixels=0,captured=0,fd=0;
    reg capturing=0,capture_armed=0,co_de_previous=0;
    reg call_check_active=0;
    always @(posedge clk)if(dut.rst_n_sys)begin
        if(call_check_active && (^{led,seg,sel,buzzer,uart_tx,sclk,mosi,cs_n,hclk,h0,h1,h2})===1'bx)
            $fatal(1,"ERROR unknown board output led=%h seg=%h sel=%h buz=%b uart=%b SD=%b%b%b HDMI=%b%b%b%b rgb=%h base=%h param=%h osd=%h/%h spec=%h/%h",led,seg,sel,buzzer,uart_tx,sclk,mosi,cs_n,hclk,h0,h1,h2,dut.co_rgb,dut.rgb_cur,dut.param_pix,dut.osd_rgb,dut.osd_alpha,dut.spec_rgb,dut.spec_alpha);
        if(dut.call_pulse_sys)calls=calls+1;
    end
    always @(posedge dut.clk_mem)if(dut.mem_req_valid && dut.mem_req_ready)mem_requests=mem_requests+1;
    always @(posedge dut.clk_pix)if(dut.rst_n_pix)begin
        if(dut.call_pulse_pix)begin
            pix_calls=pix_calls+1;
            if(dut.call_ticket_pix[7:0]==0 || dut.call_room_pix<1 || dut.call_room_pix>2)$fatal(1,"ERROR invalid dual call payload");
        end
        if(dut.play_req)pcm_requests=pcm_requests+1;
        if(dut.aud_stb)audio_samples=audio_samples+1;
        if(dut.osd_alpha!=0)osd_pixels=osd_pixels+1;
        if(dut.vt_frame_start)begin
            frames=frames+1;
            if(dut.assets_ok && !capturing && captured<12)capture_armed=1;
        end
        if(capture_armed && dut.co_de && !co_de_previous)begin
            capture_armed=0;capturing=1;fd=$fopen($sformatf("top_frame_%02d.ppm",captured),"wb");
            $fwrite(fd,"P6\n640 480\n255\n");
        end
        if(capturing && dut.co_de)begin
            $fwrite(fd,"%c%c%c",dut.co_rgb[23:16],dut.co_rgb[15:8],dut.co_rgb[7:0]);
            frame_pixels=frame_pixels+1;
            if(frame_pixels==307200)begin
                $fclose(fd);fd=0;capturing=0;captured=captured+1;frame_pixels=0;
            end
        end
        co_de_previous=dut.co_de;
        if(call_check_active && (dut.disp_underrun || dut.pcm_underrun))$fatal(1,"ERROR integrated display/audio underrun display=%b pcm=%b level=%0d urgent=%b reader=%0d arb_owner=%0d arb_state=%0d loader=%0d play=%b",dut.disp_underrun,dut.pcm_underrun,dut.u_frame_reader_main.wlevel,dut.main_urgent,dut.u_frame_reader_main.state,dut.u_sdram_arbiter.owner,dut.u_sdram_arbiter.state,dut.u_asset_loader.state,dut.play_busy);
    end
    reg [127:0] held_state;
    reg [29:0] held_elapsed;
    reg reset_caption_a,reset_caption_b;
    reg [127:0] expected_frame;
    integer caption_refreshes=0;
    always @(posedge dut.clk_pix)if(dut.rst_n_pix && dut.vt_frame_start)begin
        reset_caption_a=dut.u_osd_renderer.u_dual_scene.pending_refresh[0] || dut.u_osd_renderer.u_dual_scene.changed_a;
        reset_caption_b=dut.u_osd_renderer.u_dual_scene.pending_refresh[1] || dut.u_osd_renderer.u_dual_scene.changed_b;
        expected_frame=dut.qstate_pix;
        #1;
        if(dut.u_osd_renderer.u_dual_scene.frame_state!==expected_frame ||
          (reset_caption_a && dut.u_osd_renderer.u_dual_scene.scroll_a!=dut.u_osd_renderer.u_dual_scene.subtitle_home(expected_frame[31:0],expected_frame[83:68],0)) ||
          (reset_caption_b && dut.u_osd_renderer.u_dual_scene.scroll_b!=dut.u_osd_renderer.u_dual_scene.subtitle_home(expected_frame[63:32],expected_frame[99:84],1)))$fatal(1,"ERROR next-frame atomic centered event refresh");
        if(reset_caption_a || reset_caption_b)caption_refreshes=caption_refreshes+1;
    end
    reg [9:0] held_scroll_a,held_scroll_b;
    task press(input [3:0] mask);
      begin KEY=~mask;#11000000;KEY=15;#11000000;end
    endtask
    task doctor_a;begin SW[2]=!SW[2];#11000000;end endtask
    initial begin
        wait(dut.rst_n_sys && dut.rst_n_pix && dut.rst_n_mem);
        wait(dut.u_media_control.released);press(1);wait(dut.clinic_enable);
        if(dut.qstate_service[63:0]!=0 || calls!=0)$fatal(1,"ERROR cover entry leaked a clinic operation");
        repeat(100)@(negedge clk);call_check_active=1;
        wait(dut.assets_ok && dut.inputs_ready && dut.running==2'b11);
        if(dut.img_count!==0 || dut.media_valid_sys!==0 || dut.pcm_count!==54)$fatal(1,"ERROR unrelated GUIDE.BMP must not be treated as a named media asset");
        command(4,0,0,0);command(4,0,0,1);command(1,0,0,0);command(2,0,0,0);
        if(dut.qstate_service[63:0]!=0 || calls!=0)$fatal(1,"ERROR obsolete UART queue commands active");
        command(5,0,128,0);
        if(dut.param_sys[7:0]!==128)$fatal(1,"ERROR UART parameter");
        KEY=0;#100000;KEY=15;#100000;press(15);
        wait(!dut.u_dual_announcer.announcing && !dut.play_busy);
        if(dut.qstate_pix[7:0]!=1 || dut.qstate_pix[39:32]!=1 ||
          dut.qstate_pix[12:8]!=1 || dut.qstate_pix[44:40]!=1 ||
          dut.qstate_pix[17:13]!=0 || dut.qstate_pix[49:45]!=0 || !dut.qstate_pix[22] || !dut.qstate_pix[54])
          $fatal(1,"ERROR simultaneous A/B normal+return queues %h",dut.qstate_pix);
        doctor_a;
        if(dut.qstate_pix[19:18]!=2 || dut.qstate_pix[51:50]!=1)$fatal(1,"ERROR doctor A independent arrival");
        press(4);
        if(dut.qstate_pix[7:0]!=1 || dut.qstate_pix[17:13]!=1)$fatal(1,"ERROR return preempted current");
        doctor_a;
        wait(dut.qstate_pix[7:0]==2 && dut.qstate_pix[22]);
        if(!dut.qstate_pix[22] || dut.qstate_pix[12:8]!=1 || dut.qstate_pix[39:32]!=1)$fatal(1,"ERROR strict return priority/cross-room isolation");
        wait(!dut.u_dual_announcer.announcing && !dut.play_busy);
        SW[0]=1;#11000000;
        @(posedge dut.vt_frame_start);@(negedge dut.clk_pix);
        held_state=dut.qstate_pix;held_elapsed=dut.u_dual_service.a.elapsed;held_scroll_a=dut.u_osd_renderer.u_dual_scene.scroll_a;held_scroll_b=dut.u_osd_renderer.u_dual_scene.scroll_b;
        KEY=0;#11000000;KEY=15;#11000000;
        repeat(2)@(posedge dut.vt_frame_start);@(negedge dut.clk_pix);
        if(dut.qstate_pix[12:8]!=held_state[12:8]+1 || dut.qstate_pix[17:13]!=held_state[17:13]+1 ||
           dut.qstate_pix[44:40]!=held_state[44:40]+1 || dut.qstate_pix[49:45]!=held_state[49:45]+1 ||
           dut.qstate_pix[7:0]!=held_state[7:0] || dut.u_dual_service.a.elapsed!=held_elapsed ||
           dut.u_osd_renderer.u_dual_scene.scroll_a>591 || dut.u_osd_renderer.u_dual_scene.scroll_b>591)
          $fatal(1,"ERROR SW1-off live queues/marquees or call progression");
        held_scroll_a=dut.u_osd_renderer.u_dual_scene.scroll_a;held_scroll_b=dut.u_osd_renderer.u_dual_scene.scroll_b;
        repeat(2)@(posedge dut.vt_frame_start);@(negedge dut.clk_pix);
        if(dut.u_osd_renderer.u_dual_scene.scroll_a!=(held_scroll_a==591 ? 0 : held_scroll_a+1) || dut.u_osd_renderer.u_dual_scene.scroll_b!=(held_scroll_b==591 ? 0 : held_scroll_b+1))$fatal(1,"ERROR event reset prevented later continuous scroll");
        SW[0]=0;#11000000;
        if(dut.qstate_pix[12:8]!=2 || dut.qstate_pix[17:13]!=1)$fatal(1,"ERROR SW1 resume duplicated enqueue");
        doctor_a;if(dut.qstate_pix[19:18]!=2)$fatal(1,"ERROR resume doctor arrival");
        doctor_a;wait(dut.qstate_pix[7:0]==3 && dut.qstate_pix[22]);
        wait(!dut.u_dual_announcer.announcing && !dut.play_busy);
        doctor_a;doctor_a;wait(dut.qstate_pix[7:0]==1 && !dut.qstate_pix[22]);
        wait(!dut.u_dual_announcer.announcing && !dut.play_busy);
        wait(captured>=12 && frames>=13);
        if(caption_refreshes<5 || calls!=5 || pix_calls!=5 || pcm_requests!=45 || mem_requests<2000 || osd_pixels<100 || audio_samples<1600)
            $fatal(1,"ERROR coverage calls=%0d/%0d clips=%0d memory=%0d OSD=%0d audio=%0d",calls,pix_calls,pcm_requests,mem_requests,osd_pixels,audio_samples);
        if(dut.u_dual_service.accepted_a!=5 || dut.u_dual_service.accepted_b!=4 || dut.u_dual_service.completed_a!=3 ||
           dut.qstate_pix[12:8]!=1 || dut.qstate_pix[17:13]!=0 || dut.qstate_pix[44:40]!=2 || dut.qstate_pix[49:45]!=1)
           $fatal(1,"ERROR final independently expected patient conservation");
`ifdef MEDQ_REAL_SDRAM
        if(device_errors!=0 || physical_refreshes<100 || dut.u_sdram_ctrl_wrap.u_hardware.fault)
            $fatal(1,"ERROR physical SDRAM errors=%0d refresh=%0d",device_errors,physical_refreshes);
        $display("CHECK original SDRAM controller in complete MedQ top, physical refreshes=%0d",physical_refreshes);
`endif
        $display("PASS V0.3 full board pins: real 10ms debounce, A/B strict return priority, doctor semantics, SW1-off enqueue/live marquee, UART ACK/NAK/CRC, five admissions, 45 PCM clips, 12 continuous full VGA/HDMI frames");
        $display("INFO frames=%0d memory_bursts=%0d audio_samples=%0d OSD_pixels=%0d",frames,mem_requests,audio_samples,osd_pixels);$finish;
    end
    initial begin #600000000;$fatal(1,"TIMEOUT top assets=%b loader=%0d calls=%0d ack=%0d frames=%0d capture=%0d",dut.assets_ok,dut.u_asset_loader.state,calls,ack_count,frames,captured);end
endmodule

`timescale 1ns / 1ps
module tb_audio_pipeline;
    reg pix=0,mem=0;always #20 pix=~pix;always #5 mem=~mem;
    reg rst=0,call_event=0;reg [15:0] ticket=16'h1234;reg [3:0] room=2;reg priority_call=0;
    wire stb,play_req,play_busy,play_done,underrun,announcing;
    wire [5:0] clip;wire [21:0] base,samples,play_base,play_samples;
    reg clips_enabled=1;
    assign base=22'he1000+clip*2;assign samples=clips_enabled ? 3 : 0;
    wire [15:0] sample;
    wire req,ready,we,wv,wr,rv,rr,initialized;wire [21:0] addr;wire [8:0] len;wire [31:0] wd,rd;
    audio_sample_clk sample_clock(.clk(pix),.rst_n(rst),.stb(stb));
    audio_announcer announcer(.clk(pix),.rst_n(rst),.call_pulse(call_event),.call_ticket(ticket),.call_room(room),.call_prio(priority_call),.call_recall(1'b0),
        .clip_sel(clip),.clip_base(base),.clip_samples(samples),.play_req(play_req),.play_base(play_base),.play_samples(play_samples),
        .play_busy(play_busy),.play_done(play_done),.announcing(announcing));
    audio_pcm_player player(.clk_pix(pix),.rst_n_pix(rst),.clk_mem(mem),.rst_n_mem(rst),.stb(stb),
        .play_req(play_req),.play_base(play_base),.play_samples(play_samples),.play_busy(play_busy),.play_done(play_done),.sample(sample),.underrun(underrun),
        .aud_req_valid(req),.aud_req_ready(ready),.aud_req_addr(addr),.aud_req_we(we),.aud_req_len(len),
        .aud_wr_valid(wv),.aud_wr_ready(wr),.aud_wr_data(wd),.aud_rd_valid(rv),.aud_rd_ready(rr),.aud_rd_data(rd));
    sdram_ctrl_wrap memory(.clk(mem),.rst_n(rst),.mem_req_valid(req),.mem_req_ready(ready),.mem_req_addr(addr),.mem_req_we(we),.mem_req_len(len),
        .mem_wr_valid(wv),.mem_wr_ready(wr),.mem_wr_data(wd),.mem_rd_valid(rv),.mem_rd_ready(rr),.mem_rd_data(rd),.init_done(initialized));
    integer expected_clip[0:8];integer requests=0,outputs=0,clip_index=0,n,phase,expected,cycles=0,last_stb=0,strobes=0;
    reg counted;
    always @(posedge pix)if(rst)begin
        cycles=cycles+1;
        if(stb)begin
            if(last_stb!=0 && cycles-last_stb!=520 && cycles-last_stb!=521)$fatal(1,"ERROR sample interval %0d",cycles-last_stb);
            last_stb=cycles;strobes=strobes+1;
        end
        if(play_req)begin
            if(requests>=9 || clip!==expected_clip[requests] || play_base!==(22'he1000+2*expected_clip[requests]))$fatal(1,"ERROR announcement step %0d clip=%0d",requests,clip);
            clip_index=expected_clip[requests];requests=requests+1;outputs=0;
        end
        counted=stb && play_busy;
        if(counted)begin
            phase=outputs%3;
            case(outputs/3)
                0:expected=100+clip_index+(-300-2*clip_index)*phase/3;
                1:expected=-200-clip_index+(500+2*clip_index)*phase/3;
                2:expected=300+clip_index;
                default:$fatal(1,"ERROR PCM extra samples");
            endcase
            #1;if(sample!==expected[15:0])$fatal(1,"ERROR PCM output=%0d exp=%0d got=%0d",outputs,expected,$signed(sample));
            outputs=outputs+1;
        end
        #1;if(underrun)$fatal(1,"ERROR audio underrun");
    end
    task announce;
        begin @(negedge pix);call_event=1;@(negedge pix);call_event=0;wait(announcing);wait(!announcing);end
    endtask
    initial begin
        for(n=0;n<19;n=n+1)begin
            memory.sim_mem[22'he1000+n*2]={16'(-200-n),16'(100+n)};
            memory.sim_mem[22'he1001+n*2]=300+n;
        end
        expected_clip[0]=1;expected_clip[1]=0;expected_clip[2]=4;expected_clip[3]=5;expected_clip[4]=6;
        expected_clip[5]=7;expected_clip[6]=13;expected_clip[7]=15;expected_clip[8]=18;
        repeat(5)@(negedge pix);rst=1;repeat(40)@(negedge pix);
        announce;
        if(requests!=9 || outputs!=9)$fatal(1,"ERROR incomplete announcement");
        requests=0;expected_clip[1]=2;priority_call=1;announce;
        if(requests!=9)$fatal(1,"ERROR repeated playback");
        clips_enabled=0;requests=0;announce;if(requests!=0)$fatal(1,"ERROR zero clips should be skipped");
        if(strobes<162)$fatal(1,"ERROR sample count");
        $display("PASS audio: 48kHz single strobes, all BCD digits, 18 clips, signed 3x interpolation, odd samples, repeated playback, missing clips");$finish;
    end
    initial begin #10000000;$fatal(1,"TIMEOUT audio");end
endmodule

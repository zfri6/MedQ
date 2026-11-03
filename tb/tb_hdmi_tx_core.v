`timescale 1ns / 1ps
module tb_hdmi_tx_core;
    reg clk=0;always #20 clk=~clk;
    reg rst=0;
    wire de,hs,vs;wire [9:0] x,y;wire [23:0] rgb={x[7:0]^y[7:0],y[7:0],x[7:0]};
    wire stb;integer audio_in=0,audio_out=0;
    wire [15:0] left=audio_in[15:0],right=~audio_in[15:0];
    wire [9:0] ch0,ch1,ch2;wire overflow,underflow;
    video_timing timing(.clk(clk),.rst_n(rst),.de(de),.hs(hs),.vs(vs),.x(x),.y(y),.frame_start(),.line_start(),.frame_cnt());
    audio_sample_clk samples(.clk(clk),.rst_n(rst),.stb(stb));
    hdmi_tx_core dut(.clk(clk),.rst_n(rst),.vid_de(de),.vid_hs(hs),.vid_vs(vs),.vid_rgb(rgb),
        .aud_stb(stb),.aud_l(left),.aud_r(right),.tmds_ch0(ch0),.tmds_ch1(ch1),.tmds_ch2(ch2),.aud_overflow(overflow),.aud_underflow(underflow));
    reg [9:0] terc[0:15];integer i,k,bit_index=0,di_state=0,di_count=0,packets=0,video_pixels=0;
    integer acr_count=0,avi_count=0,info_count=0,sample_count=0,sum,header_type,decoded0,decoded1,decoded2;
    reg [31:0] hb;reg [63:0] sb[0:3];
    reg input_de;reg [23:0] expected_rgb;
    function [7:0] decode_video(input [9:0] symbol);
        reg [7:0] qm;integer b;
        begin
            qm=symbol[9] ? ~symbol[7:0] : symbol[7:0];decode_video[0]=qm[0];
            for(b=1;b<8;b=b+1)decode_video[b]=symbol[8] ? qm[b]^qm[b-1] : ~(qm[b]^qm[b-1]);
        end
    endfunction
    function integer decode_terc(input [9:0] symbol);
        integer j;begin decode_terc=-1;for(j=0;j<16;j=j+1)if(terc[j]==symbol)decode_terc=j;end
    endfunction
    function [7:0] syndrome(input [63:0] block_data,input integer length);
        reg [7:0] ecc;integer j;
        begin ecc=0;for(j=0;j<length;j=j+1)ecc=(ecc>>1)^((ecc[0]^block_data[j]) ? 8'h83 : 0);syndrome=ecc;end
    endfunction
    task check_packet;
        begin
            if(syndrome({32'd0,hb},32)!==0)$fatal(1,"ERROR header BCH %h",hb);
            for(k=0;k<4;k=k+1)if(syndrome(sb[k],64)!==0)$fatal(1,"ERROR subpacket BCH %0d",k);
            packets=packets+1;header_type=hb[7:0];
            case(header_type)
                0: begin end
                1: begin
                    acr_count=acr_count+1;
                    for(k=0;k<4;k=k+1)if(sb[k][55:0]!==56'h001800a8610000)$fatal(1,"ERROR ACR N/CTS bytes %h",sb[k][55:0]);
                end
                2: begin
                    sample_count=sample_count+1;
                    for(k=0;k<4;k=k+1)if(hb[8+k])begin
                        if(sb[k][23:8]!==audio_out[15:0] || sb[k][47:32]!==~audio_out[15:0] || sb[k][7:0]!==0 || sb[k][31:24]!==0)
                            $fatal(1,"ERROR audio packet sequence expected=%0d payload=%h",audio_out,sb[k][55:0]);
                        if(hb[20+k] !== (audio_out%192==0))$fatal(1,"ERROR IEC block start");
                        audio_out=audio_out+1;
                    end
                end
                8'h82,8'h84:begin
                    sum=hb[7:0]+hb[15:8]+hb[23:16];
                    for(k=0;k<4;k=k+1)for(i=0;i<7;i=i+1)sum=sum+sb[k][8*i+:8];
                    if((sum&255)!=0)$fatal(1,"ERROR InfoFrame checksum");
                    if(header_type==8'h82)avi_count=avi_count+1;else info_count=info_count+1;
                end
                default:$fatal(1,"ERROR packet type %h",hb);
            endcase
        end
    endtask
    always @(posedge clk)if(rst)begin
        input_de=de;expected_rgb=rgb;
        if(stb)audio_in<=audio_in+1;
        #1;
        if((^{ch0,ch1,ch2})===1'bx || overflow)$fatal(1,"ERROR HDMI X or audio overflow");
        if(input_de)begin
            if({decode_video(ch2),decode_video(ch1),decode_video(ch0)}!==expected_rgb)$fatal(1,"ERROR HDMI video alignment");
            video_pixels=video_pixels+1;
        end else if(di_state==0)begin
            if(ch1==10'b0100110011 && ch2==10'b0100110011)begin di_state=1;di_count=1;end
        end else if(di_state==1)begin
            if(ch1!==10'b0100110011 || ch2!==10'b0100110011)$fatal(1,"ERROR leading guard band");
            di_state=2;di_count=0;bit_index=0;hb=0;for(k=0;k<4;k=k+1)sb[k]=0;
        end else if(di_state==2)begin
            decoded0=decode_terc(ch0);decoded1=decode_terc(ch1);decoded2=decode_terc(ch2);
            if(decoded0<0 || decoded1<0 || decoded2<0)$fatal(1,"ERROR illegal TERC4");
            hb[bit_index]=(decoded0>>2)&1;
            for(k=0;k<4;k=k+1)begin sb[k][2*bit_index]=(decoded1>>k)&1;sb[k][2*bit_index+1]=(decoded2>>k)&1;end
            di_count=di_count+1;
            if(bit_index==31)begin check_packet;bit_index=0;hb=0;for(k=0;k<4;k=k+1)sb[k]=0;end
            else bit_index=bit_index+1;
            if(di_count==96)begin di_state=3;di_count=0;end
        end else if(di_state==3)begin
            if(ch1!==10'b0100110011 || ch2!==10'b0100110011)$fatal(1,"ERROR trailing guard band");
            di_count=di_count+1;if(di_count==2)di_state=0;
        end
    end
    initial begin
        terc[0]=10'b1010011100;terc[1]=10'b1001100011;terc[2]=10'b1011100100;terc[3]=10'b1011100010;
        terc[4]=10'b0101110001;terc[5]=10'b0100011110;terc[6]=10'b0110001110;terc[7]=10'b0100111100;
        terc[8]=10'b1011001100;terc[9]=10'b0100111001;terc[10]=10'b0110011100;terc[11]=10'b1011000110;
        terc[12]=10'b1010001110;terc[13]=10'b1001110001;terc[14]=10'b0101100011;terc[15]=10'b1011000011;
        repeat(5)@(negedge clk);rst=1;
        repeat(430000)@(negedge clk);
        if(video_pixels<307200 || packets<1500 || acr_count==0 || avi_count==0 || info_count==0 || sample_count==0 || audio_in-audio_out>8)
            $fatal(1,"ERROR HDMI coverage pixels=%0d packets=%0d audio=%0d/%0d",video_pixels,packets,audio_out,audio_in);
        $display("PASS HDMI: %0d video pixels, %0d decoded packets, BCH/checksums, %0d ordered stereo samples",video_pixels,packets,audio_out);$finish;
    end
    initial begin #20000000;$fatal(1,"TIMEOUT HDMI");end
endmodule

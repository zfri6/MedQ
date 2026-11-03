`timescale 1ns / 1ps
// 640x480 HDMI: three 32-symbol packets per H blank, zero-seeded BCH on all five blocks.
module hdmi_tx_core (
    input  wire        clk,
    input  wire        rst_n,
    // Video input (negative polarity HS/VS)
    input  wire        vid_de,     // 1: active video
    input  wire        vid_hs,     // negative polarity
    input  wire        vid_vs,     // negative polarity
    input  wire [23:0] vid_rgb,
    // Audio input (48 kHz)
    input  wire        aud_stb,
    input  wire [15:0] aud_l,
    input  wire [15:0] aud_r,
    // TMDS output (10-bit parallel symbols)
    output wire [9:0]  tmds_ch0,  // Blue: control in pre-video, video in video
    output wire [9:0]  tmds_ch1,  // Green: 0 in pre-video/data-island; video in video
    output wire [9:0]  tmds_ch2,  // Red: 0 in pre-video/data-island; video in video
    // Diagnostics
    output wire        aud_overflow,
    output wire        aud_underflow
);


    reg prev_de,prev_hs,prev_vs,hs_seen,line_locked;
    reg [9:0] next_x,line_y;
    wire [9:0] xpos=vid_de && !prev_de ? 10'd0 : !vid_hs && prev_hs ? 10'd656 : next_x;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin prev_de<=0; prev_hs<=1; prev_vs<=1; next_x<=0; line_y<=480; hs_seen<=0; line_locked<=0; end
        else begin
            prev_de<=vid_de; prev_hs<=vid_hs; prev_vs<=vid_vs;
            next_x<=xpos==799 ? 0 : xpos+1'b1;
            if(!vid_hs && prev_hs) hs_seen<=1;
            if(xpos==799 && hs_seen) line_locked<=1;
            if(!vid_vs && prev_vs) line_y<=490;
            else if(xpos==799) line_y<=line_y==524 ? 0 : line_y+1'b1;
        end
    end
    wire packet_request=line_locked && (xpos==600 || xpos==604 || xpos==608);
    wire ack;
    wire [23:0] header;
    wire [55:0] sub0,sub1,sub2,sub3;
    hdmi_packet_scheduler u_sched(.clk(clk),.rst_n(rst_n),.aud_stb(aud_stb),.aud_l(aud_l),.aud_r(aud_r),
        .pkt_req(packet_request),.pkt_ack(ack),.pkt_header(header),.pkt_sub0(sub0),.pkt_sub1(sub1),.pkt_sub2(sub2),.pkt_sub3(sub3),
        .aud_overflow(aud_overflow),.aud_underflow(aud_underflow));
    reg [1:0] pending_slot;
    reg [31:0] headers[0:2];
    reg [63:0] blocks0[0:2],blocks1[0:2],blocks2[0:2],blocks3[0:2];
    function [7:0] parity;
        input [55:0] block_data;
        input integer nbits;
        integer j;
        reg [7:0] crc;
        begin
            crc=0;
            for(j=0;j<nbits;j=j+1) crc=(crc>>1)^((crc[0]^block_data[j]) ? 8'h83 : 8'd0);
            parity=crc;
        end
    endfunction
    integer slot;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            pending_slot<=0;
            for(slot=0;slot<3;slot=slot+1) begin headers[slot]<=0; blocks0[slot]<=0; blocks1[slot]<=0; blocks2[slot]<=0; blocks3[slot]<=0; end
        end else begin
            if(packet_request) pending_slot<=xpos==600 ? 0 : xpos==604 ? 1 : 2;
            if(ack) begin
                headers[pending_slot]<={parity({32'd0,header},24),header};
                blocks0[pending_slot]<={parity(sub0,56),sub0};
                blocks1[pending_slot]<={parity(sub1,56),sub1};
                blocks2[pending_slot]<={parity(sub2,56),sub2};
                blocks3[pending_slot]<={parity(sub3,56),sub3};
            end
        end
    end
    function [9:0] control_symbol;
        input [1:0] bits_value;
        begin case(bits_value)
            0:control_symbol=10'b1101010100;
            1:control_symbol=10'b0010101011;
            2:control_symbol=10'b0101010100;
            3:control_symbol=10'b1010101011;
        endcase end
    endfunction
    wire di=line_locked && xpos>=654 && xpos<750;
    wire di_guard=line_locked && ((xpos>=652 && xpos<654)||(xpos>=750 && xpos<752));
    wire di_preamble=line_locked && xpos>=644 && xpos<652;
    wire next_line_video=line_y<479 || line_y==524;
    wire video_preamble=xpos>=790 && xpos<798 && next_line_video;
    wire video_guard=xpos>=798 && next_line_video;
    integer packet_index,bit_index;
    reg [3:0] nibble0,nibble1,nibble2;
    always @* begin
        packet_index=di ? (xpos-654)/32 : 0;
        bit_index=di ? (xpos-654)%32 : 0;
        nibble0={1'b1,headers[packet_index][bit_index],vid_vs,vid_hs};
        nibble1={blocks3[packet_index][2*bit_index],blocks2[packet_index][2*bit_index],
                 blocks1[packet_index][2*bit_index],blocks0[packet_index][2*bit_index]};
        nibble2={blocks3[packet_index][2*bit_index+1],blocks2[packet_index][2*bit_index+1],
                 blocks1[packet_index][2*bit_index+1],blocks0[packet_index][2*bit_index+1]};
        if(di_guard) nibble0={2'b11,vid_vs,vid_hs};
    end
    wire [9:0] terc0,terc1,terc2;
    hdmi_terc4_encoder te0(.din(nibble0),.dout(terc0));
    hdmi_terc4_encoder te1(.din(nibble1),.dout(terc1));
    hdmi_terc4_encoder te2(.din(nibble2),.dout(terc2));
    wire [9:0] enc0,enc1,enc2;
    hdmi_tmds_encoder u_tmds_ch0(.clk(clk),.rst_n(rst_n),.din(vid_rgb[7:0]),.c({vid_vs,vid_hs}),.de(vid_de),.dout(enc0));
    hdmi_tmds_encoder u_tmds_ch1(.clk(clk),.rst_n(rst_n),.din(vid_rgb[15:8]),.c(2'b00),.de(vid_de),.dout(enc1));
    hdmi_tmds_encoder u_tmds_ch2(.clk(clk),.rst_n(rst_n),.din(vid_rgb[23:16]),.c(2'b00),.de(vid_de),.dout(enc2));
    reg [9:0] other0,other1,other2;
    reg video_q;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin video_q<=0; other0<=10'b1101010100; other1<=10'b1101010100; other2<=10'b1101010100; end
        else begin
            video_q<=vid_de;
            other0<=control_symbol({vid_vs,vid_hs});
            other1<=control_symbol({1'b0,di_preamble || video_preamble});
            other2<=control_symbol({1'b0,di_preamble});
            if(di) begin other0<=terc0; other1<=terc1; other2<=terc2; end
            else if(di_guard) begin other0<=terc0; other1<=10'b0100110011; other2<=10'b0100110011; end
            else if(video_guard) begin other0<=10'b1011001100; other1<=10'b0100110011; other2<=10'b1011001100; end
        end
    end
    assign tmds_ch0=video_q ? enc0 : other0;
    assign tmds_ch1=video_q ? enc1 : other1;
    assign tmds_ch2=video_q ? enc2 : other2;
endmodule

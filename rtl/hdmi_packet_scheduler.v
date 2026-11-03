`timescale 1ns / 1ps
// Raw 24/56-bit packet payloads. ECC belongs to the 32-symbol wire encoder.
module hdmi_packet_scheduler #(
    parameter ACR_N   = 6144,   // 48 kHz standard N value
    parameter ACR_CTS = 25000   // 25.000 MHz TMDS / (128 * fs) = 25000
) (
    input  wire        clk,
    input  wire        rst_n,
    // Audio input (48 kHz)
    input  wire        aud_stb,    // 48 kHz sample strobe
    input  wire [15:0] aud_l,      // Left channel signed sample
    input  wire [15:0] aud_r,      // Right channel signed sample
    // Packet request from hdmi_tx_core
    input  wire        pkt_req,    // Data island controller requests next packet
    output reg         pkt_ack,    // Packet ready, consumers should latch
    output reg  [23:0] pkt_header, // HB0=type, HB1=ver, HB2=len
    output reg  [55:0] pkt_sub0,  // subpacket 0 (56 bits = 7 bytes)
    output reg  [55:0] pkt_sub1,  // subpacket 1
    output reg  [55:0] pkt_sub2,  // subpacket 2
    output reg  [55:0] pkt_sub3,  // subpacket 3
    // Diagnostics
    output reg         aud_overflow,  // Audio FIFO overflow
    output reg         aud_underflow  // Audio FIFO underflow
);


    reg [31:0] fifo[0:63];
    reg [5:0] wp,rp;
    reg [6:0] count;
    reg sample_turn;
    reg [1:0] metadata;
    reg [7:0] frame_index;
    wire [2:0] take=pkt_req && sample_turn ? (count>=4 ? 3'd4 : count[2:0]) : 3'd0;
    wire push=aud_stb && (count<64 || take!=0);
    integer i,fi;
    reg [3:0] present,block_start;
    reg [55:0] assembled[0:3];
    function [55:0] audio_payload;
        input [31:0] value;
        input [7:0] index;
        reg [191:0] status_l,status_r;
        reg cl,cr,pl,pr;
        reg [23:0] l,r;
        begin
            status_l=(192'd2<<24)|(192'd1<<16)|192'd4|(192'd2<<32);
            status_r=(192'd2<<24)|(192'd2<<16)|192'd4|(192'd2<<32);
            cl=status_l[index]; cr=status_r[index];
            l={value[15:0],8'd0}; r={value[31:16],8'd0};
            pl=(^l)^cl; pr=(^r)^cr;
            audio_payload={pr,cr,2'b00,pl,cl,2'b00,r,l};
        end
    endfunction
    always @* begin
        present=0; block_start=0; fi=0;
        for(i=0;i<4;i=i+1) begin
            fi=frame_index+i;
            if(fi>=192) fi=fi-192;
            assembled[i]=0;
            if(i<take) begin
                present[i]=1; block_start[i]=fi==0;
                assembled[i]=audio_payload(fifo[(rp+i)&63],fi[7:0]);
            end
        end
    end
    wire [55:0] acr={ACR_N[7:0],ACR_N[15:8],4'd0,ACR_N[19:16],
                     ACR_CTS[7:0],ACR_CTS[15:8],4'd0,ACR_CTS[19:16],8'd0};
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            wp<=0; rp<=0; count<=0; sample_turn<=0; metadata<=0; frame_index<=0;
            pkt_ack<=0; pkt_header<=0; pkt_sub0<=0; pkt_sub1<=0; pkt_sub2<=0; pkt_sub3<=0;
            aud_overflow<=0; aud_underflow<=0;
        end else begin
            pkt_ack<=pkt_req;
            aud_overflow<=aud_stb && !push;
            aud_underflow<=pkt_req && sample_turn && count==0;
            if(push) begin fifo[wp]<={aud_r,aud_l}; wp<=wp+1'b1; end
            count<=count+(push ? 1'b1 : 1'b0)-take;
            if(take!=0) begin
                rp<=rp+take;
                frame_index<=frame_index+take>=192 ? frame_index+take-192 : frame_index+take;
            end
            if(pkt_req) begin
                sample_turn<=~sample_turn;
                pkt_sub0<=0; pkt_sub1<=0; pkt_sub2<=0; pkt_sub3<=0;
                if(sample_turn) begin
                    pkt_header<=take==0 ? 24'd0 : {block_start,8'd0,present,8'h02};
                    pkt_sub0<=assembled[0]; pkt_sub1<=assembled[1]; pkt_sub2<=assembled[2]; pkt_sub3<=assembled[3];
                end else begin
                    metadata<=metadata==2 ? 0 : metadata+1'b1;
                    case(metadata)
                        0: begin pkt_header<=24'h000001; pkt_sub0<=acr; pkt_sub1<=acr; pkt_sub2<=acr; pkt_sub3<=acr; end
                        1: begin pkt_header<=24'h0d0282; pkt_sub0<=56'h00000100080066; end
                        2: begin pkt_header<=24'h0a0184; pkt_sub0<=56'h00000000000170; end
                        default: pkt_header<=0;
                    endcase
                end
            end
        end
    end
endmodule

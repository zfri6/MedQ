`timescale 1ns / 1ps
// Backpressured two-row bilinear scaler, both top-down and bottom-up streams.
module bilinear_scaler (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        bypass,
    input  wire [10:0] src_w,
    input  wire [10:0] src_h,
    input  wire        in_valid,
    input  wire [23:0] in_rgb,
    input  wire [10:0] in_x,
    input  wire [10:0] in_y,
    input  wire        in_last,
    output wire        in_ready,
    input wire         out_ready,
    output reg         out_valid,
    output wire [23:0] out_rgb,
    output wire [9:0]  out_x,
    output wire [9:0]  out_y,
    output reg         out_last
);


    // Coordinate division once per image; exact quotient/remainder DDA per pixel.
    localparam IDLE=0,DIVIDE=1,FILL=2,CHECK=3,ADDR0=4,CAP0=5,
               ADDR1=6,CAP1=7,HT=8,HB=9,VERT=10,OUTPUT=11,PREP_HT=13,PREP_HB=14,PREP_V=15;
    reg [3:0] state;
    reg [23:0] rows0[0:1023],rows1[0:1023];
    reg [23:0] q0,q1,a,b,c,d,top_rgb,bottom_rgb,result_rgb;
    reg [10:0] tag0,tag1;
    reg valid0,valid1,descending,write_bank;
    reg [9:0] ox,oy;
    reg [26:0] sx,sy,step_x,step_y,quot_x,quot_y,num_x,num_y;
    reg [9:0] rem_x,rem_y,step_rx,step_ry,div_rx,div_ry;
    reg [4:0] div_bit;
    wire [10:0] x0=sx[26:16],y0=sy[26:16];
    wire [10:0] x1=x0+1<src_w ? x0+1'b1 : x0;
    wire [10:0] y1=y0+1<src_h ? y0+1'b1 : y0;
    wire have0=(valid0 && tag0==y0)||(valid1 && tag1==y0);
    wire have1=(valid0 && tag0==y1)||(valid1 && tag1==y1);
    wire bank0=!(valid0 && tag0==y0),bank1=!(valid0 && tag0==y1);
    wire [9:0] ram_addr=(state==ADDR1 || state==CAP1) ? x1[9:0] : x0[9:0];
    wire fill=(state==IDLE || state==FILL) && in_valid && !bypass;
    wire [10:0] shifted_x={div_rx,num_x[div_bit]};
    wire [10:0] shifted_y={div_ry,num_y[div_bit]};
    wire [10:0] sum_x={1'b0,rem_x}+{1'b0,step_rx};
    wire [10:0] sum_y={1'b0,rem_y}+{1'b0,step_ry};
    // Two physical synchronous row memories, no reset on the memory ports.
    always @(posedge clk) begin
        if(fill && (state==IDLE || !write_bank))rows0[in_x[9:0]]<=in_rgb;
        if(fill && state!=IDLE && write_bank)rows1[in_x[9:0]]<=in_rgb;
        q0<=rows0[ram_addr];q1<=rows1[ram_addr];
    end
    function [7:0] lerp;
        input [7:0] first,second;
        input [15:0] fraction;
        reg signed [8:0] delta;
        reg signed [25:0] product;
        reg signed [26:0] weighted;
        begin
            delta=$signed({1'b0,second})-$signed({1'b0,first});
            product=delta*$signed({1'b0,fraction});
            weighted=$signed({3'd0,first,16'd0})+product+27'sd32768;
            lerp=weighted[23:16];
        end
    endfunction
    reg [23:0] first,second;
    reg [15:0] fraction;
    wire [23:0] mixed={lerp(first[23:16],second[23:16],fraction),
                      lerp(first[15:8],second[15:8],fraction),
                      lerp(first[7:0],second[7:0],fraction)};
    assign in_ready=bypass ? out_ready : state==IDLE || state==FILL;
    assign out_rgb=bypass ? in_rgb : result_rgb;
    assign out_x=bypass ? in_x[9:0] : ox;
    assign out_y=bypass ? in_y[9:0] : oy;
    always @* begin
        out_valid=bypass ? in_valid : state==OUTPUT;
        out_last=bypass ? (in_x==639 && ((state==IDLE ? in_y!=0 : descending) ? in_y==0 : in_y==479)) :
            state==OUTPUT && ox==639 && (descending ? oy==0 : oy==479);
    end
    always @(posedge clk or negedge rst_n)begin
      if(!rst_n)begin
        state<=IDLE;valid0<=0;valid1<=0;tag0<=0;tag1<=0;write_bank<=0;
        descending<=0;ox<=0;oy<=0;sx<=0;sy<=0;rem_x<=0;rem_y<=0;
        step_x<=0;step_y<=0;step_rx<=0;step_ry<=0;div_rx<=0;div_ry<=0;
        num_x<=0;num_y<=0;quot_x<=0;quot_y<=0;div_bit<=26;
        a<=0;b<=0;c<=0;d<=0;top_rgb<=0;bottom_rgb<=0;result_rgb<=0;first<=0;second<=0;fraction<=0;
      end else if(bypass)begin
        if(in_valid && out_ready)begin
          if(state==IDLE)begin descending<=in_y!=0;state<=12;end
          if(out_last)state<=IDLE;
        end
      end else case(state)
        IDLE:if(in_valid)begin
          valid0<=in_x==src_w-1;valid1<=0;tag0<=in_y;
          descending<=in_y!=0;ox<=0;oy<=in_y!=0 ? 479 : 0;
          sx<=0;sy<=in_y!=0 ? {(src_h-11'd1),16'd0} : 27'd0;
          rem_x<=0;rem_y<=0;write_bank<=0;
          num_x<={(src_w-11'd1),16'd0};num_y<={(src_h-11'd1),16'd0};
          quot_x<=0;quot_y<=0;div_rx<=0;div_ry<=0;div_bit<=26;state<=DIVIDE;
        end
        DIVIDE:begin
          div_rx<=shifted_x>=639 ? shifted_x-11'd639 : shifted_x;
          div_ry<=shifted_y>=479 ? shifted_y-11'd479 : shifted_y;
          quot_x<={quot_x[25:0],shifted_x>=639};quot_y<={quot_y[25:0],shifted_y>=479};
          if(div_bit==0)begin
            step_x<={quot_x[25:0],shifted_x>=639};step_y<={quot_y[25:0],shifted_y>=479};
            step_rx<=shifted_x>=639 ? shifted_x-11'd639 : shifted_x;
            step_ry<=shifted_y>=479 ? shifted_y-11'd479 : shifted_y;
            state<=valid0 ? CHECK : FILL;
          end else div_bit<=div_bit-1'b1;
        end
        FILL:if(in_valid)begin
          if(write_bank)begin tag1<=in_y;if(in_x==src_w-1)valid1<=1;end
          else begin tag0<=in_y;if(in_x==src_w-1)valid0<=1;end
          if(in_x==src_w-1)state<=CHECK;
        end
        CHECK:if(have0 && have1)begin ox<=0;sx<=0;rem_x<=0;state<=ADDR0;end
          else begin write_bank<=valid0 && (tag0==y0 || tag0==y1);state<=FILL;end
        ADDR0:state<=CAP0;
        CAP0:begin a<=bank0 ? q1 : q0;c<=bank1 ? q1 : q0;state<=ADDR1;end
        ADDR1:state<=CAP1;
        CAP1:begin b<=bank0 ? q1 : q0;d<=bank1 ? q1 : q0;state<=PREP_HT;end
        PREP_HT:begin first<=a;second<=b;fraction<=sx[15:0];state<=HT;end
        HT:begin top_rgb<=mixed;state<=PREP_HB;end
        PREP_HB:begin first<=c;second<=d;fraction<=sx[15:0];state<=HB;end
        HB:begin bottom_rgb<=mixed;state<=PREP_V;end
        PREP_V:begin first<=top_rgb;second<=bottom_rgb;fraction<=sy[15:0];state<=VERT;end
        VERT:begin result_rgb<=mixed;state<=OUTPUT;end
        OUTPUT:if(out_ready)begin
          if(ox==639)begin
            ox<=0;sx<=0;rem_x<=0;
            if(out_last)begin valid0<=0;valid1<=0;state<=IDLE;end
            else begin
              oy<=descending ? oy-1'b1 : oy+1'b1;
              if(descending)begin
                sy<=sy-step_y-(rem_y<step_ry ? 27'd1 : 27'd0);
                rem_y<=rem_y<step_ry ? rem_y+10'd479-step_ry : rem_y-step_ry;
              end else begin
                sy<=sy+step_y+(sum_y>=479 ? 27'd1 : 27'd0);
                rem_y<=sum_y>=479 ? sum_y-11'd479 : sum_y;
              end
              state<=CHECK;
            end
          end else begin
            ox<=ox+1'b1;sx<=sx+step_x+(sum_x>=639 ? 27'd1 : 27'd0);
            rem_x<=sum_x>=639 ? sum_x-11'd639 : sum_x;state<=ADDR0;
          end
        end
        default:state<=IDLE;
      endcase
    end
endmodule

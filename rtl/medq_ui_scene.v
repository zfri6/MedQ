`timescale 1ns / 1ps
// Default MedQ dashboard. Every visible state is held for a complete frame.
// Geometry is procedural; text shares the existing synchronous font ROM.
module medq_ui_scene #(parameter LIVE_STATUS=0) (
    input wire clk, rst_n,
    input wire [9:0] x, y,
    input wire frame_start,
    input wire [127:0] qstate,
    input wire [7:0] service_status,
    output reg [13:0] font_addr,
    output reg [3:0] font_column,
    output reg [23:0] background, foreground,
    output reg text_active,
    output reg [7:0] text_opacity
);
    `include "medq_ui_layout.vh"
    localparam [23:0] INK=24'h16324a, MUTED=24'h60798a,
        TEAL=24'h078a86, LINE=24'hdce9ee, WHITE=24'hffffff;
    reg [127:0] display_state;
    reg [7:0] display_service;
    wire reduced_motion=display_state[35];
    reg [4:0] call_age;
    reg [6:0] breath_phase;
    reg [7:0] ease;
    reg [3:0] lift;
    reg [8:0] bar_width;
    wire has_call=display_state[23:16]!=0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin display_state<=0;display_service<=0;call_age<=16;breath_phase<=0;end
        else if(frame_start) begin
            display_state<=qstate;
            display_service<=LIVE_STATUS ? service_status : 8'd0;
            breath_phase<=breath_phase==119 ? 0 : breath_phase+1'b1;
            if(qstate[23:16]!=0 &&
               (qstate[31:0]!=display_state[31:0] || qstate[33]!=display_state[33])) call_age<=0;
            else if(call_age<16) call_age<=call_age+1'b1;
        end
    end
    // Cubic ease-out, evaluated once per frame; no division on the pixel path.
    always @* begin
        case(call_age)
            0:begin ease=0;lift=11;bar_width=0;end
            1:begin ease=45;lift=9;bar_width=61;end
            2:begin ease=84;lift=8;bar_width=115;end
            3:begin ease=118;lift=6;bar_width=161;end
            4:begin ease=147;lift=5;bar_width=201;end
            5:begin ease=172;lift=3;bar_width=235;end
            6:begin ease=193;lift=2;bar_width=263;end
            7:begin ease=210;lift=2;bar_width=287;end
            8:begin ease=223;lift=1;bar_width=304;end
            9:begin ease=234;lift=0;bar_width=319;end
            10:begin ease=242;lift=0;bar_width=330;end
            11:begin ease=247;lift=0;bar_width=337;end
            12:begin ease=251;lift=0;bar_width=343;end
            13:begin ease=253;lift=0;bar_width=345;end
            14:begin ease=254;lift=0;bar_width=347;end
            default:begin ease=255;lift=0;bar_width=348;end
        endcase
        if(reduced_motion)begin ease=255;lift=0;bar_width=348;end
    end
    function rounded;
        input [9:0] px,py,left,top,width,height;
        reg [3:0] cut;
        begin
            if(py==top || py==top+height-1)cut=7;
            else if(py==top+1 || py==top+height-2)cut=5;
            else if(py==top+2 || py==top+height-3)cut=4;
            else if(py==top+3 || py==top+height-4)cut=3;
            else if(py==top+4 || py==top+height-5)cut=2;
            else if(py==top+5 || py==top+height-6 || py==top+6 || py==top+height-7)cut=1;
            else cut=0;
            rounded=py>=top && py<top+height && px>=left+cut && px<left+width-cut;
        end
    endfunction
    reg [7:0] atlas_x;
    reg [8:0] atlas_y;
    task text;
        input [5:0] id;
        input [9:0] left,top;
        input [23:0] color;
        input [7:0] opacity;
        reg [31:0] meta;
        reg signed [10:0] u,v;
        begin
            meta=ui_sprite(id);
            u=$signed({1'b0,x})-$signed({1'b0,left});
            v=$signed({1'b0,y})-$signed({1'b0,top});
            if(x>=left && y>=top && u<meta[14:7] && v<meta[6:0]) begin
                atlas_x=meta[31:24]+u;atlas_y=meta[23:15]+v;
                font_addr={1'b1,atlas_y,atlas_x[7:4]};
                font_column=atlas_x[3:0];text_active=1;
                foreground=color;text_opacity=opacity;
            end
        end
    endtask
    reg [2:0] slot;
    reg [4:0] digit;
    reg [5:0] pulse;
    reg [7:0] dot_green;
    wire [7:0] focus_r=8'd7+{1'b0,ease[7:1]};
    wire [7:0] focus_g=8'd138+{2'b0,ease[7:2]};
    wire [7:0] focus_b=8'd134+{2'b0,ease[7:2]};
    reg [5:0] service_label;
    reg [23:0] service_color;
    always @* begin
        service_label=UI_SERVICE;service_color=TEAL;
        if(LIVE_STATUS)begin
            case(display_service[1:0])
                0:begin service_label=UI_LOADING;service_color=MUTED;end
                1:begin service_label=display_service[3] ? UI_WARNING : UI_READY;
                        service_color=display_service[3] ? 24'ha25d15 : TEAL;end
                2:begin service_label=UI_BASIC;service_color=24'ha25d15;end
                default:begin service_label=UI_FAULT;service_color=24'hb34843;end
            endcase
        end
    end
    always @* begin
        font_addr=8192;font_column=0;foreground=INK;text_active=0;text_opacity=255;
        atlas_x=0;atlas_y=0;slot=0;digit=0;
        pulse=reduced_motion ? 6'd0 : breath_phase<60 ? breath_phase : 119-breath_phase;
        dot_green=130+pulse;
        // Quiet background, header and card shadows.
        background={8'hec,8'hf3,8'hf7};
        if(y<88)background=WHITE;
        if(y==87)background=LINE;
        if(rounded(x,y,24,135,388,224) || rounded(x,y,428,135,188,224) ||
           rounded(x,y,24,379,188,64) || rounded(x,y,228,379,188,64) || rounded(x,y,428,379,188,64))
            background=24'hdfe9ef;
        if(rounded(x,y,24,132,388,224) || rounded(x,y,428,132,188,224) ||
           rounded(x,y,24,376,188,64) || rounded(x,y,228,376,188,64) || rounded(x,y,428,376,188,64))
            background=WHITE;
        // Medical cross, clinic status and destination arrow.
        if(rounded(x,y,24,20,44,44))background=TEAL;
        if((x>=42 && x<50 && y>=30 && y<54) || (x>=34 && x<58 && y>=38 && y<46))background=WHITE;
        if(rounded(x,y,488,24,128,32))background=24'he8f6f2;
        if((x>=501 && x<505 && y>=37 && y<43) || (x>=500 && x<506 && y>=38 && y<42))
            background={8'd7,dot_green,8'd125};
        if(x>=584 && x<600 && y>=154 && y<156)background=TEAL;
        if(x>=594 && x<601 && y>=149 && y<161 &&
           (x-594>=((y>=155)?y-155:154-y)) && (x-594<((y>=155)?y-155:154-y)+2))background=TEAL;
        // Current-call badge, calm progress rule and lower information cards.
        if(rounded(x,y,44,286,92,28))background=display_state[32] ? 24'hfff1dc : 24'he8f6f2;
        if(x>=44 && x<392 && y>=344 && y<346)background=24'he9f3f3;
        if(has_call && x>=44 && x<44+bar_width && y>=344 && y<346)background=24'h72c5bc;
        if(x>=24 && x<616 && y==455)background=24'hd8e6ed;
        if(has_call && x>=430 && x<434 && y>=185 && y<302)
            background=reduced_motion ? TEAL : {focus_r,focus_g,focus_b};
        if(LIVE_STATUS && display_service[1:0]==0 && y>=68 && y<70 &&
           x>=488 && x<488+{display_service[7:4],3'b000})background=TEAL;
        text(UI_BRAND,84,15,INK,255);
        text(UI_SUBTITLE,85,48,MUTED,255);
        text(service_label,516,30,service_color,255);
        text(UI_EYEBROW,24,103,MUTED,255);
        text(UI_CURRENT,44,146,INK,255);
        text(UI_NOW,44,172,MUTED,255);
        text(UI_DESTINATION,448,149,INK,255);
        text(UI_ROOM,552,228,MUTED,255);
        text(UI_ORDER,448,300,MUTED,255);
        text(has_call ? (display_state[33] ? UI_RECALL : display_state[32] ? UI_PRIORITY : UI_NORMAL) : UI_EMPTY,
             52,291,display_state[32] ? 24'ha25d15 : TEAL,255);
        text(UI_CALL_HINT,44,318+lift,MUTED,has_call ? (ease>>1)+128 : 255);
        text(UI_WAITING,44,386,MUTED,255);
        text(UI_PEOPLE,184,412,MUTED,255);
        text(UI_MODE,248,386,MUTED,255);
        text(display_state[34] ? UI_AUTO : UI_MANUAL,248,410,TEAL,255);
        text(UI_HINT,448,386,INK,255);
        text(LIVE_STATUS && display_service[1:0]!=1 ? (display_service[1:0]==0 ? UI_LOADING_NOTE : UI_BASIC_NOTE) : UI_NOTICE,448,410,MUTED,255);
        text(UI_FOOTER,24,459,MUTED,255);
        text(UI_SIGNATURE,544,459,MUTED,255);
        // Native-size anti-aliased glyphs. No nearest-neighbour enlargement.
        if(x>=44 && x<264 && y>=198 && y<266) begin
            slot=x<88 ? 0 : x<132 ? 1 : x<176 ? 2 : x<220 ? 3 : 4;
            case(slot)
                0:digit=display_state[23:16]==8'h50 ? 11 : 10;
                1:digit=display_state[15:12];2:digit=display_state[11:8];
                3:digit=display_state[7:4];default:digit=display_state[3:0];
            endcase
            if(!has_call || digit>12)digit=12;
            text(UI_BIG_0+digit,44+slot*44,198,INK,255);
        end
        if(x>=448 && x<536 && y>=198 && y<266) begin
            slot=x<492 ? 0 : 1;
            digit=!has_call || display_state[27:24]==0 ? 12 : slot==0 ? 0 : display_state[27:24];
            if(digit>12)digit=12;
            text(UI_BIG_0+digit,448+slot*44,198,TEAL,255);
        end
        if(x>=44 && x<98 && y>=406 && y<436) begin
            slot=x<62 ? 0 : x<80 ? 1 : 2;
            case(slot)
                0:digit=display_state[43:36]/100;
                1:digit=(display_state[43:36]/10)%10;
                default:digit=display_state[43:36]%10;
            endcase
            text(UI_SMALL_0+digit,44+slot*18,406,TEAL,255);
        end
    end
endmodule

`timescale 1ns / 1ps
// One pixel/clock OSD with synchronous one-cycle font ROM and output register.
module osd_renderer #(parameter LIVE_STATUS=0,DUAL=0,MEDIA_LAYOUT=0) (
    input wire clk, rst_n,
    input wire [9:0] x, y,
    input wire de, line_start, frame_start,
    input wire [15:0] frame_cnt,
    input wire [127:0] qstate,
    input wire [63:0] param,
    input wire [7:0] service_status,
    input wire cover_mode,media_show,input wire [6:0] photo_alpha,
    input wire cfg_we,
    input wire [9:0] cfg_addr,
    input wire [31:0] cfg_wdata,
    output reg [13:0] font_addr,
    input wire [31:0] font_dout,
    output reg [23:0] osd_rgb,
    output reg [7:0] osd_alpha
);
    `include "medq_pixel_math.vh"
    reg [11:0] char_ram [0:319];
    reg [31:0] field_reg [0:15];
    reg [31:0] color_reg [0:15];
    reg dashboard_enabled;
    wire [13:0] legacy_addr,dual_addr;
    wire [3:0] legacy_column;
    wire [4:0] dual_column;
    wire [23:0] legacy_bg,legacy_fg,dual_bg,dual_fg;
    wire legacy_text,dual_text;
    wire [7:0] legacy_opacity,dual_opacity;
    wire [13:0] scene_addr=DUAL ? dual_addr : legacy_addr;
    wire [4:0] scene_column=DUAL ? dual_column : {1'b0,legacy_column};
    wire [23:0] scene_bg=DUAL ? dual_bg : legacy_bg,scene_fg=DUAL ? dual_fg : legacy_fg;
    wire scene_text=DUAL ? dual_text : legacy_text;
    wire [7:0] scene_opacity=DUAL ? dual_opacity : legacy_opacity;
    medq_ui_scene #(.LIVE_STATUS(LIVE_STATUS)) u_scene(.clk(clk),.rst_n(rst_n),.x(x),.y(y),.frame_start(frame_start),.qstate(qstate),.service_status(service_status),
        .font_addr(legacy_addr),.font_column(legacy_column),.background(legacy_bg),.foreground(legacy_fg),
        .text_active(legacy_text),.text_opacity(legacy_opacity));
    medq_dual_ui_scene #(.COMPACT_MAP(MEDIA_LAYOUT)) u_dual_scene(.clk(clk),.rst_n(rst_n),.x(x),.y(y),.frame_start(frame_start),.qstate(qstate),.service_status(service_status),
        .font_addr(dual_addr),.font_column(dual_column),.background(dual_bg),.foreground(dual_fg),
        .text_active(dual_text),.text_opacity(dual_opacity));
    integer n;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dashboard_enabled<=1;
            for (n=0;n<320;n=n+1) char_ram[n]<=0;
            for (n=0;n<16;n=n+1) begin field_reg[n]<=0; color_reg[n]<=32'hffffffff; end
        end else begin
            if (cfg_we) begin
                if (cfg_addr<320) char_ram[cfg_addr]<=cfg_wdata[11:0];
                else if (cfg_addr>=512 && cfg_addr<528) field_reg[cfg_addr-512]<=cfg_wdata;
                else if (cfg_addr>=640 && cfg_addr<656) color_reg[cfg_addr-640]<=cfg_wdata;
                else if (cfg_addr==768) dashboard_enabled<=cfg_wdata[0];
            end
            // Reserved live text slots, sampled from the atomic QSTATE snapshot.
            char_ram[240]<=qstate[23:16]==0 ? 12'd33 : {4'd0,qstate[23:16]}-12'd32;
            char_ram[241]<=12'd16+qstate[15:12];
            char_ram[242]<=12'd16+qstate[11:8];
            char_ram[243]<=12'd16+qstate[7:4];
            char_ram[244]<=12'd16+qstate[3:0];
            char_ram[245]<=0; char_ram[246]<=12'd50;
            char_ram[247]<=12'd16+qstate[27:24];
            char_ram[248]<=0; char_ram[249]<=12'd55;
            char_ram[250]<=12'd16+qstate[43:36]/100;
            char_ram[251]<=12'd16+(qstate[43:36]/10)%10;
            char_ram[252]<=12'd16+qstate[43:36]%10;
        end
    end
    integer f, scale, dx, dy, cell_w, cell_h, glyph, glyph_col, glyph_row;
    reg found;
    reg [4:0] column;
    reg [31:0] rgba;
    always @* begin
        font_addr=0; found=0; column=0; rgba=0;
        scale=1; dx=0; dy=0; cell_w=8; cell_h=16;
        glyph=0; glyph_col=0; glyph_row=0;
        for (f=0;f<16;f=f+1) begin
            scale=field_reg[f][22:21]+1;
            dx=(x-field_reg[f][10:1])/scale;
            dy=(y-field_reg[f][20:11])/scale;
            glyph=char_ram[{field_reg[f][31:27],3'd0}];
            cell_w=glyph<96 ? 8 : glyph<224 ? 16 : 32;
            cell_h=glyph<224 ? 16 : 48;
            if (!found && field_reg[f][0] && x>=field_reg[f][10:1] && y>=field_reg[f][20:11] &&
                dy<cell_h && dx<field_reg[f][26:23]*cell_w) begin
                glyph=char_ram[{field_reg[f][31:27],3'd0}+dx/cell_w];
                glyph_col=dx%cell_w; glyph_row=dy;
                if (glyph<96) font_addr=glyph*16+glyph_row;
                else if (glyph<224) font_addr=1536+(glyph-96)*16+glyph_row;
                else font_addr=3584+(glyph-224)*48+glyph_row;
                column=glyph_col;
                rgba=color_reg[f];
                found=1;
            end
        end
        if(!found && dashboard_enabled)font_addr=scene_addr;
    end
    reg found_q, de_q;
    reg [4:0] column_q;
    reg [31:0] rgba_q;
    reg scene_enabled_q,scene_text_q;
    reg [4:0] scene_column_q;
    reg [23:0] scene_bg_q,scene_fg_q;
    reg [7:0] scene_opacity_q;
    reg cover_q,media_q,photo_q;
    reg [7:0] photo_opacity_q;
    function [23:0] covered;
        input [23:0] bg,fg;
        input [1:0] coverage;
        input [7:0] opacity;
        integer channel;
        reg [7:0] alpha;
        reg [15:0] total;
        begin
            case(coverage)
                0:alpha=0;
                1:alpha=({1'b0,opacity}+9'd1)/9'd3;
                2:alpha=({opacity,1'b0}+9'd1)/9'd3;
                default:alpha=opacity;
            endcase
            for(channel=0;channel<3;channel=channel+1)begin
                total=bg[channel*8+:8]*(8'd255-alpha)+fg[channel*8+:8]*alpha+16'd127;
                covered[channel*8+:8]=medq_div255(total);
            end
        end
    endfunction
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            found_q<=0; de_q<=0; column_q<=0; rgba_q<=0;
            scene_enabled_q<=0;scene_text_q<=0;scene_column_q<=0;
            scene_bg_q<=0;scene_fg_q<=0;scene_opacity_q<=0;
            cover_q<=0;media_q<=0;photo_q<=0;photo_opacity_q<=0;
            osd_rgb<=0; osd_alpha<=0;
        end else begin
            found_q<=found; de_q<=de; column_q<=column; rgba_q<=rgba;
            scene_enabled_q<=dashboard_enabled;scene_text_q<=scene_text && !found;
            scene_column_q<=scene_column;scene_bg_q<=scene_bg;scene_fg_q<=scene_fg;scene_opacity_q<=scene_opacity;
            cover_q<=cover_mode;media_q<=media_show;
            photo_q<=x>=456 && x<608 && y>=298 && y<426;
            photo_opacity_q<=photo_alpha==64 ? 8'd255 : {photo_alpha[5:0],2'b00};
            if(MEDIA_LAYOUT && de_q && cover_q)begin
                osd_rgb<=24'heef3f6;osd_alpha<=media_q ? 8'd0 : 8'd255;
            end else if(MEDIA_LAYOUT && de_q && photo_q && param[40])begin
                osd_rgb<=24'hffffff;osd_alpha<=media_q ? 8'd255-photo_opacity_q : 8'd255;
            end else if (de_q && found_q && font_dout[31-column_q] && param[40]) begin
                osd_rgb<=rgba_q[23:0]; osd_alpha<=rgba_q[31:24];
            end else if(de_q && scene_enabled_q && param[40])begin
                // Both scenes use two-bit, four-level coverage glyphs.
                osd_rgb<=scene_text_q ? covered(scene_bg_q,scene_fg_q,font_dout[31-2*scene_column_q-:2],scene_opacity_q) : scene_bg_q;
                osd_alpha<=255;
            end else begin osd_rgb<=0; osd_alpha<=0; end
        end
    end
endmodule

`timescale 1ns/1ps
// V0.3 dual-clinic page: procedural geometry plus a two-bit coverage atlas held in
// the production 4K font window (virtual words 3584..7679). No frame buffer.
// All snapshots and animation update at every frame_start. QSTATE[64] controls
// calling summary only; queue counts and marquees stay live with either gate off.
module medq_dual_ui_scene #(parameter COMPACT_MAP=0)(input wire clk,rst_n,input wire [9:0] x,y,
 input wire frame_start,input wire [127:0] qstate,input wire [7:0] service_status,
 output reg [13:0] font_addr,output reg [4:0] font_column,
 output reg [23:0] background,foreground,output reg text_active,
 output reg [7:0] text_opacity);
 `include "medq_dual_layout.vh"
 `include "medq_patient_lookup.vh"
 localparam [23:0] PAGE=24'heef3f6,CARD=24'hffffff,SHADOW=24'hdfe7ec,LINE=24'he3eaef,
  INK=24'h17324a,MUTED=24'h647a8b,FAINT=24'hb3c0c9,TILE=24'hf4f7f9,PATH=24'he3eaef,
  TEAL=24'h078a86,TEAL_BG=24'he8f5f4,TEAL_HI=24'hbfe6e1,
  BLUE=24'h2f6db5,BLUE_BG=24'hecf1fa,BLUE_HI=24'hc8daf3,
  AMBER=24'ha95f17,AMBER_BG=24'hfff1dc,AMBER_HI=24'hffdcaa,
  GREEN=24'h1d8657,GREEN_BG=24'he3f3ea,RED=24'hbd3a2c,RED_BG=24'hfbe7e4,GREY_BG=24'heef2f5;
 localparam integer CARD_T=144,CARD_W=204,CARD_H=320,TICK_TOP_A=77,TICK_TOP_B=111;
 // The 592-pixel strip is a ring: a pixel leaving x24 re-enters at x615
 // on the same one-pixel step. New messages start centered in that ring.
 localparam [9:0] SCROLL_LAST=591;
 function [9:0] subtitle_home;
  input [31:0] row;input [15:0] msg;input room_b;
  reg [3:0] kind,letter,hi,lo;reg [1:0] state;
  reg [5:0] person;reg [31:0] meta;
  reg [9:0] number_w,room_w,name_w,width;
  reg [10:0] home_sum;
  begin
   kind=msg[14:11];state=row[19:18];
   letter=(room_b ? 11 : 10)+(row[22] && state!=0 ? 2 : 0);hi=row[7:4];lo=row[3:0];
   if(kind!=0)begin
    letter=(room_b ? 11 : 10)+(msg[10] ? 2 : 0);hi=msg[9:6];lo=msg[5:2];
    if(kind==3)state=1;else if(kind==4)state=2;
   end
   person=patient_id(room_b,letter>=12,{hi,lo});
   meta=d3_sprite(person==63 ? D3_TK_ANONYMOUS : D3_SURNAME_0+person);name_w={2'b00,meta[15:8]};
   number_w=d3_tick_adv(letter)+d3_tick_adv(hi)+d3_tick_adv(lo)-D3_TICK_TRACK;
   room_w=d3_tick_adv(room_b ? 11 : 10)-D3_TICK_TRACK+3+D3_W_TK_ROOM;
   if(kind==6 || kind==7 || kind==9)
    width=room_w+6+(kind==9 ? D3_W_TK_REJECT : kind==6 ? D3_W_TK_PAUSE : D3_W_TK_ENABLE);
   else if(kind==1 || kind==2 || kind==5 || kind==8)
    width=number_w+12+name_w+(kind==1 ? D3_W_TK_TAKEN : kind==2 ? D3_W_TK_RETURN_TAKEN : kind==5 ? D3_W_TK_LEFT : D3_W_TK_MISSED);
   else if(state==1)
    width=D3_W_TK_QING+number_w+name_w+D3_W_TK_DAO+room_w+D3_W_TK_JIU+26;
   else if(state==2)width=number_w+12+name_w+D3_W_TK_ARRIVED;
   else width=room_w+6+(row[17:8]==0 ? D3_W_TK_NONE : D3_W_TK_SOON);
   home_sum=11'd593+{1'b0,width};subtitle_home=home_sum[10:1];
  end
 endfunction

 //--------------------------------------------------------------------------
 // Frame snapshot and animation state (updated at every frame_start)
 //--------------------------------------------------------------------------
 reg [127:0] frame_state;
 reg [7:0] frame_service;
 reg [9:0] scroll_a,scroll_b;
 reg [1:0] scroll_phase,pending_refresh;
 reg [24:0] seen_a,seen_b;
 reg [15:0] seen_message_a,seen_message_b;
 reg [1:0] seen_run;
 reg seen_ready;
 reg [7:0] seen_service;
 wire changed_a=qstate[24:0]!=seen_a || qstate[83:68]!=seen_message_a || qstate[66]!=seen_run[0] ||
   qstate[65]!=seen_ready || service_status!=seen_service;
 wire changed_b=qstate[56:32]!=seen_b || qstate[99:84]!=seen_message_b || qstate[67]!=seen_run[1] ||
   qstate[65]!=seen_ready || service_status!=seen_service;
 reg [6:0] breath;
 reg [4:0] age_a,age_b;
 reg [23:0] glow,route_a,route_b,flash_a,flash_b;
 // a + (b-a)*t/64 per channel; shift-add only, evaluated once per frame.
 function [23:0] mix;
  input [23:0] a,b;input [5:0] t;
  integer c,k;reg signed [9:0] d;reg signed [16:0] acc;
  begin
   for(c=0;c<3;c=c+1)begin
    d=$signed({2'b00,b[c*8+:8]})-$signed({2'b00,a[c*8+:8]});acc=0;
    for(k=0;k<6;k=k+1)if(t[k])acc=acc+(d<<<k);
    mix[c*8+:8]=a[c*8+:8]+acc[13:6];
   end
  end
 endfunction
 // Ease-out flash after a new call or recall: strong first, settles in 16 frames.
 function [5:0] ease;
  input [4:0] age;
  begin
   case(age)
    0:ease=63;1:ease=55;2:ease=48;3:ease=41;4:ease=35;5:ease=29;6:ease=24;7:ease=19;
    8:ease=15;9:ease=11;10:ease=8;11:ease=6;12:ease=4;13:ease=2;14:ease=1;default:ease=0;
   endcase
  end
 endfunction
 wire [5:0] tri_wave=breath[6] ? ~breath[5:0] : breath[5:0]; // 0..63..0 over 128 frames
 // Latch even short events and changes which return to the same value before
 // a frame. Pixel state is still swapped atomically at the next frame_start.
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin seen_a<=0;seen_b<=0;seen_message_a<=0;seen_message_b<=0;seen_run<=0;seen_ready<=0;seen_service<=0;pending_refresh<=0;end
  else begin
   seen_a<=qstate[24:0];seen_b<=qstate[56:32];seen_run<=qstate[67:66];
   seen_message_a<=qstate[83:68];seen_message_b<=qstate[99:84];
   seen_ready<=qstate[65];seen_service<=service_status;
   if(frame_start)pending_refresh<=0;
   else pending_refresh<=pending_refresh | {changed_b,changed_a};
  end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   frame_state<=0;frame_service<=0;scroll_a<=subtitle_home(0,0,0);scroll_b<=subtitle_home(0,0,1);scroll_phase<=0;
   breath<=0;age_a<=16;age_b<=16;glow<=AMBER_BG;route_a<=TEAL_HI;route_b<=BLUE_HI;flash_a<=TEAL_BG;flash_b<=BLUE_BG;
  end else if(frame_start)begin
   frame_state<=qstate;frame_service<=service_status;
   if(pending_refresh[0] || changed_a)begin scroll_a<=subtitle_home(qstate[31:0],qstate[83:68],0);scroll_phase[0]<=0;end
   else begin scroll_phase[0]<=!scroll_phase[0];if(scroll_phase[0])scroll_a<=scroll_a==SCROLL_LAST ? 0 : scroll_a+1'b1;end
   if(pending_refresh[1] || changed_b)begin scroll_b<=subtitle_home(qstate[63:32],qstate[99:84],1);scroll_phase[1]<=0;end
   else begin scroll_phase[1]<=!scroll_phase[1];if(scroll_phase[1])scroll_b<=scroll_b==SCROLL_LAST ? 0 : scroll_b+1'b1;end
   breath<=breath+1'b1;
   if(qstate[19:18]==1 && {qstate[22:18],qstate[7:0]}!={frame_state[22:18],frame_state[7:0]})age_a<=0;
   else if(age_a<16)age_a<=age_a+1'b1;
   if(qstate[51:50]==1 && {qstate[54:50],qstate[39:32]}!={frame_state[54:50],frame_state[39:32]})age_b<=0;
   else if(age_b<16)age_b<=age_b+1'b1;
   glow<=mix(AMBER_BG,AMBER_HI,tri_wave);
   route_a<=mix(TEAL_HI,TEAL,tri_wave);route_b<=mix(BLUE_HI,BLUE,tri_wave);
   flash_a<=mix(TEAL_BG,TEAL_HI,ease(age_a));flash_b<=mix(BLUE_BG,BLUE_HI,ease(age_b));
  end
 end

 //--------------------------------------------------------------------------
 // Pixel helpers
 //--------------------------------------------------------------------------
 // Rounded rectangle coverage: 0 outside, 1 half-covered corner edge, 2 inside.
 function [1:0] rr;
  input [9:0] px,py,l,t,w,h;input [3:0] r;
  reg [9:0] row;reg [4:0] c;
  begin
   rr=0;
   if(py>=t && py<t+h && px>=l && px<l+w)begin
    row=py<t+r ? py-t : py>=t+h-r ? t+h-1-py : 10'd15;
    c=d3_cut(r,row);
    if(px>=l+c[3:0]+c[4] && px<l+w-c[3:0]-c[4])rr=2;
    else if(c[4] && (px==l+c[3:0] || px==l+w-1-c[3:0]))rr=1;
   end
  end
 endfunction
 function [23:0] avg;
  input [23:0] a,b;integer c;reg [8:0] s;
  begin for(c=0;c<3;c=c+1)begin s=a[c*8+:8]+b[c*8+:8];avg[c*8+:8]=s[8:1];end end
 endfunction
 task fill;
  input [1:0] cov;input [23:0] color;
  begin if(cov==2)background=color;else if(cov==1)background=avg(background,color);end
 endtask
 // Non-overlapping interior objects have a known underlay. Keep their rounded
 // edge average independent instead of chaining it through all earlier fills.
 task fill_on;
  input [1:0] cov;input [23:0] color,under;
  begin if(cov==2)background=color;else if(cov==1)background=avg(under,color);end
 endtask
 reg [7:0] ax,ay;
 reg signed [11:0] sprite_x;
 // Native-size coverage sprite; the clip test happens before any ROM address is formed.
 task spr;
  input [6:0] id;input signed [11:0] left,top;input [23:0] color;
  reg [31:0] m;reg signed [12:0] u,v;
  begin
   m=d3_sprite(id);u=sprite_x-left;v=$signed({1'b0,y})-top;
   if(u>=0 && v>=0 && u<$signed({1'b0,m[15:8]}) && v<$signed({1'b0,m[7:0]}))begin
    ax=m[31:24]+u;ay=m[23:16]+v;
    font_addr=(id>=D3_EXTRA0 ? D3_EXTRA_BASE : D3_ATLAS_BASE)+{ay,ax[7:4]};font_column={1'b0,ax[3:0]};
    text_active=1;foreground=color;
   end
  end
 endtask

 //--------------------------------------------------------------------------
 // Scene
 //--------------------------------------------------------------------------
 // All screen/scroll positions fit -2048..2047; do not infer 32-bit pixel math.
 reg signed [11:0] cl,s,p,ty,gw,aL,a1,a2,tw;
 reg [31:0] rd;
 reg [15:0] message;
 reg [3:0] message_kind;
 reg rb;
 reg [1:0] st;
 reg [3:0] lg,d1,d2,tens,ones;
 reg [4:0] count;
 reg [23:0] rc,rbg,rflash,pill_bg,pill_fg,svc_bg,svc_fg;
 reg [6:0] svc_id,name_sprite;reg [5:0] name_id;reg [31:0] name_meta;reg [7:0] name_width;
 always @* begin
  font_addr=D3_ATLAS_BASE;font_column=0;text_active=0;text_opacity=255;foreground=INK;background=PAGE;
  name_id=63;name_sprite=D3_TK_ANONYMOUS;name_meta=0;name_width=D3_W_TK_ANONYMOUS;
  ax=0;ay=0;cl=0;s=0;p=0;ty=0;gw=0;aL=0;a1=0;a2=0;tw=0;sprite_x=$signed({2'b00,x});rd=0;rb=0;st=0;lg=0;d1=0;d2=0;
  tens=0;ones=0;count=0;message=0;message_kind=0;rc=TEAL;rbg=TEAL_BG;rflash=TEAL_BG;pill_bg=GREY_BG;pill_fg=MUTED;
  case(frame_service[1:0])
   0:begin svc_id=D3_SVC_LOADING;svc_bg=GREY_BG;svc_fg=MUTED;gw=D3_W_SVC_LOADING;end
   1:begin svc_id=D3_SVC_READY;svc_bg=TEAL_BG;svc_fg=TEAL;gw=D3_W_SVC_READY;end
   2:begin svc_id=D3_SVC_BASIC;svc_bg=AMBER_BG;svc_fg=AMBER;gw=D3_W_SVC_BASIC;end
   default:begin svc_id=D3_SVC_FAULT;svc_bg=RED_BG;svc_fg=RED;gw=D3_W_SVC_FAULT;end
  endcase

  // Header: logo, title, live service pill.
  if(y<64)background=CARD;
  if(y==63)background=LINE;
  if(y<64)begin
   fill_on(rr(x,y,16,12,40,40,8),TEAL,CARD);
   if((x>=32 && x<40 && y>=20 && y<44)||(x>=24 && x<48 && y>=28 && y<36))background=CARD;
   spr(D3_TITLE,68,10,INK);
   spr(D3_SUB,69,38,MUTED);
   fill_on(rr(x,y,500,18,124,28,12),svc_bg,CARD);
   p=500+(124-16-gw)/2;
   fill_on(rr(x,y,p,28,8,8,4),svc_fg,svc_bg);
   spr(svc_id,p+16,23,svc_fg);
  end

  // Two subtitle strips. Glyphs are clipped to x24..615 before any address is formed.
  if(y>=72 && y<136)begin
   rb=y>=104;rd=rb ? frame_state[63:32] : frame_state[31:0];
   rc=rb ? BLUE : TEAL;
   fill_on(rr(x,y,16,rb ? 106 : 72,608,30,6),rb ? BLUE_BG : TEAL_BG,PAGE);
   if(x>=18 && x<21 && y>=(rb ? 113 : 79) && y<(rb ? 129 : 95))background=rc;
   if(x>=24 && x<616)begin
    st=rd[19:18];lg=(rb ? 11 : 10)+(rd[22] && st!=0 ? 2 : 0);d1=rd[7:4];d2=rd[3:0];
    message=rb ? frame_state[99:84] : frame_state[83:68];message_kind=message[14:11];
    if(message_kind!=0)begin
     lg=(rb ? 11 : 10)+(message[10] ? 2 : 0);d1=message[9:6];d2=message[5:2];
     if(message_kind==3)st=1;else if(message_kind==4)st=2;
    end
    name_id=patient_id(rb,lg>=12,{d1,d2});name_sprite=name_id==63 ? D3_TK_ANONYMOUS : D3_SURNAME_0+name_id;
    name_meta=d3_sprite(name_sprite);name_width=name_meta[15:8];
    aL=d3_tick_adv(lg);a1=d3_tick_adv(d1);a2=d3_tick_adv(d2);tw=aL+a1+a2-D3_TICK_TRACK;
    // Fold only the subtitle's sample coordinate, not the glyphs or the ROM.
    // Every ring pixel is rendered once; no duplicate sprite datapath needed.
    sprite_x=$signed({2'b00,x})-12'sd24+$signed({2'b00,(rb ? scroll_b : scroll_a)});
    if(sprite_x>=12'sd592)sprite_x=sprite_x-12'sd592;
    s=0;ty=rb ? TICK_TOP_B : TICK_TOP_A;
    if(message_kind==6 || message_kind==7 || message_kind==9)begin
     spr(D3_TICK0+(rb ? 11 : 10),s,ty,rc);
     p=s+d3_tick_adv(rb ? 11 : 10)-D3_TICK_TRACK+3;spr(D3_TK_ROOM,p,ty,INK);
     p=p+D3_W_TK_ROOM+6;
     if(message_kind==6)spr(D3_TK_PAUSE,p,ty,INK);
     else if(message_kind==7)spr(D3_TK_ENABLE,p,ty,INK);
     else spr(D3_TK_REJECT,p,ty,INK);
    end else if(message_kind==1 || message_kind==2 || message_kind==5 || message_kind==8)begin
     spr(D3_TICK0+lg,s,ty,rc);spr(D3_TICK0+d1,s+aL,ty,rc);spr(D3_TICK0+d2,s+aL+a1,ty,rc);
     p=s+tw+6;spr(name_sprite,p,ty,INK);p=p+name_width+6;
     case(message_kind)
      1:spr(D3_TK_TAKEN,p,ty,INK);2:spr(D3_TK_RETURN_TAKEN,p,ty,INK);
      5:spr(D3_TK_LEFT,p,ty,INK);default:spr(D3_TK_MISSED,p,ty,INK);
     endcase
    end else if(st==1)begin
     spr(D3_TK_QING,s,ty,INK);
     p=s+D3_W_TK_QING+6;
     spr(D3_TICK0+lg,p,ty,rc);spr(D3_TICK0+d1,p+aL,ty,rc);spr(D3_TICK0+d2,p+aL+a1,ty,rc);
     p=p+tw+6;spr(name_sprite,p,ty,INK);p=p+name_width+3;spr(D3_TK_DAO,p,ty,INK);
     p=p+D3_W_TK_DAO+6;spr(D3_TICK0+(rb ? 11 : 10),p,ty,rc);
     p=p+d3_tick_adv(rb ? 11 : 10)-D3_TICK_TRACK+3;spr(D3_TK_ROOM,p,ty,INK);
     spr(D3_TK_JIU,p+D3_W_TK_ROOM+5,ty,INK);
    end else if(st==2)begin
     spr(D3_TICK0+lg,s,ty,rc);spr(D3_TICK0+d1,s+aL,ty,rc);spr(D3_TICK0+d2,s+aL+a1,ty,rc);
     p=s+tw+6;spr(name_sprite,p,ty,INK);
     spr(D3_TK_ARRIVED,p+name_width+6,ty,INK);
    end else begin
     spr(D3_TICK0+lg,s,ty,rc);
     p=s+aL-D3_TICK_TRACK+3;spr(D3_TK_ROOM,p,ty,INK);
     if(rd[17:8]==0)spr(D3_TK_NONE,p+D3_W_TK_ROOM+6,ty,MUTED);
     else spr(D3_TK_SOON,p+D3_W_TK_ROOM+6,ty,INK);
    end
    // No edge fade: preserve every coverage pixel across the left/right seam.
   end
  end

  // Panel shadows and surfaces.
  if(x<224)begin
   fill(rr(x,y,16,CARD_T+2,CARD_W,CARD_H,8),SHADOW);
   fill(rr(x,y,16,CARD_T,CARD_W,CARD_H,8),CARD);
  end else if(x<436)begin
   fill(rr(x,y,228,CARD_T+2,CARD_W,CARD_H,8),SHADOW);
   fill(rr(x,y,228,CARD_T,CARD_W,CARD_H,8),CARD);
  end else begin
   fill(rr(x,y,440,CARD_T+2,184,CARD_H,8),SHADOW);
   fill(rr(x,y,440,CARD_T,184,CARD_H,8),CARD);
  end

  // A/B clinic cards share one datapath selected by x.
  if(y>=CARD_T && y<CARD_T+CARD_H && x>=16 && x<432)begin
   rb=x>=224;cl=rb ? 228 : 16;rd=rb ? frame_state[63:32] : frame_state[31:0];
   st=rd[19:18];lg=rb ? 11 : 10;d1=rd[7:4];d2=rd[3:0];
   rc=rb ? BLUE : TEAL;rbg=rb ? BLUE_BG : TEAL_BG;rflash=rb ? flash_b : flash_a;
   case(st)
    1:begin pill_bg=glow;pill_fg=AMBER;end
    2:begin pill_bg=GREEN_BG;pill_fg=GREEN;end
    default:begin pill_bg=GREY_BG;pill_fg=MUTED;end
   endcase
   // Header row: room badge, name, state pill.
   fill_on(rr(x,y,cl+16,160,28,28,6),rc,CARD);
   spr(D3_MID0+(rb ? 11 : 10),cl+16+(30-d3_mid_adv(rb ? 11 : 10)+D3_MID_TRACK)/2-1,164,CARD);
   spr(D3_ROOM,cl+52,163,INK);
   fill_on(rr(x,y,cl+124,162,64,24,12),pill_bg,CARD);
   case(st)
    1:spr(D3_PILL_CALL,cl+124+(64-D3_W_PILL_CALL)/2,165,pill_fg);
    2:spr(D3_PILL_VISIT,cl+124+(64-D3_W_PILL_VISIT)/2,165,pill_fg);
    default:spr(D3_PILL_IDLE,cl+124+(64-D3_W_PILL_IDLE)/2,165,pill_fg);
   endcase
   if(y==200 && x>=cl+16 && x<cl+188)background=LINE;
   spr(D3_CURRENT,cl+16,212,MUTED);
   if(rd[22] && st!=0)lg=rb ? 13 : 12;
   // Current number panel; the tint flashes and eases out on each new call/recall.
   fill_on(rr(x,y,cl+16,236,172,100,8),st==1 ? rflash : st==2 ? rbg : TILE,CARD);
   aL=d3_big_adv(lg);a1=d3_big_adv(d1);a2=d3_big_adv(d2);
   if(st==0)begin
    p=cl+102-(aL+60)/2;
    spr(D3_BIG0+lg,p,246,FAINT);
    if(y>=275 && y<281 && ((x>=p+aL+4 && x<p+aL+26)||(x>=p+aL+34 && x<p+aL+56)))background=FAINT;
    spr(D3_DET_NONE,cl+102-D3_W_DET_NONE/2,306,MUTED);
   end else begin
    tw=aL+a1+a2-D3_BIG_TRACK;p=cl+102-tw/2;
    spr(D3_BIG0+lg,p,246,st==1 ? rc : INK);spr(D3_BIG0+d1,p+aL,246,st==1 ? rc : INK);
    spr(D3_BIG0+d2,p+aL+a1,246,st==1 ? rc : INK);
    if(st==1)begin
     a1=d3_tick_adv({2'b00,rd[21:20]})-D3_TICK_TRACK;
     p=cl+102-(D3_W_DET_DI+a1+D3_W_DET_CALL+6)/2;
     spr(D3_DET_DI,p,306,MUTED);spr(D3_TICK0+rd[21:20],p+D3_W_DET_DI+3,305,AMBER);
     spr(D3_DET_CALL,p+D3_W_DET_DI+a1+6,306,MUTED);
    end else spr(D3_DET_VISIT,cl+102-D3_W_DET_VISIT/2,306,GREEN);
   end
   // Waiting / return counters.
   fill_on(rr(x,y,cl+16,348,82,68,6),TILE,CARD);fill_on(rr(x,y,cl+106,348,82,68,6),TILE,CARD);
   spr(D3_WAIT,cl+28,356,MUTED);spr(D3_RET,cl+118,356,MUTED);
   p=x<cl+102 ? cl+28 : cl+118;count=x<cl+102 ? rd[12:8] : rd[17:13];
   tens=count>=10 ? 1 : 0;ones=count>=10 ? count-10 : count[3:0];
   if(tens!=0)begin
    spr(D3_MID0+1,p,384,rc);spr(D3_MID0+ones,p+d3_mid_adv(1),384,rc);
    p=p+d3_mid_adv(1)+d3_mid_adv(ones)-D3_MID_TRACK;
   end else begin
    spr(D3_MID0+ones,p,384,rc);p=p+d3_mid_adv(ones)-D3_MID_TRACK;
   end
   spr(D3_UNIT,p+4,388,MUTED);
   if(rd[23])spr(D3_NOTE_REJECT,cl+16,431,RED);
   else spr(D3_NOTE_RULE,cl+16,432,MUTED);
  end

  // Sample wayfinding map; the active route pulses while a room is calling.
  if(y>=CARD_T && y<CARD_T+CARD_H && x>=440 && x<624)begin
   if(COMPACT_MAP)begin
    spr(D3_MAP_TITLE,456,158,INK);
    fill_on(rr(x,y,456,186,152,100,6),TILE,CARD);
    fill_on(rr(x,y,464,194,64,30,4),frame_state[19:18]==1 ? route_a : TEAL_BG,TILE);
    fill_on(rr(x,y,536,194,64,30,4),frame_state[51:50]==1 ? route_b : BLUE_BG,TILE);
    if(frame_state[19:18]==1)fill(rr(x,y,466,196,60,26,4),TEAL_BG);
    if(frame_state[51:50]==1)fill(rr(x,y,538,196,60,26,4),BLUE_BG);
    gw=d3_tick_adv(10)-D3_TICK_TRACK;
    spr(D3_TICK0+10,496-(gw+3+D3_W_MAP_ROOM)/2,199,TEAL);spr(D3_MAP_ROOM,496-(gw+3+D3_W_MAP_ROOM)/2+gw+3,201,INK);
    gw=d3_tick_adv(11)-D3_TICK_TRACK;
    spr(D3_TICK0+11,568-(gw+3+D3_W_MAP_ROOM)/2,199,BLUE);spr(D3_MAP_ROOM,568-(gw+3+D3_W_MAP_ROOM)/2+gw+3,201,INK);
    fill_on(rr(x,y,464,232,136,16,4),PATH,TILE);
    if(frame_state[19:18]==1 && x>=494 && x<498 && y>=224 && y<254)background=route_a;
    if(frame_state[51:50]==1 && x>=566 && x<570 && y>=224 && y<254)background=route_b;
    spr(D3_MAP_CORRIDOR,532-D3_W_MAP_CORRIDOR/2,232,MUTED);
    fill_on(rr(x,y,464,254,136,24,4),CARD,TILE);
    spr(D3_MAP_AREA,532-D3_W_MAP_AREA/2,256,INK);
    if(y==290 && x>=456 && x<608)background=LINE;
    if(y==433 && x>=456 && x<608)background=LINE;
   end else begin
   spr(D3_MAP_TITLE,456,163,INK);
   fill_on(rr(x,y,456,196,152,192,6),TILE,CARD);
   fill_on(rr(x,y,464,204,64,48,6),frame_state[19:18]==1 ? route_a : TEAL_BG,TILE);
   fill_on(rr(x,y,536,204,64,48,6),frame_state[51:50]==1 ? route_b : BLUE_BG,TILE);
   if(frame_state[19:18]==1)fill(rr(x,y,466,206,60,44,4),TEAL_BG);
   if(frame_state[51:50]==1)fill(rr(x,y,538,206,60,44,4),BLUE_BG);
   gw=d3_mid_adv(10)-D3_MID_TRACK;
   spr(D3_MID0+10,496-(gw+3+D3_W_MAP_ROOM)/2,218,TEAL);spr(D3_MAP_ROOM,496-(gw+3+D3_W_MAP_ROOM)/2+gw+3,222,INK);
   gw=d3_mid_adv(11)-D3_MID_TRACK;
   spr(D3_MID0+11,568-(gw+3+D3_W_MAP_ROOM)/2,218,BLUE);spr(D3_MAP_ROOM,568-(gw+3+D3_W_MAP_ROOM)/2+gw+3,222,INK);
   fill_on(rr(x,y,464,260,136,24,4),PATH,TILE);
   if(frame_state[19:18]==1 && x>=494 && x<498 && y>=252 && y<292)background=route_a;
   if(frame_state[51:50]==1 && x>=566 && x<570 && y>=252 && y<292)background=route_b;
   spr(D3_MAP_CORRIDOR,532-D3_W_MAP_CORRIDOR/2,264,MUTED);
   fill_on(rr(x,y,464,292,136,56,6),CARD,TILE);
   spr(D3_MAP_AREA,532-D3_W_MAP_AREA/2,311,INK);
   if(y==365 && ((x>=476 && x<514)||(x>=550 && x<588)))background=FAINT;
   spr(D3_MAP_ENTRY,532-D3_W_MAP_ENTRY/2,358,MUTED);
   if(y==404 && x>=456 && x<608)background=LINE;
   spr(D3_MAP_NOTE1,532-D3_W_MAP_NOTE1/2,426,MUTED);
   end
  end
 end
endmodule

`timescale 1ns/1ps
// R09: each clinic holds its request. No overwriting pending event slot.
module medq_dual_announcer #(parameter integer TONE_CYCLES=3750000)(
 input wire clk,rst_n,voice_ready,input wire [1:0] running,request,doctor_event,
 input wire [15:0] request_ticket,input wire [1:0] request_return,input wire [127:0] qstate,
 output wire [1:0] grant,announcement_start,output reg [5:0] clip_sel,
 input wire [21:0] clip_base,clip_samples,output wire play_req,
 output wire [21:0] play_base,play_samples,input wire play_busy,play_done,
 output wire pcm_abort,output wire fallback_tone,output wire announcing,
 output reg active_room,output reg [7:0] active_ticket);
 localparam IDLE=0,WAIT_BUSY=1,WAIT_DONE=2,SELECT=3,ISSUE=4,DRAIN=5,TONE=6;
 reg [2:0] state;reg [3:0] step;
 `include "medq_patient_lookup.vh"
 wire [5:0] name_id=patient_id(active_room,active_return,active_ticket);
 reg turn;
 reg active_return;
 // A stopped room releases the single player after the issued SDRAM burst
 // drains. Replay only this same patient on resume, without a second grant.
 reg [1:0] replay,replay_return;
 reg [15:0] replay_ticket;
 reg [31:0] tone_left;
 wire [1:0] replay_valid;
 assign replay_valid[0]=replay[0] && !doctor_event[0] && qstate[19:18]==1 &&
   qstate[7:0]==replay_ticket[7:0] && qstate[22]==replay_return[0];
 assign replay_valid[1]=replay[1] && !doctor_event[1] && qstate[51:50]==1 &&
   qstate[39:32]==replay_ticket[15:8] && qstate[54]==replay_return[1];
 wire [1:0] eligible=running & (request | replay_valid) & ~doctor_event;
 wire choose_b=eligible[1] && (!eligible[0] || turn);
 wire replay_start=replay_valid[choose_b];
 wire available=state==IDLE && !play_busy;
 wire start=available && (|eligible);
 wire full_voice=voice_ready && clip_samples!=0;
 wire [31:0] active_state=active_room ? qstate[63:32] : qstate[31:0];
 wire stale=
   (doctor_event[active_room] || active_state[19:18]!=1 || active_state[7:0]!=active_ticket || active_state[22]!=active_return);
 wire cancel=state!=IDLE && state!=DRAIN && (stale || !running[active_room]);
 assign grant=start && !replay_start ? (choose_b ? 2'b10 : 2'b01) : 2'b00;
 // Includes replay of an interrupted patient, which deliberately has no grant.
 assign announcement_start=start ? (choose_b ? 2'b10 : 2'b01) : 2'b00;
 assign play_req=!cancel && ((start && full_voice) ||
   (state==ISSUE && running[active_room] && !play_busy && clip_samples!=0));
 assign play_base=clip_base;
 assign play_samples=clip_samples;
 assign pcm_abort=cancel && play_busy;
 assign fallback_tone=state==TONE && running[active_room] && !cancel;
 assign announcing=state!=IDLE;
 always @* begin
  if(state==IDLE)clip_sel=1;
  else case(step)
   0:clip_sel=1;
   1:clip_sel=active_return ? (active_room ? 20 : 19) : (active_room ? 17 : 2);
   2:clip_sel=3+active_ticket[7:4];
   3:clip_sel=3+active_ticket[3:0];
   4:clip_sel=51;
   5:clip_sel=name_id==63 ? 53 : 6'd21+name_id;
   6:clip_sel=52;
   7:clip_sel=active_room ? 15 : 14;
   default:clip_sel=18;
  endcase
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=IDLE;step<=0;turn<=0;tone_left<=0;active_room<=0;active_ticket<=0;active_return<=0;replay<=0;replay_ticket<=0;replay_return<=0;end
  else begin
   replay<=replay_valid;
   if(cancel)begin
    state<=play_busy ? DRAIN : IDLE;tone_left<=0;
    if(!stale)begin
     replay[active_room]<=1;
     if(active_room)replay_ticket[15:8]<=active_ticket;else replay_ticket[7:0]<=active_ticket;
     replay_return[active_room]<=active_return;
    end
   end
  else if(state==DRAIN)begin if(!play_busy)state<=IDLE;end
  else begin
   case(state)
    IDLE:if(start)begin
     active_room<=choose_b;
     active_ticket<=replay_start ? (choose_b ? replay_ticket[15:8] : replay_ticket[7:0]) :
       (choose_b ? request_ticket[15:8] : request_ticket[7:0]);
     active_return<=replay_start ? replay_return[choose_b] : request_return[choose_b];
     replay[choose_b]<=0;
     turn<=!choose_b;step<=0;
     if(full_voice)state<=WAIT_BUSY;else begin state<=TONE;tone_left<=TONE_CYCLES;end
    end
    WAIT_BUSY:if(play_done)begin if(step==8)state<=IDLE;else begin step<=step+1'b1;state<=SELECT;end end else if(play_busy)state<=WAIT_DONE;
    WAIT_DONE:if(play_done)begin if(step==8)state<=IDLE;else begin step<=step+1'b1;state<=SELECT;end end
    SELECT:state<=ISSUE;
    ISSUE:if(clip_samples==0)begin if(step==8)state<=IDLE;else begin step<=step+1'b1;state<=SELECT;end end
      else if(!play_busy)state<=WAIT_BUSY;
    DRAIN:if(!play_busy)state<=IDLE;
    TONE:if(tone_left<=1)begin state<=IDLE;tone_left<=0;end else tone_left<=tone_left-1'b1;
    default:state<=IDLE;
   endcase
  end
  end
 end
endmodule

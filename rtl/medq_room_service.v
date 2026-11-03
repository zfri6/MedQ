`timescale 1ns/1ps
// R02-R07/R13: a single clinic owns its queues, allocator and patient lifetime.
module medq_room_service #(
 parameter integer AW=4, MAX_TICKET=99,
 parameter [63:0] INTERVAL_CYCLES=64'd25000000*64'd30
)(input wire clk,rst_n,running,ev_normal,ev_return,doctor_event,grant,
 output wire request,output wire [7:0] request_ticket,output wire request_return,
 output reg [1:0] state,output reg [7:0] ticket,output reg current_return,
 output reg [1:0] calls,output reg [AW:0] normal_count,return_count,
 output reg rejected,output reg [7:0] accepted,completed,missed,
 output reg [15:0] subtitle);
 function integer bits;input [63:0] n;reg [63:0] v;begin v=n-1;bits=0;while(v>0)begin bits=bits+1;v=v>>1;end if(bits<1)bits=1;end endfunction
 function [7:0] inc_bcd;input [7:0] n;begin inc_bcd=n[3:0]==9 ? {n[7:4]+4'd1,4'd0} : n+8'd1;end endfunction
 localparam integer DEPTH=2**AW,TW=bits(INTERVAL_CYCLES);
 localparam IDLE=0,WAIT_ARRIVAL=1,IN_VISIT=2;
 reg [7:0] normal_fifo[0:DEPTH-1],return_fifo[0:DEPTH-1];
 reg [AW-1:0] nw,nr,rw,rr;
 reg [6:0] next_normal,next_return;
 reg [7:0] normal_bcd,return_bcd;
 reg [TW-1:0] elapsed;
 wire first_grant=grant && request && state==IDLE;
 wire pop_r=first_grant && return_count!=0;
 wire pop_n=first_grant && return_count==0;
 wire take_r=ev_return && next_return<=MAX_TICKET && (return_count<DEPTH || pop_r);
 wire take_n=ev_normal && next_normal<=MAX_TICKET && (normal_count<DEPTH || pop_n);
 wire due=elapsed==INTERVAL_CYCLES-1;
 reg was_running;
 // Persistent latest operation: epoch[15], kind[14:11], return[10], BCD[9:2].
 // Doctor/timeout/call take precedence over simultaneous queue notifications.
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin subtitle<=0;was_running<=0;end
  else begin
   was_running<=running;
   if(doctor_event && state==WAIT_ARRIVAL)subtitle<={~subtitle[15],4'd4,current_return,ticket,2'b00};
   else if(doctor_event && state==IN_VISIT)subtitle<={~subtitle[15],4'd5,current_return,ticket,2'b00};
   else if(running && state==WAIT_ARRIVAL && calls==3 && due)subtitle<={~subtitle[15],4'd8,current_return,ticket,2'b00};
   else if(running && grant && request)subtitle<={~subtitle[15],4'd3,request_return,request_ticket,2'b00};
   else if(running!=was_running)subtitle<={~subtitle[15],running ? 4'd7 : 4'd6,1'b0,8'd0,2'b00};
   else if((ev_return && !take_r)||(ev_normal && !take_n))subtitle<={~subtitle[15],4'd9,1'b0,8'd0,2'b00};
   else if(take_r)subtitle<={~subtitle[15],4'd2,1'b1,return_bcd,2'b00};
   else if(take_n)subtitle<={~subtitle[15],4'd1,1'b0,normal_bcd,2'b00};
  end
 end
 // A newly accepted return blocks an unstarted ordinary candidate on this edge.
 assign request=running && !doctor_event &&
   ((state==IDLE && (return_count!=0 || (normal_count!=0 && !ev_return))) ||
    (state==WAIT_ARRIVAL && calls<3 && due));
 assign request_ticket=state==IDLE ? (return_count!=0 ? return_fifo[rr] : normal_fifo[nr]) : ticket;
 assign request_return=state==IDLE ? return_count!=0 : current_return;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;ticket<=0;current_return<=0;calls<=0;normal_count<=0;return_count<=0;
   nw<=0;nr<=0;rw<=0;rr<=0;next_normal<=1;next_return<=1;normal_bcd<=1;return_bcd<=1;elapsed<=0;
   rejected<=0;accepted<=0;completed<=0;missed<=0;
  end else begin
   if(take_r)begin return_fifo[rw]<=return_bcd;rw<=rw+1'b1;next_return<=next_return+1'b1;return_bcd<=inc_bcd(return_bcd);end
   if(take_n)begin normal_fifo[nw]<=normal_bcd;nw<=nw+1'b1;next_normal<=next_normal+1'b1;normal_bcd<=inc_bcd(normal_bcd);end
   if(pop_r)rr<=rr+1'b1;
   if(pop_n)nr<=nr+1'b1;
   case({take_r,pop_r})2'b10:return_count<=return_count+1'b1;2'b01:return_count<=return_count-1'b1;default:return_count<=return_count;endcase
   case({take_n,pop_n})2'b10:normal_count<=normal_count+1'b1;2'b01:normal_count<=normal_count-1'b1;default:normal_count<=normal_count;endcase
   if(take_r || take_n)begin
    accepted<=accepted+take_r+take_n;
    rejected<=0;
   end
   if((ev_return && !take_r)||(ev_normal && !take_n))rejected<=1;
   // Priority is semantic: an arrival always beats recall/final timeout.
   if(doctor_event && state==WAIT_ARRIVAL)state<=IN_VISIT;
   else if(doctor_event && state==IN_VISIT)begin
    state<=IDLE;ticket<=0;calls<=0;elapsed<=0;current_return<=0;completed<=completed+1'b1;
   end else if(running && state==WAIT_ARRIVAL && calls==3 && due)begin
    state<=IDLE;ticket<=0;calls<=0;elapsed<=0;current_return<=0;missed<=missed+1'b1;
   end else if(running && grant && request)begin
    if(state==IDLE)begin ticket<=request_ticket;current_return<=request_return;state<=WAIT_ARRIVAL;calls<=1;end
    else calls<=calls+1'b1;
    elapsed<=0;
   end else if(running && state==WAIT_ARRIVAL && !due)elapsed<=elapsed+1'b1;
  end
 end
endmodule

`timescale 1ns/1ps
module tb_patient_names_audio;
 reg clk=0;always #20 clk=~clk;
 reg rst=0;reg [1:0] run=3,req=0,ret=0;reg [15:0] tickets=0;reg [127:0] q=0;
 wire [1:0] grant,started;wire [5:0] clip;wire preq,abort_pcm,tone,announcing,room;
 wire [7:0] ticket;wire [21:0] base,samples;reg busy=0,done=0;
 reg [21:0] query_base=0;always @(posedge clk)query_base<={10'd0,clip,6'd0};
 medq_dual_announcer dut(.clk(clk),.rst_n(rst),.running(run),.voice_ready(1'b1),.request(req),.doctor_event(2'b0),
 .request_ticket(tickets),.request_return(ret),.qstate(q),.grant(grant),.announcement_start(started),.clip_sel(clip),
 .clip_base(query_base),.clip_samples(22'd4),.play_req(preq),.play_base(base),.play_samples(samples),.play_busy(busy),.play_done(done),
 .pcm_abort(abort_pcm),.fallback_tone(tone),.announcing(announcing),.active_room(room),.active_ticket(ticket));
 integer left=0,ix=0,mroom=0,mret=0,n=0,bcd=0,expected=0,nameclip=0,calls=0,clips=0;
 always @(posedge clk)begin
  done<=0;
  if(preq)begin
   if(busy)$fatal(1,"ERROR overwritten player");
   case(ix)
    0:expected=1;1:expected=mret ? (mroom ? 20 : 19) : (mroom ? 17 : 2);
    2:expected=3+n/10;3:expected=3+n%10;4:expected=51;5:expected=nameclip;
    6:expected=52;7:expected=mroom ? 15 : 14;8:expected=18;default:expected=-1;
   endcase
   if(clip!==expected || base!==(expected*64))$fatal(1,"ERROR actual number/name clip room=%0d ret=%0d n=%0d ix=%0d clip=%0d expected=%0d base=%h",mroom,mret,n,ix,clip,expected,base);
   ix=ix+1;clips=clips+1;busy<=1;left<=4;
  end else if(busy)begin
   if(left==1)begin busy<=0;done<=1;end
   else left<=left-1;
  end
 end
 initial begin
  repeat(6)@(negedge clk);rst=1;
  for(mroom=0;mroom<2;mroom=mroom+1)for(mret=0;mret<2;mret=mret+1)for(n=1;n<=99;n=n+1)begin
   bcd=(n/10)*16+n%10;ix=0;
   nameclip=53;
   if(mret && n<=5)nameclip=21+mroom*15+n-1;
   if(!mret && n<=10)nameclip=21+mroom*15+5+n-1;
   @(negedge clk);q=0;tickets=0;ret=0;
   q[mroom*32+:8]=bcd;q[mroom*32+18+:2]=1;q[mroom*32+22]=mret;
   tickets[mroom*8+:8]=bcd;ret[mroom]=mret;req=1<<mroom;
   @(posedge clk);if(grant!==(1<<mroom))$fatal(1,"ERROR admission");
   @(negedge clk);req=0;
   wait(!announcing && !busy);@(negedge clk);
   if(ix!=9)$fatal(1,"ERROR incomplete name sentence");calls=calls+1;
  end
  if(calls!=396 || clips!=3564)$fatal(1,"ERROR coverage");
  $display("PASS 396 A/B/C/D actual 01..99 ticket sentences, 3564 selected clips/bases, all 30 full-name mappings and anonymous out-of-list, synchronous metadata settling");$finish;
 end
 initial begin #20000000;$fatal(1,"TIMEOUT exhaustive patient audio");end
endmodule

`timescale 1ns/1ps
// Independent cover keys; the clinic input frontend remains in reset until
// entry has committed at a frame boundary AND every entry key is released.
module medq_media_control #(parameter DEBOUNCE_CYCLES=250000,HOLD_FRAMES=238)(
 input wire clk,rst_n,frame_start,input wire [3:0] keys_sync,
 input wire [2:0] media_valid,
 output reg clinic_visible,clinic_enable,output reg [21:0] fb_base,
 output wire media_show,output reg [6:0] photo_alpha);
 function integer bits;input integer n;integer v;begin v=n-1;bits=1;while(v>1)begin bits=bits+1;v=v>>1;end end endfunction
 localparam W=bits(DEBOUNCE_CYCLES);
 reg [W-1:0] debounce;
 reg released,entry_pending;
 reg [3:0] candidate;
 reg [2:0] cover_age,settle;
 reg [7:0] hold_count;
 reg [5:0] fade;
 reg [1:0] phase;
 reg doctor;
 // Smoothstep, rounded to Q6; endpoints are exact and never overflow.
 function [6:0] eased;
  input [5:0] t;
  begin case(t)
   0:eased=0;1:eased=0;2:eased=1;3:eased=2;4:eased=3;5:eased=4;6:eased=6;7:eased=8;
   8:eased=10;9:eased=12;10:eased=15;11:eased=17;12:eased=20;13:eased=23;14:eased=26;15:eased=29;
   16:eased=32;17:eased=35;18:eased=38;19:eased=41;20:eased=44;21:eased=47;22:eased=49;23:eased=52;
   24:eased=54;25:eased=56;26:eased=58;27:eased=60;28:eased=61;29:eased=62;30:eased=63;31:eased=64;
   default:eased=64;
  endcase end
 endfunction
 assign media_show=clinic_visible ? ((doctor ? media_valid[2] : media_valid[1]) && settle==0) : cover_age==5;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   clinic_visible<=0;clinic_enable<=0;fb_base<=0;photo_alpha<=0;
   debounce<=0;released<=0;entry_pending<=0;candidate<=15;
   cover_age<=0;settle<=3;hold_count<=0;fade<=0;phase<=0;doctor<=0;
  end else begin
   // A boot-held key cannot enter until a clean all-key release has occurred.
   if(keys_sync!=candidate)begin candidate<=keys_sync;debounce<=0;end
   else if(debounce<DEBOUNCE_CYCLES-1)debounce<=debounce+1'b1;
   else begin
    if(!clinic_visible && !entry_pending)begin
     if(candidate==15)released<=1;
     else if(released)begin entry_pending<=1;released<=0;end
    end
    if(clinic_visible && candidate==15)clinic_enable<=1;
   end
   if(frame_start)begin
    if(media_valid[0])begin if(cover_age<5)cover_age<=cover_age+1'b1;end
    else cover_age<=0;
    if(!clinic_visible)begin
     if(entry_pending)begin
      clinic_visible<=1;fb_base<=22'h04b000;settle<=3;photo_alpha<=0;
      // The release barrier starts at the page swap, not the original press.
      debounce<=0;candidate<=keys_sync;
     end
    end else if(settle!=0)begin settle<=settle-1'b1;photo_alpha<=0;end
    else if(!(doctor ? media_valid[2] : media_valid[1]))begin
     photo_alpha<=0;phase<=0;fade<=0;
     if(doctor ? media_valid[1] : media_valid[2])begin
      doctor<=!doctor;fb_base<=doctor ? 22'h04b000 : 22'h096000;settle<=3;
     end
    end else case(phase)
     0:begin
      photo_alpha<=eased(fade);
      if(fade==32)begin phase<=1;hold_count<=0;end else fade<=fade+1'b1;
     end
     1:begin
      photo_alpha<=64;
      if(hold_count==HOLD_FRAMES-1)begin
       if(doctor ? media_valid[1] : media_valid[2])begin phase<=2;fade<=32;end
       hold_count<=0;
      end else hold_count<=hold_count+1'b1;
     end
     2:begin
      photo_alpha<=eased(fade);
      if(fade==0)begin
       doctor<=!doctor;fb_base<=doctor ? 22'h04b000 : 22'h096000;
       settle<=3;phase<=0;fade<=0;
      end else fade<=fade-1'b1;
     end
     default:begin phase<=0;fade<=0;photo_alpha<=0;end
    endcase
   end
  end
 end
endmodule

`timescale 1ns/1ps
// Contacts have already passed medq_board_inputs' two synchronizer stages.
module medq_v03_inputs #(parameter integer DEBOUNCE_CYCLES=250000,INIT_CYCLES=250000)(
 input wire clk,rst_n,input wire [3:0] keys_sync,switches_sync,
 output wire [1:0] running,output wire ready,output reg [3:0] enqueue,
 output reg [1:0] doctor_event);
 function integer bits;input integer n;integer v;begin v=n-1;bits=0;while(v>0)begin bits=bits+1;v=v>>1;end if(bits<1)bits=1;end endfunction
 localparam W=bits(DEBOUNCE_CYCLES>INIT_CYCLES ? DEBOUNCE_CYCLES : INIT_CYCLES);
 wire [7:0] raw={switches_sync,keys_sync};
 reg [7:0] stable,candidate,initialized;
 reg [7:0] armed;
 reg [W-1:0] count[0:7];
 reg [2:0] warmup;
 reg [2:0] run_age;
 assign ready=&initialized;
 assign running={2{ready}} & ~stable[5:4];
 integer i;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   stable<=8'hff;candidate<=8'hff;initialized<=0;armed<=0;warmup<=0;run_age<=0;enqueue<=0;doctor_event<=0;
   for(i=0;i<8;i=i+1)count[i]<=0;
  end else begin
   enqueue<=0;doctor_event<=0;
   if(!ready)begin armed<=0;run_age<=0;end
   else begin
    if(run_age<4)run_age<=run_age+1'b1;
    // SW1/SW2 gate A/B calling only. Keys and SW3/SW4 doctors stay live.
    for(i=0;i<8;i=i+1)
     if(run_age==4 && initialized[i] && raw[i]==stable[i] && raw[i]==candidate[i])armed[i]<=1;
   end
   if(warmup<4)begin warmup<=warmup+1'b1;candidate<=raw;end
   else for(i=0;i<8;i=i+1)begin
    if(raw[i]!=candidate[i])begin candidate[i]<=raw[i];count[i]<=1;end
    else if(!initialized[i])begin
     if(count[i]>=INIT_CYCLES-1)begin stable[i]<=raw[i];initialized[i]<=1;count[i]<=0;end
     else count[i]<=count[i]+1'b1;
    end else if(raw[i]!=stable[i])begin
     if(count[i]>=DEBOUNCE_CYCLES-1)begin
      stable[i]<=raw[i];count[i]<=0;
      if(ready && armed[i])begin
       if(i<4 && !raw[i])enqueue[i]<=1;
       if(i==6)doctor_event[0]<=1;
       if(i==7)doctor_event[1]<=1;
      end
     end else count[i]<=count[i]+1'b1;
    end else count[i]<=0;
   end
  end
 end
endmodule

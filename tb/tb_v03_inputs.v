`timescale 1ns/1ps
module tb_v03_inputs;
 reg clk=0;always #20 clk=~clk;
 reg rst=0;reg [3:0] key=15,sw=15;wire [3:0] ks,ss,enq;wire [1:0] doc;wire [1:0] run;wire ready;
 medq_board_inputs sync(.clk(clk),.rst_n(rst),.keys(key),.switches(sw),.keys_sync(ks),.switches_sync(ss));
 medq_v03_inputs #(.DEBOUNCE_CYCLES(5),.INIT_CYCLES(7)) dut(.clk(clk),.rst_n(rst),.keys_sync(ks),.switches_sync(ss),.running(run),.ready(ready),.enqueue(enq),.doctor_event(doc));
 integer kc[0:3],dc[0:1],i,before_k,before_a,before_b;
 always @(posedge clk)if(rst)begin for(integer j=0;j<4;j=j+1)if(enq[j])kc[j]=kc[j]+1;for(integer j=0;j<2;j=j+1)if(doc[j])dc[j]=dc[j]+1;end
 task settle;begin repeat(20)@(negedge clk);end endtask
 initial begin
  for(i=0;i<4;i=i+1)kc[i]=0;dc[0]=0;dc[1]=0;
  for(i=0;i<16;i=i+1)begin
   rst=0;sw=i[3:0];key=15;settle;rst=1;wait(ready);settle;
   if(run!==(~sw[1:0]))$fatal(1,"ERROR independent switch startup polarity");
   if(dc[0]!=0 || dc[1]!=0)$fatal(1,"ERROR false startup doctor event initial=%h",sw);
  end
  @(negedge clk);sw[1:0]=0;settle;before_a=dc[0];before_b=dc[1];
  for(i=0;i<4;i=i+1)begin
   @(negedge clk);key[i]=0;#11;key[i]=1;#7;key[i]=0;#9;key[i]=1;settle;
   if(kc[i]!=0)$fatal(1,"ERROR short bounce counted");
   @(negedge clk);key[i]=0;repeat(200)@(negedge clk);
   if(kc[i]!=1)$fatal(1,"ERROR long hold key=%0d count=%0d",i,kc[i]);
   key[i]=1;settle;
  end
  @(negedge clk);sw[2]=~sw[2];settle;sw[2]=~sw[2];settle;
  sw[3]=~sw[3];settle;sw[3]=~sw[3];settle;
  if(dc[0]!=before_a+2 || dc[1]!=before_b+2)$fatal(1,"ERROR both-edge doctor events");
  sw[1:0]=3;settle;before_a=dc[0];before_b=dc[1];
  key=0;sw[3:2]=~sw[3:2];settle;key=15;settle;
  sw[0]=0;settle;
  if(dc[0]!=before_a+1 || dc[1]!=before_b+1)$fatal(1,"ERROR SW1 off dropped doctor events");
  for(i=0;i<4;i=i+1)if(kc[i]!=2)$fatal(1,"ERROR SW1 off dropped or duplicated key");
  before_a=dc[0];before_b=dc[1];
  sw[1]=~sw[1];settle;
  if(dc[0]!=before_a || dc[1]!=before_b || run[1]!==!sw[1])$fatal(1,"ERROR SW2 gate generated doctor event");
  // SW1 transitions never rearm/drop independent input debouncers.
  sw[0]=1;settle;before_a=dc[0];before_k=kc[0];
  sw[0]=0;repeat(3)@(negedge clk);sw[2]=~sw[2];key[0]=0;settle;
  if(dc[0]!=before_a+1 || kc[0]!=before_k+1)$fatal(1,"ERROR SW1 boundary dropped transition");
  key[0]=1;settle;sw[2]=~sw[2];key[0]=0;settle;key[0]=1;settle;
  if(dc[0]!=before_a+2 || kc[0]!=before_k+2)$fatal(1,"ERROR SW1 boundary duplicate/missing event");
  $display("PASS synchronized/debounced four keys: bounce, long hold, 16 initial switch levels, both doctor edges, SW1-off input acceptance and no duplicated resume events, independent SW1/SW2 gates and SW3/SW4 doctors");$finish;
 end
 initial begin #200000;$fatal(1,"TIMEOUT input test");end
endmodule

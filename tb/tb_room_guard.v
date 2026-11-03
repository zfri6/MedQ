`timescale 1ns/1ps
module tb_room_guard;
 reg clk=0;always #10 clk=~clk;
 reg rst=0,next=0,arrive=0,skip=0,recall=0,auto_mode=0;
 wire pulse;wire [15:0] ticket;wire [3:0] room;wire [127:0] qstate;
 integer n;
 queue_fsm #(.AUTO_PERIOD(8)) dut(.clk(clk),.rst_n(rst),.ev_next(next),.ev_recall(recall),.ev_skip(skip),
  .ev_page(1'b0),.ev_arrive(arrive),.sw_priority(1'b0),.sw_auto(auto_mode),.sw_access(1'b0),
  .restore_req(1'b0),.restore_data(128'd0),.persist_data(),.persist_req(),.qstate(qstate),
  .call_pulse(pulse),.call_ticket(ticket),.call_room(room),.call_prio());
 task tick;begin @(posedge clk);#1;@(negedge clk);end endtask
 initial begin
  repeat(4)tick();rst=1;
  for(n=1;n<=5;n=n+1)begin arrive=1;tick();arrive=0;tick();end
  for(n=1;n<=4;n=n+1)begin next=1;tick();if(!pulse || ticket!==16'(n) || room!==4'(n))$fatal(1,"ERROR room allocation");next=0;tick();end
  next=1;tick();if(pulse || dut.norm_wait!=1)$fatal(1,"ERROR full-room manual consumed ticket");next=0;
  auto_mode=1;repeat(32)begin tick();if(pulse || dut.norm_wait!=1)$fatal(1,"ERROR full-room auto consumed ticket");end auto_mode=0;
  recall=1;tick();if(!pulse || ticket!=4 || room!=4)$fatal(1,"ERROR full-room recall");recall=0;tick();
  skip=1;tick();skip=0;tick();next=1;tick();
  if(!pulse || ticket!=5 || room!=4 || dut.norm_wait!=0)$fatal(1,"ERROR release / retained next ticket");
  next=0;tick();
  $display("PASS room guard: full-room manual/auto hold, no room0 dispatch or lost ticket, recall and release reuse");$finish;
 end
 initial begin #100000;$fatal(1,"TIMEOUT room guard");end
endmodule

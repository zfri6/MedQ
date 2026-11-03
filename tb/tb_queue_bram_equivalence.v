`timescale 1ns/1ps
module tb_queue_bram_equivalence;
 reg clk=0;always #10 clk=~clk;
 reg rst=0;reg [7:0] events=0;reg restore=0;
 reg [127:0] restore_data=0;
 wire [127:0] state_a,state_b,persist_a,persist_b;
 wire pr_a,pr_b,call_a,call_b,priority_a,priority_b;
 wire [15:0] ticket_a,ticket_b;wire [3:0] room_a,room_b;
 integer n,checks=0;reg [31:0] rng=32'h59a17e03;
 queue_fsm #(.ROOM_GUARD(0),.AUTO_PERIOD(64)) dut(.clk(clk),.rst_n(rst),.ev_next(events[0]),.ev_recall(events[1]),.ev_skip(events[2]),
  .ev_page(events[3]),.ev_arrive(events[4]),.sw_priority(events[5]),.sw_auto(events[6]),.sw_access(events[7]),
  .restore_req(restore),.restore_data(restore_data),.qstate(state_a),.persist_data(persist_a),.persist_req(pr_a),
  .call_pulse(call_a),.call_ticket(ticket_a),.call_room(room_a),.call_prio(priority_a));
 queue_fsm_reference #(.AUTO_PERIOD(64)) reference(.clk(clk),.rst_n(rst),.ev_next(events[0]),.ev_recall(events[1]),.ev_skip(events[2]),
  .ev_page(events[3]),.ev_arrive(events[4]),.sw_priority(events[5]),.sw_auto(events[6]),.sw_access(events[7]),
  .restore_req(restore),.restore_data(restore_data),.qstate(state_b),.persist_data(persist_b),.persist_req(pr_b),
  .call_pulse(call_b),.call_ticket(ticket_b),.call_room(room_b),.call_prio(priority_b));
 always @(posedge clk)begin
  #1;
  if({state_a,persist_a,pr_a,call_a,ticket_a,room_a,priority_a}!=={state_b,persist_b,pr_b,call_b,ticket_b,room_b,priority_b})
   $fatal(1,"ERROR queue RAM equivalence at cycle=%0d tickets=%h/%h",checks,ticket_a,ticket_b);
  checks=checks+1;
 end
 initial begin
  repeat(5)@(negedge clk);rst=1;
  // Fill both queues, replace while full, wrap, and immediate empty push/pop.
  for(n=0;n<1300;n=n+1)begin
   events=n<600 ? (n%2 ? 8'h30:8'h10) : n<1000 ? 8'h11 : 8'h01;
   @(negedge clk);
  end
  for(n=0;n<20000;n=n+1)begin
   rng=(rng<<1)^(rng[31]?32'h04c11db7:0);events=rng[7:0];
   rst=n%1001!=0;restore=n%127==0;
   restore_data=n%2 ? 128'h4d000000010001000000000000000001 : 128'd0;
   @(negedge clk);
  end
  events=0;restore=0;repeat(5)@(negedge clk);
  $display("PASS queue RAM equivalence: %0d cycles, full/empty, wrap, simultaneous events, restore, reset, auto call",checks);$finish;
 end
endmodule

`timescale 1ns/1ps
// Unit-only terminal deposit. Full top never forces/deposits internal state.
module tb_v03_timer;
 reg clk=0;always #20 clk=~clk;
 reg rst=0,run=1,enq=0,doc=0,allow=1;wire req;wire grant=req&&allow;
 wire [1:0] state,calls;wire [7:0] ticket,rt;wire rp,cr,rejected;
 wire [4:0] nc,rc;wire [7:0] accepted,completed,missed;
 medq_room_service dut(.clk(clk),.rst_n(rst),.running(run),.ev_normal(enq),.ev_return(1'b0),.doctor_event(doc),.grant(grant),
 .request(req),.request_ticket(rt),.request_return(rp),.state(state),.ticket(ticket),.current_return(cr),.calls(calls),
 .normal_count(nc),.return_count(rc),.rejected(rejected),.accepted(accepted),.completed(completed),.missed(missed));
 task terminal;begin @(negedge clk);dut.elapsed=749999998;@(negedge clk);if(dut.elapsed!=749999999)$fatal(1,"ERROR terminal increment");end endtask
 initial begin
  if(dut.INTERVAL_CYCLES!==64'd750000000 || $bits(dut.elapsed)!=30)$fatal(1,"ERROR production clock product/width");
  repeat(5)@(negedge clk);rst=1;enq=1;@(negedge clk);enq=0;wait(state==1);@(negedge clk);
  if(calls!=1 || ticket!=1)$fatal(1,"ERROR first grant");
  terminal;@(negedge clk);if(calls!=2 || dut.elapsed!=0)$fatal(1,"ERROR second grant terminal");
  terminal;@(negedge clk);if(calls!=3)$fatal(1,"ERROR third grant");
  terminal;doc=1;@(negedge clk);doc=0;
  if(state!=2 || missed!=0 || calls!=3)$fatal(1,"ERROR arrival beats final timeout");
  repeat(30)@(negedge clk);if(req)$fatal(1,"ERROR recall after arrival");
  doc=1;@(negedge clk);doc=0;if(state!=0 || completed!=1)$fatal(1,"ERROR departure");
  enq=1;@(negedge clk);enq=0;wait(state==1);terminal;
  doc=1;@(negedge clk);doc=0;if(state!=2 || calls!=1)$fatal(1,"ERROR arrival beats recall");
  doc=1;@(negedge clk);doc=0;enq=1;@(negedge clk);enq=0;wait(state==1);
  terminal;@(negedge clk);terminal;@(negedge clk);terminal;
  run=0;repeat(20)@(negedge clk);if(state!=1 || missed!=0 || dut.elapsed!=749999999)$fatal(1,"ERROR pause terminal");
  run=1;@(negedge clk);if(state!=0 || missed!=1)$fatal(1,"ERROR final wait timeout");
  $display("PASS production 25MHz*30=750000000, 30-bit timer, exact terminal boundaries, 3 starts/final wait, arrival precedence, pause; terminal acceleration is unit-only deposit");$finish;
 end
 initial begin #100000;$fatal(1,"TIMEOUT production timer");end
endmodule

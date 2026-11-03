`timescale 1ns/1ps
module tb_call_feedback;
 reg clk=0;always #20 clk=~clk;
 reg rst=0,call=0,ready=0;wire tone;integer n;
 medq_call_feedback #(.DURATION_CYCLES(7)) dut(.clk(clk),.rst_n(rst),.call_pulse(call),.voice_ready(ready),.tone_enable(tone));
 task tick;begin @(posedge clk);#1;@(negedge clk);end endtask
 task check(input v);begin if(tone!==v)$fatal(1,"ERROR fallback tone expected=%b actual=%b",v,tone);end endtask
 initial begin
  tick();rst=1;repeat(10)begin tick();check(0);end
  call=1;tick();check(1);call=0;
  for(n=1;n<7;n=n+1)begin tick();check(1);end
  tick();check(0);
  call=1;tick();call=0;repeat(3)tick();call=1;tick();call=0;
  repeat(6)begin tick();check(1);end tick();check(0);
  call=1;ready=1;tick();check(0);ready=0;tick();check(1);call=0;
  ready=1;tick();check(0);ready=0;repeat(5)begin tick();check(0);end
  rst=0;tick();check(0);
  $display("PASS fallback feedback: silence when idle, exactly7 cycles, retrigger, ready cancellation, reset");$finish;
 end
 initial begin #100000;$fatal(1,"TIMEOUT feedback");end
endmodule

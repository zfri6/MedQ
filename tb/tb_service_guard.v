`timescale 1ns/1ps
module tb_service_guard;
 reg clk=0;always #10 clk=~clk;
 reg rst=0,ok=0,err=0,mr=1,mf=0,under=0;reg [3:0] progress=0;
 wire [7:0] status;integer i;
 medq_service_guard #(.STARTUP_CYCLES(8)) dut(.clk(clk),.rst_n(rst),.assets_ok(ok),.load_error(err),
  .memory_ready(mr),.memory_fault(mf),.underrun(under),.progress(progress),.service_status(status));
 task tick;begin @(posedge clk);#1;@(negedge clk);end endtask
 task mode(input [1:0] expected);begin #1;if(status[1:0]!==expected)$fatal(1,"ERROR guard expected=%0d actual=%h",expected,status);end endtask
 initial begin
  tick();rst=1;under=1;
  for(i=0;i<7;i=i+1)begin tick();mode(0);end
  if(status[3])$fatal(1,"ERROR startup underrun latched");
  tick();mode(2);mr=0;mode(3);mr=1;ok=1;progress=15;mode(1);
  tick();if(!status[3] || status[7:4]!=15)$fatal(1,"ERROR sticky warning or progress");
  under=0;tick();if(!status[3])$fatal(1,"ERROR warning not sticky");
  err=1;mode(2);mf=1;mode(3);mf=0;err=0;mode(1);
  rst=0;tick();if(status!==0)$fatal(1,"ERROR guard reset");
  rst=1;ok=0;mr=1;err=1;mode(2);
  $display("PASS service guard: exact deadline, basic mode, memory fault precedence, recovery, progress, qualified sticky warning, reset");$finish;
 end
 initial begin #100000;$fatal(1,"TIMEOUT guard");end
endmodule

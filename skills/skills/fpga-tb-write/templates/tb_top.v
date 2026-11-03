`timescale 1ns/1ps

// Template: tb_top.v
// Copy to tb/tb_top.v and adapt signal names, widths, parameters and stimulus
// to the actual RTL under test. Works with both ModelSim (vlog/vsim) and iverilog.
//
// CLOCK: HX4S20 on-board oscillator is believed to be 25 MHz (DEMO cnt1s counts
// to 24_999_999 for 1 s; DEMO sdc uses period 40 ns). Confirm from the board
// manual before relying on it for real-time behaviour; for pure logic tests the
// exact value does not matter.
//
// WAIT STYLE:      repeat (N) @(posedge clk);   (never raw #delays for protocol timing)
// PORT DIRECTION:  RTL input -> TB reg (driven), RTL output -> TB wire (observed)
// VCD:             run_sim.py --vcd defines DUMP_VARS; cwd is sim/, so "wave.vcd" lands in sim/

module tb_top;
    parameter CLK_FREQ_HZ   = 25_000_000;
    parameter CLK_PERIOD_NS = 1_000_000_000 / CLK_FREQ_HZ;   // 40
    parameter TIMEOUT_CYCLES = 100_000;

    // DUT parameters (copy from RTL; only `parameter`s can be overridden, not `localparam`s)
    localparam T1S = 27'd24999999;

    reg        clk;
    reg        rst_n;
    wire [3:0] LED;

    integer cycle_count;
    integer error_count;

    initial clk = 1'b0;
    always #(CLK_PERIOD_NS / 2) clk = ~clk;

    initial begin
        `ifdef DUMP_VARS
            $dumpfile("wave.vcd");
            $dumpvars(0, tb_top);
        `endif
    end

    initial begin
        error_count = 0;
        rst_n = 1'b0;
        repeat (5) @(posedge clk);
        #1 rst_n = 1'b1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) cycle_count <= 0;
        else        cycle_count <= cycle_count + 1;
    end

    // DUT: either inline instantiation or `include "dut_inst.vh"
    cnt1s dut (
        .CLOCK(clk),
        .rst_n(rst_n),
        .LED  (LED)
    );

    task check4(input [8*32-1:0] name, input [3:0] exp, input [3:0] got);
        begin
            if (got !== exp) begin
                $display("ERROR [%0s] t=%0t exp=%b got=%b", name, $time, exp, got);
                error_count = error_count + 1;
            end
        end
    endtask

    initial begin
        wait (rst_n === 1'b1);
        @(posedge clk); #1;
        check4("reset_value", 4'hF, LED);

        // Behavioural check instead of waiting 25M cycles: force the counter near
        // its terminal value via hierarchical reference, then observe the toggle.
        @(negedge clk);
        dut.cnt_value = T1S - 2;
        repeat (3) @(posedge clk); #1;
        check4("toggle_after_T1S", 4'h0, LED);
        repeat (2) @(posedge clk); #1;
        check4("stays_until_next_T1S", 4'h0, LED);

        if (error_count == 0) $display("PASS");
        else                  $display("FAIL errors=%0d", error_count);
        $finish;
    end

    always @(posedge clk) begin
        if (rst_n && cycle_count > TIMEOUT_CYCLES) begin
            $display("TIMEOUT at cycle %0d", cycle_count);
            $finish;
        end
    end
endmodule

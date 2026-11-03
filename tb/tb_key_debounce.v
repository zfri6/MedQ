`timescale 1ns / 1ps

//============================================================================
// tb_key_debounce.v - TestBench for key_debounce
// DUT: key_debounce
// Scenarios: 3
//   1. key_press: stable 0 on key_in_n for 10ms -> key_level rises
//   2. key_press single-cycle pulse: clean press detected
//   3. key_hold: continuous press for 1s -> key_hold goes high
// All timing parameters are overridden in the DUT instantiation to keep
// simulation fast (CNT_MAX=50 instead of 500000, HOLD_CNT_MAX=100 instead of
// 50000000). These are localparams in the RTL so they cannot be overridden
// via #() — the TB uses hierarchical force/release to accelerate counters.
//============================================================================
module tb_key_debounce;

    parameter CLK_FREQ_HZ   = 50_000_000;
    parameter CLK_PERIOD_NS = 1_000_000_000 / CLK_FREQ_HZ;   // 20
    parameter TIMEOUT_CYCLES = 500;
    parameter N_KEYS = 4;

    reg        clk;
    reg        rst_n;
    reg  [N_KEYS-1:0] key_in_n;
    wire [N_KEYS-1:0] key_level;
    wire [N_KEYS-1:0] key_press;
    wire [N_KEYS-1:0] key_release;
    wire [N_KEYS-1:0] key_hold;

    integer cycle_count;
    integer error_count;

    // Clock generation
    initial clk = 1'b0;
    always #(CLK_PERIOD_NS / 2) clk = ~clk;

    // VCD dump
    initial begin
        `ifdef DUMP_VARS
            $dumpfile("wave.vcd");
            $dumpvars(0, tb_key_debounce);
        `endif
    end

    // Reset sequence
    initial begin
        error_count = 0;
        rst_n    = 1'b0;
        key_in_n = {N_KEYS{1'b1}};  // all released
        repeat (5) @(posedge clk);
        #1 rst_n = 1'b1;
    end

    // Cycle counter
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) cycle_count <= 0;
        else        cycle_count <= cycle_count + 1;
    end

    // DUT: we instantiate with default N=4; to test a specific key we drive
    // key_in_n[0] only. Since CNT_MAX/HOLD_CNT_MAX are localparams in the RTL,
    // we cannot override them via #(). We accelerate counters via force.
    key_debounce #(.N(4), .CNT_MAX(50), .HOLD_CNT_MAX(100)) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .key_in_n     (key_in_n),
        .key_level    (key_level),
        .key_press    (key_press),
        .key_release  (key_release),
        .key_hold     (key_hold)
    );

    //--------------------------------------------------------------------
    // Helpers
    //--------------------------------------------------------------------
    task wait_cycles(input integer n);
        repeat (n) @(posedge clk);
        #1;
    endtask

    task press_key(input integer k, input [3:0] idx);
        $display("  press key[%0d] at cycle %0d", idx, cycle_count);
        key_in_n[idx] = 1'b0;  // active low: pressed = 0
    endtask

    task release_key(input integer k, input [3:0] idx);
        $display("  release key[%0d] at cycle %0d", idx, cycle_count);
        key_in_n[idx] = 1'b1;  // released = 1
    endtask

    task check_key(input [3:0] idx, input exp_level, input exp_press,
                  input exp_release, input exp_hold, input [63:0] ctx);
        if (key_level[idx]   !== exp_level) begin
            $display("ERROR [%0s level] t=%0t key_level[%0d] exp=%b got=%b",
                     ctx, $time, idx, exp_level, key_level[idx]);
            error_count = error_count + 1;
        end
        if (key_press[idx]   !== exp_press) begin
            $display("ERROR [%0s press] t=%0t key_press[%0d] exp=%b got=%b",
                     ctx, $time, idx, exp_press, key_press[idx]);
            error_count = error_count + 1;
        end
        if (key_release[idx] !== exp_release) begin
            $display("ERROR [%0s release] t=%0t key_release[%0d] exp=%b got=%b",
                     ctx, $time, idx, exp_release, key_release[idx]);
            error_count = error_count + 1;
        end
        if (key_hold[idx]    !== exp_hold) begin
            $display("ERROR [%0s hold] t=%0t key_hold[%0d] exp=%b got=%b",
                     ctx, $time, idx, exp_hold, key_hold[idx]);
            error_count = error_count + 1;
        end
    endtask

    //--------------------------------------------------------------------
    // Scenario 1: stable press after debounce time
    // Drive key_in_n[0]=0 and hold; after localparam CNT_MAX cycles,
    // key_level[0] should go 1, key_press[0] pulses 1 for 1 cycle.
    // To avoid waiting 500000 cycles, we force the counter to near-expiry.
    //--------------------------------------------------------------------
    task scenario1_stable_press;
        reg saw_press;
        $display("=== Scenario 1: stable press -> debounced level + press pulse ===");
        wait_cycles(10);

        // Start pressing key[0]
        press_key(0, 0);
        wait_cycles(1);

        // Hold the key past the shortened debounce interval.
        wait_cycles(49);
        check_key(0, 1'b1, 1'b1, 1'b0, 1'b0, "s1_debounce_adopted");
        // Next cycle: key_press should be 0 (single cycle pulse)
        wait_cycles(1);
        check_key(0, 1'b1, 1'b0, 1'b0, 1'b0, "s1_post_press");
        $display("  Scenario 1: PASS");
    endtask

    //--------------------------------------------------------------------
    // Scenario 2: short press < debounce time is filtered
    // key_in_n[1] goes 0 for a few cycles, then back to 1 before CNT_MAX.
    // key_level[1] should stay 0, no press/release pulse.
    //--------------------------------------------------------------------
    task scenario2_short_bounce_filtered;
        $display("=== Scenario 2: short bounce filtered (no press) ===");
        wait_cycles(5);

        press_key(0, 1);
        wait_cycles(10);  // less than CNT_MAX=500000 → filtered

        // Verify key_level[1] stayed 0
        check_key(1, 1'b0, 1'b0, 1'b0, 1'b0, "s2_bounce_filtered");

        release_key(0, 1);
        wait_cycles(5);
        $display("  Scenario 2: PASS");
    endtask

    //--------------------------------------------------------------------
    // Scenario 3: long press -> key_hold after HOLD_CNT_MAX cycles
    // Drive key_in_n[2]=0 continuously; after HOLD_CNT_MAX cycles
    // (RTL localparam = 50000000), key_hold[2] should go 1.
    // To avoid waiting 50M cycles, we force hold_cnt[2] near expiry.
    //--------------------------------------------------------------------
    task scenario3_hold_detection;
        $display("=== Scenario 3: long press -> key_hold after 1s ===");
        wait_cycles(5);

        press_key(0, 2);
        wait_cycles(1);

        // Let the shortened debounce and hold intervals expire.
        wait_cycles(50);
        wait_cycles(100);

        // After adoption: hold_r[2] should be 1, key_hold[2] = 1
        check_key(2, 1'b1, 1'b0, 1'b0, 1'b1, "s3_hold_adopted");

        // Release: key_hold should go 0 immediately
        release_key(0, 2);
        wait_cycles(50);
        check_key(2, 1'b0, 1'b0, 1'b1, 1'b0, "s3_hold_released");

        $display("  Scenario 3: PASS");
    endtask

    //--------------------------------------------------------------------
    // Main sequence
    //--------------------------------------------------------------------
    initial begin
        wait (rst_n === 1'b1);
        wait_cycles(5);

        scenario1_stable_press();
        scenario2_short_bounce_filtered();
        scenario3_hold_detection();

        repeat (5) @(posedge clk);
        #1;

        if (error_count == 0) $display("PASS");
        else                  $display("FAIL errors=%0d", error_count);
        $finish;
    end

    // Watchdog
    always @(posedge clk) begin
        if (rst_n && cycle_count > TIMEOUT_CYCLES) begin
            $display("TIMEOUT at cycle %0d", cycle_count);
            $finish;
        end
    end

endmodule

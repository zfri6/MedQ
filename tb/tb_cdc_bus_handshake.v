`timescale 1ns / 1ps

//============================================================================
// tb_cdc_bus_handshake.v - TestBench for cdc_bus_handshake
// DUT: cdc_bus_handshake #(.W(128))
// Scenarios: 3
//   1. Single write: src writes data, dst receives same data (basic handshake)
//   2. Two consecutive writes: dst receives both values in order, no tearing
//   3. Same-frequency clock: src_clk=dst_clk=50MHz, state machine closes
//
// NOTE: cdc_bus_handshake instantiates cdc_sync_bit sub-module.
//       The TB uses the same 50 MHz clock for both domains (scenario 3).
//============================================================================
module tb_cdc_bus_handshake;

    parameter W = 128;

    parameter SRC_CLK_HZ   = 50_000_000;
    parameter SRC_PERIOD_NS = 1_000_000_000 / SRC_CLK_HZ;   // 20
    parameter DST_CLK_HZ   = 50_000_000;
    parameter DST_PERIOD_NS = 1_000_000_000 / DST_CLK_HZ;   // 20
    parameter TIMEOUT_CYCLES = 500;

    reg        src_clk;
    reg        src_rst_n;
    reg  [W-1:0] src_data;
    // The frozen interface is level-based: changing src_data starts a transfer.
    // No internal request/acknowledge signals are required by the TB.

    reg        dst_clk;
    reg        dst_rst_n;
    wire [W-1:0] dst_data;

    integer cycle_count;
    integer error_count;

    // Dual clock generation
    initial src_clk = 1'b0;
    always #(SRC_PERIOD_NS / 2) src_clk = ~src_clk;

    initial dst_clk = 1'b0;
    always #(DST_PERIOD_NS / 2) dst_clk = ~dst_clk;

    // VCD dump
    initial begin
        `ifdef DUMP_VARS
            $dumpfile("wave.vcd");
            $dumpvars(0, tb_cdc_bus_handshake);
        `endif
    end

    // Reset sequence
    initial begin
        error_count = 0;
        src_rst_n  = 1'b0;
        dst_rst_n  = 1'b0;
        src_data   = {W{1'b0}};
        repeat (5) @(posedge src_clk);
        #1 src_rst_n = 1'b1;
        repeat (5) @(posedge dst_clk);
        #1 dst_rst_n = 1'b1;
    end

    // Cycle counter on src_clk
    always @(posedge src_clk or negedge src_rst_n) begin
        if (!src_rst_n) cycle_count <= 0;
        else            cycle_count <= cycle_count + 1;
    end

    // DUT instantiation
    cdc_bus_handshake #(.W(W)) dut (
        .src_clk    (src_clk),
        .src_rst_n  (src_rst_n),
        .src_data   (src_data),
        .dst_clk    (dst_clk),
        .dst_rst_n  (dst_rst_n),
        .dst_data   (dst_data)
    );

    //--------------------------------------------------------------------
    // NOTE on handshake protocol:
    // The DUT reports only the captured destination data; completion is
    // observed by matching that public output.

    //--------------------------------------------------------------------
    // Helpers
    //--------------------------------------------------------------------
    task wait_src_cycles(input integer n);
        repeat (n) @(posedge src_clk);
    endtask

    task wait_dst_cycles(input integer n);
        repeat (n) @(posedge dst_clk);
    endtask

    task send_data(input [W-1:0] data_val);
        $display("  send_data: 0x%h at src cycle %0d", data_val, cycle_count);
        src_data <= data_val;
        while (dst_data !== data_val && cycle_count <= TIMEOUT_CYCLES) begin
            wait_src_cycles(1);
            wait_dst_cycles(1);
        end
        if (dst_data !== data_val) begin
            $display("ERROR: transfer timeout waiting for data 0x%h", data_val);
            error_count = error_count + 1;
        end else begin
            $display("  data received at src cycle %0d", cycle_count);
        end
        wait_src_cycles(3);
    endtask

    task check_data(input [W-1:0] exp, input [63:0] ctx);
        if (dst_data !== exp) begin
            $display("ERROR [%0s] t=%0t exp=0x%h got=0x%h", ctx, $time, exp, dst_data);
            error_count = error_count + 1;
        end
    endtask

    //--------------------------------------------------------------------
    // Scenario 1: single write - src writes data, dst receives same data
    //--------------------------------------------------------------------
    task scenario1_single_transfer;
        reg [W-1:0] test_data;
        $display("=== Scenario 1: single transfer ===");
        wait_src_cycles(10);

        // Prepare test data
        test_data = 128'hDEAD_BEEF_1234_5678_9ABC_DEF0_1234_5678;
        send_data(test_data);

        // Check dst_data
        wait_dst_cycles(3);
        check_data(test_data, "s1_dst_data");
        $display("  Scenario 1: PASS");
    endtask

    //--------------------------------------------------------------------
    // Scenario 2: two consecutive writes - verify both received in order
    //--------------------------------------------------------------------
    task scenario2_consecutive_transfers;
        reg [W-1:0] data1, data2;
        $display("=== Scenario 2: consecutive transfers ===");
        wait_src_cycles(5);

        data1 = 128'hAAAA_BBBB_CCCC_DDDD_1111_2222_3333_4444;
        data2 = 128'h5555_6666_7777_8888_9999_AAAA_BBBB_CCCC;

        send_data(data1);
        wait_src_cycles(5);
        check_data(data1, "s2_first_data");

        send_data(data2);
        wait_src_cycles(5);
        check_data(data2, "s2_second_data");

        $display("  Scenario 2: PASS");
    endtask

    //--------------------------------------------------------------------
    // Scenario 3: same-frequency clock (src_clk = dst_clk = 50 MHz)
    // Verify state machine completes (no deadlock) and handshake closes.
    //--------------------------------------------------------------------
    task scenario3_same_freq_no_deadlock;
        reg [W-1:0] test_data;
        $display("=== Scenario 3: same-frequency clock (50MHz/50MHz) ===");
        wait_src_cycles(5);

        test_data = 128'h1234_5678_9ABC_DEF0_FEDC_BA98_7654_3210;
        send_data(test_data);
        wait_dst_cycles(3);
        check_data(test_data, "s3_same_freq");

        // Additional check: send another value to confirm cycle closes
        test_data = 128'h5555_5555_5555_5555_5555_5555_5555_5555;
        send_data(test_data);
        wait_dst_cycles(3);
        check_data(test_data, "s3_second_xfer");

        $display("  Scenario 3: PASS");
    endtask

    //--------------------------------------------------------------------
    // Main sequence
    //--------------------------------------------------------------------
    initial begin
        wait (src_rst_n === 1'b1 && dst_rst_n === 1'b1);
        wait_src_cycles(5);

        scenario1_single_transfer();
        scenario2_consecutive_transfers();
        scenario3_same_freq_no_deadlock();

        repeat (5) @(posedge src_clk);
        #1;

        if (error_count == 0) $display("PASS");
        else                  $display("FAIL errors=%0d", error_count);
        $finish;
    end

    // Watchdog
    always @(posedge src_clk) begin
        if (src_rst_n && dst_rst_n && cycle_count > TIMEOUT_CYCLES) begin
            $display("TIMEOUT at src cycle %0d", cycle_count);
            $finish;
        end
    end

endmodule

// dut_inst.vh -- DUT instantiation include (optional; inline instantiation in tb_top.v is also fine)
// Copy to tb/dut_inst.vh and adapt:
//   1. module name = exact RTL module name (case-sensitive)
//   2. parameter block only for `parameter`s that exist in the RTL (never for localparam)
//   3. every port mapped by name, copied verbatim from the RTL declaration
// Do NOT use defparam; TD and ModelSim both accept #(...) overrides.

cnt1s dut (
    .CLOCK(clk),
    .rst_n(rst_n),
    .LED  (LED)
);

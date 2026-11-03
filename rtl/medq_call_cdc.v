`timescale 1ns / 1ps
// Stable payload plus acknowledged event. QSTATE has one source-clock packing
// delay, so capture its settled snapshot one cycle after call_pulse.
module medq_call_cdc (
    input wire src_clk,src_rst_n,dst_clk,dst_rst_n,call_pulse,
    input wire [127:0] qstate,
    output reg valid,
    output reg [15:0] ticket,
    output reg [3:0] room,
    output reg priority_call,recall
);
    reg pending,fire;
    reg [21:0] held;
    wire busy,event_out;
    always @(posedge src_clk or negedge src_rst_n) begin
        if(!src_rst_n) begin pending<=0; fire<=0; held<=0; end
        else begin
            fire<=0;
            if(call_pulse) pending<=1;
            if(pending && !busy && !fire) begin
                held<={qstate[33:32],qstate[27:24],qstate[15:0]}; fire<=1; pending<=0;
            end
        end
    end
    cdc_pulse u_event(.src_clk(src_clk),.src_rst_n(src_rst_n),.src_pulse(fire),.src_busy(busy),
        .dst_clk(dst_clk),.dst_rst_n(dst_rst_n),.dst_pulse(event_out));
    always @(posedge dst_clk or negedge dst_rst_n) begin
        if(!dst_rst_n) begin valid<=0; ticket<=0; room<=0; priority_call<=0; recall<=0; end
        else begin
            valid<=event_out;
            if(event_out) begin ticket<=held[15:0]; room<=held[19:16]; priority_call<=held[20]; recall<=held[21]; end
        end
    end
endmodule

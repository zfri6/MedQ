`timescale 1ns/1ps
module medq_dual_service #(parameter integer AW=4,MAX_TICKET=99,
 parameter [63:0] INTERVAL_CYCLES=64'd25000000*64'd30)(
 input wire clk,rst_n,inputs_ready,input wire [1:0] running,input wire [3:0] enqueue,
 input wire [1:0] doctor_event,grant,output wire [1:0] request,
 output wire [15:0] request_ticket,output wire [1:0] request_return,
 output wire [127:0] qstate);
 wire [1:0] sa,sb,ca,cb;
 wire [7:0] ta,tb;
 wire ra,rb,ea,eb;
 wire [AW:0] na,nb,qa,qb;
 wire [7:0] accepted_a,accepted_b,completed_a,completed_b,missed_a,missed_b;
 wire [15:0] subtitle_a,subtitle_b;
 medq_room_service #(.AW(AW),.MAX_TICKET(MAX_TICKET),.INTERVAL_CYCLES(INTERVAL_CYCLES)) a(
 .clk(clk),.rst_n(rst_n),.running(running[0]),.ev_normal(enqueue[0]),.ev_return(enqueue[2]),
 .doctor_event(doctor_event[0]),.grant(grant[0]),.request(request[0]),.request_ticket(request_ticket[7:0]),
 .request_return(request_return[0]),.state(sa),.ticket(ta),.current_return(ra),.calls(ca),
 .normal_count(na),.return_count(qa),.rejected(ea),.accepted(accepted_a),.completed(completed_a),.missed(missed_a),.subtitle(subtitle_a));
 medq_room_service #(.AW(AW),.MAX_TICKET(MAX_TICKET),.INTERVAL_CYCLES(INTERVAL_CYCLES)) b(
 .clk(clk),.rst_n(rst_n),.running(running[1]),.ev_normal(enqueue[1]),.ev_return(enqueue[3]),
 .doctor_event(doctor_event[1]),.grant(grant[1]),.request(request[1]),.request_ticket(request_ticket[15:8]),
 .request_return(request_return[1]),.state(sb),.ticket(tb),.current_return(rb),.calls(cb),
 .normal_count(nb),.return_count(qb),.rejected(eb),.accepted(accepted_b),.completed(completed_b),.missed(missed_b),.subtitle(subtitle_b));
 assign qstate={28'd0,subtitle_b,subtitle_a,running,inputs_ready,(|running),8'd0,eb,rb,cb,sb,{{(5-AW-1){1'b0}},qb},{{(5-AW-1){1'b0}},nb},tb,
 8'd0,ea,ra,ca,sa,{{(5-AW-1){1'b0}},qa},{{(5-AW-1){1'b0}},na},ta};
endmodule

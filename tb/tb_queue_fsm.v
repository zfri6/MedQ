`timescale 1ns / 1ps
module tb_queue_fsm;
    reg clk=0; always #10 clk=~clk;
    reg rst_n=0,next=0,recall=0,skip=0,page=0,arrive=0,priority_sw=0,auto_sw=0,access_sw=0,restore=0;
    reg [127:0] restore_data=0,saved;
    wire [127:0] qstate,persist;
    wire call_pulse,persist_req,call_prio;
    wire [15:0] ticket;
    wire [3:0] room;
    integer calls=0,n;
    queue_fsm #(.ROOM_GUARD(0),.AUTO_PERIOD(16)) dut(.clk(clk),.rst_n(rst_n),.ev_next(next),.ev_recall(recall),.ev_skip(skip),
        .ev_page(page),.ev_arrive(arrive),.sw_priority(priority_sw),.sw_auto(auto_sw),.sw_access(access_sw),
        .restore_req(restore),.restore_data(restore_data),.persist_data(persist),.persist_req(persist_req),
        .qstate(qstate),.call_pulse(call_pulse),.call_ticket(ticket),.call_room(room),.call_prio(call_prio));
    always @(posedge clk) if(call_pulse) calls=calls+1;
    task event_tick(input integer kind);
        begin
            @(negedge clk); next=kind==0;recall=kind==1;skip=kind==2;page=kind==3;arrive=kind==4;
            @(posedge clk);#1;
        end
    endtask
    task clear;
        begin @(negedge clk); next=0;recall=0;skip=0;page=0;arrive=0; repeat(3) @(negedge clk); end
    endtask
    task add(input bit prio);
        begin priority_sw=prio;event_tick(4);if(!persist_req)$fatal(1,"ERROR persist arrival");clear;end
    endtask
    task call_check(input [15:0] expected,input bit prio,input [3:0] expected_room);
        begin
            event_tick(0);
            if({call_pulse,call_prio,ticket,room}!=={1'b1,prio,expected,expected_room})
                $fatal(1,"ERROR call exp=%h/%b/%0d got=%h/%b/%0d pulse=%b",expected,prio,expected_room,ticket,call_prio,room,call_pulse);
            clear;
            if(qstate[15:0]!==expected || qstate[27:24]!==expected_room) $fatal(1,"ERROR QSTATE layout");
        end
    endtask
    initial begin
        repeat(4) @(negedge clk);rst_n=1;clear;
        event_tick(0);if(call_pulse)$fatal(1,"ERROR empty call");clear;
        add(0);add(0);add(1);add(1);add(1);
        if(qstate[43:36]!==8'd5)$fatal(1,"ERROR waiting count");
        call_check(16'h0001,1,1);call_check(16'h0002,1,2);call_check(16'h0001,0,3);
        event_tick(1);if(!call_pulse || ticket!==16'h0001 || room!==3)$fatal(1,"ERROR recall payload");clear;
        if(qstate[31:28]!==2 || qstate[33]!==1 || qstate[43:36]!==2)$fatal(1,"ERROR recall mutates queue");
        event_tick(2);clear;if(qstate[15:0]!==0 || qstate[43:36]!==2)$fatal(1,"ERROR skip dequeued twice");
        call_check(16'h0003,1,3);call_check(16'h0002,0,4);
        event_tick(3);clear;access_sw=1;clear;if(qstate[47:44]!==1 || qstate[35]!==1)$fatal(1,"ERROR page/accessibility");
        // BCD rollover and exact persistence fields without uninitialized queue replay.
        saved=persist; saved[87:72]=16'h0099;saved[103:88]=16'h9999;
        @(negedge clk);restore_data=saved;restore=1;@(negedge clk);restore=0;clear;
        add(0);add(0);add(1);add(1);
        call_check(16'h9999,1,1);call_check(16'h0000,1,2);
        call_check(16'h0099,0,3);call_check(16'h0100,0,4);
        for(n=0;n<128;n=n+1)add(0);
        event_tick(4);if(persist_req)$fatal(1,"ERROR full arrival accepted");clear;
        if(dut.norm_wait!==8'd128)$fatal(1,"ERROR full queue overflow");
        auto_sw=1; repeat(40) @(negedge clk);auto_sw=0;
        if(dut.norm_wait>=128)$fatal(1,"ERROR automatic scheduling");
        $display("PASS queue: fairness, recall, skip, page, BCD, capacity, restore, auto");$finish;
    end
    initial begin #1000000;$fatal(1,"TIMEOUT queue");end
endmodule

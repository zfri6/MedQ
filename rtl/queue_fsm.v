`timescale 1ns / 1ps
// MedQ queue controller. Events are synchronous, one-cycle strobes.
module queue_fsm #(
    parameter integer ROOMS = 4,
    parameter integer ROOM_GUARD = 1,
    parameter integer PRIO_BURST = 2,
    parameter integer AUTO_PERIOD = 250000000
) (
    input wire clk, rst_n,
    input wire ev_next, ev_recall, ev_skip, ev_page, ev_arrive,
    input wire sw_priority, sw_auto, sw_access,
    input wire restore_req,
    input wire [127:0] restore_data,
    output wire [127:0] persist_data,
    output reg persist_req,
    output reg [127:0] qstate,
    output reg call_pulse,
    output reg [15:0] call_ticket,
    output reg [3:0] call_room,
    output reg call_prio
);
    reg [15:0] norm_queue [0:127];
    reg [15:0] prio_queue [0:127];
    reg [6:0] norm_head, norm_tail, prio_head, prio_tail;
    reg [7:0] norm_wait, prio_wait;
    reg [15:0] next_norm, next_prio, cur_ticket;
    reg [7:0] cur_prefix;
    reg [3:0] cur_room, repeat_cnt, page_id;
    reg is_priority, is_recall;
    reg [15:0] room_ticket [0:3];
    reg [3:0] occupied;
    reg [31:0] prio_streak, auto_timer;
    integer i, integer_idx;
    reg [3:0] alloc_room, room_busy;
    always @* begin
        alloc_room = 0;
        room_busy = 0;
        for (integer_idx = 3; integer_idx >= 0; integer_idx = integer_idx - 1) begin
            room_busy[integer_idx] = occupied[integer_idx];
            if (integer_idx < ROOMS && !occupied[integer_idx])
                alloc_room = integer_idx + 1;
        end
    end
    function [15:0] bcd_inc;
        input [15:0] value;
        begin
            bcd_inc = value;
            if (value[3:0] < 9) bcd_inc[3:0] = value[3:0] + 1'b1;
            else begin
                bcd_inc[3:0] = 0;
                if (value[7:4] < 9) bcd_inc[7:4] = value[7:4] + 1'b1;
                else begin
                    bcd_inc[7:4] = 0;
                    if (value[11:8] < 9) bcd_inc[11:8] = value[11:8] + 1'b1;
                    else begin
                        bcd_inc[11:8] = 0;
                        bcd_inc[15:12] = value[15:12] < 9 ? value[15:12] + 1'b1 : 4'd0;
                    end
                end
            end
        end
    endfunction
    wire tick = sw_auto && (auto_timer == AUTO_PERIOD - 1);
    wire serve_prio = prio_wait != 0 && (norm_wait == 0 || prio_streak < PRIO_BURST);
    wire do_call = (ev_next || tick) && !ev_skip && (norm_wait != 0 || prio_wait != 0) && (!ROOM_GUARD || alloc_room!=0);
    wire pop_norm = do_call && !serve_prio;
    wire pop_prio = do_call && serve_prio;
    wire push_norm = ev_arrive && !sw_priority && (norm_wait < 128 || pop_norm);
    wire push_prio = ev_arrive && sw_priority && (prio_wait < 128 || pop_prio);
    wire [8:0] waiting_sum = {1'b0,norm_wait} + {1'b0,prio_wait};
    wire [7:0] waiting = waiting_sum > 255 ? 8'd255 : waiting_sum[7:0];

    wire [6:0] norm_read_addr=norm_head+(pop_norm ? 7'd1 : 7'd0);
    wire [6:0] prio_read_addr=prio_head+(pop_prio ? 7'd1 : 7'd0);
    reg [15:0] norm_q,prio_q,norm_new,prio_new;
    reg norm_forward,prio_forward;
    wire [15:0] norm_front=norm_forward ? norm_new : norm_q;
    wire [15:0] prio_front=prio_forward ? prio_new : prio_q;
    always @(posedge clk)begin
        if(rst_n && !restore_req && push_norm)norm_queue[norm_tail]<=next_norm;
        if(rst_n && !restore_req && push_prio)prio_queue[prio_tail]<=next_prio;
        norm_q<=norm_queue[norm_read_addr];prio_q<=prio_queue[prio_read_addr];
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin norm_forward<=0;prio_forward<=0;norm_new<=0;prio_new<=0;end
        else begin
            norm_forward<=!restore_req && push_norm && norm_tail==norm_read_addr;
            prio_forward<=!restore_req && push_prio && prio_tail==prio_read_addr;
            norm_new<=next_norm;prio_new<=next_prio;
        end
    end

    // Persistence v1: counters/current call only. Pending RAM contents are not
    // persistent; restore empties both queues so uninitialized tickets cannot run.
    assign persist_data = {8'h4d, 16'd0, next_prio, next_norm, 24'd0,
                           page_id, 8'd0, sw_access, sw_auto, is_recall, is_priority,
                           repeat_cnt, cur_room, cur_prefix, cur_ticket};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            norm_head <= 0; norm_tail <= 0; prio_head <= 0; prio_tail <= 0;
            norm_wait <= 0; prio_wait <= 0;
            next_norm <= 16'h0001; next_prio <= 16'h0001;
            cur_ticket <= 0; cur_prefix <= 0; cur_room <= 0; repeat_cnt <= 0;
            page_id <= 0; is_priority <= 0; is_recall <= 0; occupied<=0;
            prio_streak <= 0; auto_timer <= 0;
            call_pulse <= 0; call_ticket <= 0; call_room <= 0; call_prio <= 0;
            persist_req <= 0; qstate <= 0;
            for (i=0; i<4; i=i+1) room_ticket[i] <= 0;
        end else begin
            call_pulse <= 0;
            persist_req <= push_norm || push_prio || do_call || ev_skip || ev_recall || ev_page;
            auto_timer <= !sw_auto || tick ? 0 : auto_timer + 1'b1;
            qstate <= {8'd0, next_norm[3:0], room_busy,
                       room_ticket[3], room_ticket[2], room_ticket[1], room_ticket[0],
                       page_id, waiting, sw_access, sw_auto, is_recall, is_priority,
                       repeat_cnt, cur_room, cur_prefix, cur_ticket};
            if (restore_req) begin
                norm_head <= 0; norm_tail <= 0; prio_head <= 0; prio_tail <= 0;
                norm_wait <= 0; prio_wait <= 0;
                if (restore_data[127:120] == 8'h4d) begin
                    next_norm <= restore_data[87:72];
                    next_prio <= restore_data[103:88];
                    cur_ticket <= restore_data[15:0];
                    cur_prefix <= restore_data[23:16];
                    cur_room <= restore_data[27:24];
                    repeat_cnt <= restore_data[31:28];
                    is_priority <= restore_data[32];
                    is_recall <= restore_data[33];
                    page_id <= restore_data[47:44];
                end
                for (i=0; i<4; i=i+1) room_ticket[i] <= 0;
                occupied<=0;
                prio_streak <= 0;
                persist_req <= 0;
            end else begin
                case ({push_norm,pop_norm})
                    2'b10: norm_wait <= norm_wait + 1'b1;
                    2'b01: norm_wait <= norm_wait - 1'b1;
                    default: norm_wait <= norm_wait;
                endcase
                case ({push_prio,pop_prio})
                    2'b10: prio_wait <= prio_wait + 1'b1;
                    2'b01: prio_wait <= prio_wait - 1'b1;
                    default: prio_wait <= prio_wait;
                endcase
                if (push_norm) begin
                    norm_tail <= norm_tail + 1'b1;
                    next_norm <= bcd_inc(next_norm);
                end
                if (push_prio) begin
                    prio_tail <= prio_tail + 1'b1;
                    next_prio <= bcd_inc(next_prio);
                end
                if (ev_page) page_id <= (page_id + 1'b1) & 4'h3;
                if (ev_skip) begin
                    if (cur_room >= 1 && cur_room <= 4) begin room_ticket[cur_room-1] <= 0; occupied[cur_room-1]<=0; end
                    cur_ticket <= 0; cur_prefix <= 0; cur_room <= 0;
                    repeat_cnt <= 0; is_priority <= 0; is_recall <= 0;
                end else if (do_call) begin
                    if (serve_prio) begin
                        call_ticket <= prio_front;
                        cur_ticket <= prio_front;
                        cur_prefix <= 8'h50;
                        prio_head <= prio_head + 1'b1;
                        if (prio_streak < PRIO_BURST) prio_streak <= prio_streak + 1'b1;
                        if (alloc_room != 0) room_ticket[alloc_room-1] <= prio_front;
                    end else begin
                        call_ticket <= norm_front;
                        cur_ticket <= norm_front;
                        cur_prefix <= 8'h41;
                        norm_head <= norm_head + 1'b1;
                        prio_streak <= 0;
                        if (alloc_room != 0) room_ticket[alloc_room-1] <= norm_front;
                    end
                    call_pulse <= 1;
                    call_prio <= serve_prio; is_priority <= serve_prio;
                    call_room <= alloc_room; cur_room <= alloc_room;
                    if(alloc_room!=0) occupied[alloc_room-1]<=1;
                    repeat_cnt <= 1; is_recall <= 0;
                end else if (ev_recall && cur_prefix != 0) begin
                    call_pulse <= 1;
                    call_ticket <= cur_ticket; call_room <= cur_room; call_prio <= is_priority;
                    is_recall <= 1;
                    if (repeat_cnt != 15) repeat_cnt <= repeat_cnt + 1'b1;
                end
            end
        end
    end
endmodule

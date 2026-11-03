`timescale 1ns / 1ps
// Nine clips: alert, prefix, all four BCD digits, invitation, room, closing.
module audio_announcer #(
    parameter integer MAX_STEPS = 12
) (
    input  wire        clk,
    input  wire        rst_n,
    // Call event
    input  wire        call_pulse,
    input  wire [15:0] call_ticket,
    input  wire [3:0]  call_room,
    input  wire        call_prio,
    input  wire        call_recall,
    // Clip info from asset_loader
    output wire [5:0]  clip_sel,
    input  wire [21:0] clip_base,
    input  wire [21:0] clip_samples,
    // Playback control to audio_pcm_player
    output reg         play_req,
    output reg  [21:0] play_base,
    output reg  [21:0] play_samples,
    input  wire        play_busy,
    input  wire        play_done,
    // Status
    output reg         announcing
);


    localparam IDLE=0, SELECT=1, ISSUE=2, WAIT_BUSY=3, WAIT_DONE=4, ADVANCE=5;
    reg [2:0] state;
    reg [3:0] step;
    reg [15:0] ticket;
    reg [3:0] room;
    reg priority_call;
    reg pending,pending_prio;
    reg [15:0] pending_ticket;
    reg [3:0] pending_room;
    reg [5:0] selected;
    always @* begin
        case (step)
            0:selected=1;
            1:selected=priority_call ? 2 : 0;
            2:selected=3+ticket[15:12];
            3:selected=3+ticket[11:8];
            4:selected=3+ticket[7:4];
            5:selected=3+ticket[3:0];
            6:selected=13;
            7:selected=room>=1 && room<=4 ? 14+room-1 : 14;
            8:selected=18;
            default:selected=1;
        endcase
    end
    assign clip_sel=selected;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; step<=0; ticket<=0; room<=0; priority_call<=0;
            pending<=0;pending_ticket<=0;pending_room<=0;pending_prio<=0;
            play_req<=0; play_base<=0; play_samples<=0; announcing<=0;
        end else begin
            play_req<=0;
            if(call_pulse && state!=IDLE) begin
                pending<=1;pending_ticket<=call_ticket;pending_room<=call_room;pending_prio<=call_prio;
            end
            case (state)
                IDLE: if (call_pulse || pending) begin
                    ticket<=call_pulse ? call_ticket : pending_ticket;
                    room<=call_pulse ? call_room : pending_room;
                    priority_call<=call_pulse ? call_prio : pending_prio;
                    pending<=0;
                    step<=0; announcing<=1; state<=SELECT;
                end
                SELECT: state<=ISSUE;
                ISSUE: if (clip_samples==0) state<=ADVANCE;
                    else if (!play_busy) begin
                        play_base<=clip_base; play_samples<=clip_samples; play_req<=1; state<=WAIT_BUSY;
                    end
                WAIT_BUSY: if (play_done) state<=ADVANCE; else if (play_busy) state<=WAIT_DONE;
                WAIT_DONE: if (play_done) state<=ADVANCE;
                ADVANCE: if (step==8 || step==MAX_STEPS-1) begin announcing<=0; state<=IDLE; end
                         else begin step<=step+1'b1; state<=SELECT; end
                default: state<=IDLE;
            endcase
        end
    end
endmodule

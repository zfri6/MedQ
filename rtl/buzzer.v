//============================================================================
// buzzer.v  — MedQ D-Group 蜂鸣器提示音
// Domain: clk_sys
//
// 三种音型：普通叫号(双响)/重呼(三响)/优先号(长响)。
// pattern[1]=1 → 优先，pattern[0]=1 → 重呼，pattern[1:0]=00 → 普通。
// mute=1 时关闭蜂鸣器。
//
// Port names and parameters frozen by doc/arch/interface_contract.yaml.
//============================================================================
`timescale 1ns / 1ps
module buzzer #(
    parameter integer CLK_HZ = 50000000
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        trig,     // 触发脉冲
    input  wire [1:0]  pattern,  // 0=普通 1=重呼 2=优先
    input  wire        mute,     // 静音

    output reg         beep,
    output reg         busy      // 音型播放中
);

    //========================================================================
    // 音型参数
    //========================================================================
    // 普通叫号：两短声，500 Hz，响 200ms 停 200ms 再响 200ms
    // 重呼：三短声，800 Hz，响 150ms 停 100ms 再响 150ms 停 100ms 再响 150ms
    // 优先号：长一声，1000 Hz，响 800ms，停 400ms（一个周期）
    // beep_pulse = 1 周期时 clk_sys

    // ---- 基础音频率参数 ----
    // 优先（长）：1000 Hz，周期 = 50000 / 1000 = 50000 clocks
    // 普通（短）：500 Hz，周期 = 50000 / 500  = 100000 clocks
    // 重呼（快）：800 Hz，周期 = 50000 / 800  = 62500 clocks

    localparam [16:0] PERIOD_PRIORITY = CLK_HZ/1000;  // 1 kHz
    localparam [16:0] PERIOD_NORMAL   = CLK_HZ/500; // 500 Hz
    localparam [16:0] PERIOD_RECALL   = CLK_HZ/800;  // 800 Hz

    // ---- 持续时间参数（单位：ms 换算为周期数，1ms = 50000 cycles）----
    localparam [25:0] DUR_SHORT  = CLK_HZ/5;  // 200ms @ 50MHz
    localparam [25:0] DUR_LONG   = CLK_HZ*4/5;  // 800ms @ 50MHz
    localparam [25:0] GAP        = CLK_HZ/5;  // 200ms
    localparam [25:0] GAP_SHORT  = CLK_HZ/10;   // 100ms

    //========================================================================
    // 状态机
    //========================================================================
    localparam ST_IDLE = 4'd0;

    // 普通双响：响(GAP)响(GAP)
    localparam ST_NORM_B1   = 4'd1;   // 第一声
    localparam ST_NORM_GAP1 = 4'd2;   // 间隔
    localparam ST_NORM_B2   = 4'd3;   // 第二声
    localparam ST_NORM_GAP2 = 4'd4;   // 结束间隔（可选）

    // 重呼三响：响(GAP)响(GAP)响(GAP)
    localparam ST_RECAL_B1  = 4'd5;
    localparam ST_RECAL_G1  = 4'd6;
    localparam ST_RECAL_B2  = 4'd7;
    localparam ST_RECAL_G2  = 4'd8;
    localparam ST_RECAL_B3  = 4'd9;

    // 优先长响：响(GAP)
    localparam ST_PRIO_B1   = 4'd10;

    reg [3:0] state_q, state_d;

    //========================================================================
    // 音型节拍计数器
    //========================================================================
    reg [25:0] beat_cnt;     // 持续时间计数
    reg [16:0] period_cnt;  // 方波周期计数

    //========================================================================
    // 当前音型的频率参数（组合逻辑）
    //========================================================================
    reg [16:0] cur_period;
    always @(*) begin
        case (state_q)
            ST_NORM_B1, ST_NORM_B2:   cur_period = PERIOD_NORMAL;
            ST_RECAL_B1, ST_RECAL_B2, ST_RECAL_B3: cur_period = PERIOD_RECALL;
            ST_PRIO_B1:               cur_period = PERIOD_PRIORITY;
            default:                   cur_period = PERIOD_NORMAL;
        endcase
    end

    //========================================================================
    // beep 生成：方波振荡器（在发声状态内）
    //========================================================================
    wire tone_active;
    assign tone_active =
        (state_q == ST_NORM_B1)   ||
        (state_q == ST_NORM_B2)   ||
        (state_q == ST_RECAL_B1)  ||
        (state_q == ST_RECAL_B2)  ||
        (state_q == ST_RECAL_B3)  ||
        (state_q == ST_PRIO_B1);

    //========================================================================
    // 组合逻辑：下一状态
    //========================================================================
    reg [3:0] next_state;
    reg       enter_new_state;

    always @(*) begin
        state_d = state_q;
        enter_new_state = 1'b0;

        case (state_q)
            ST_IDLE: begin
                if (trig && !mute) begin
                    case (pattern)
                        2'b01: begin state_d = ST_RECAL_B1; enter_new_state = 1'b1; end
                        2'b10: begin state_d = ST_PRIO_B1;  enter_new_state = 1'b1; end
                        default: begin state_d = ST_NORM_B1; enter_new_state = 1'b1; end  // 00 普通
                    endcase
                end
            end

            // ---- 普通双响 ----
            ST_NORM_B1: begin
                if (beat_cnt >= DUR_SHORT) begin
                    state_d = ST_NORM_GAP1;
                    enter_new_state = 1'b1;
                end
            end
            ST_NORM_GAP1: begin
                if (beat_cnt >= GAP) begin
                    state_d = ST_NORM_B2;
                    enter_new_state = 1'b1;
                end
            end
            ST_NORM_B2: begin
                if (beat_cnt >= DUR_SHORT) begin
                    state_d = ST_IDLE;
                end
            end

            // ---- 重呼三响 ----
            ST_RECAL_B1: begin
                if (beat_cnt >= DUR_SHORT) begin
                    state_d = ST_RECAL_G1;
                    enter_new_state = 1'b1;
                end
            end
            ST_RECAL_G1: begin
                if (beat_cnt >= GAP_SHORT) begin
                    state_d = ST_RECAL_B2;
                    enter_new_state = 1'b1;
                end
            end
            ST_RECAL_B2: begin
                if (beat_cnt >= DUR_SHORT) begin
                    state_d = ST_RECAL_G2;
                    enter_new_state = 1'b1;
                end
            end
            ST_RECAL_G2: begin
                if (beat_cnt >= GAP_SHORT) begin
                    state_d = ST_RECAL_B3;
                    enter_new_state = 1'b1;
                end
            end
            ST_RECAL_B3: begin
                if (beat_cnt >= DUR_SHORT) begin
                    state_d = ST_IDLE;
                end
            end

            // ---- 优先长响 ----
            ST_PRIO_B1: begin
                if (beat_cnt >= DUR_LONG) begin
                    state_d = ST_IDLE;
                end
            end

            default: state_d = ST_IDLE;
        endcase
    end

    //========================================================================
    // 时序逻辑
    //========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q   <= ST_IDLE;
            beat_cnt  <= {20{1'b0}};
            period_cnt <= {16{1'b0}};
            beep      <= 1'b0;
            busy      <= 1'b0;
        end else begin
            state_q <= state_d;

            // ---- 进入新状态时重置计数器 ----
            if (enter_new_state) begin
                beat_cnt  <= {20{1'b0}};
                period_cnt <= {16{1'b0}};
            end

            // ---- 静音处理 ----
            if (mute) begin
                beep  <= 1'b0;
                busy  <= (state_q != ST_IDLE);
            end else begin
                // ---- 持续时间计数 ----
                if (state_q != ST_IDLE) begin
                    beat_cnt <= beat_cnt + 20'd1;
                end else begin
                    beat_cnt <= {20{1'b0}};
                end

                // ---- 方波振荡 ----
                if (tone_active) begin
                    if (period_cnt < cur_period - 1)
                        period_cnt <= period_cnt + 16'd1;
                    else
                        period_cnt <= {16{1'b0}};
                    beep <= (period_cnt < (cur_period >> 1));
                end else begin
                    beep <= 1'b0;
                    period_cnt <= {16{1'b0}};
                end

                busy <= (state_q != ST_IDLE);
            end
        end
    end

endmodule

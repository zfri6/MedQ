//============================================================================
// param_ctrl.v  — MedQ D-Group 参数实时调节
// Domain: clk_sys
//
// 按键组合 + 拨码选择调节项，长按连续增减。
// param[63:0] 输出。
// osd_hint_id/osd_hint_val/osd_hint_vis 产生 OSD 提示，3 秒后自动隐藏。
//
// Port names frozen by doc/arch/interface_contract.yaml.
//============================================================================
`timescale 1ns / 1ps
module param_ctrl (
    input  wire        clk,
    input  wire        rst_n,

    // ---- 按键（来自 key_debounce）----
    input  wire [3:0]  key_press,  // 单周期按下沿脉冲
    input  wire [3:0]  key_hold,   // 长按持续高电平（>1s）

    // ---- 拨码 ----
    input  wire [3:0]  sw,

    // ---- 外部写入（来自 uart_cmd）----
    input  wire        ext_we,
    input  wire [3:0]  ext_sel,
    input  wire [7:0]  ext_val,

    // ---- 参数输出 ----
    output reg  [63:0] param,

    // ---- OSD 提示 ----
    output reg  [3:0]  osd_hint_id,
    output reg  [7:0]  osd_hint_val,
    output reg         osd_hint_vis
);

    //========================================================================
    // 参数索引
    //========================================================================
    localparam P_BRIGHTNESS       = 4'd0;
    localparam P_CONTRAST         = 4'd1;
    localparam P_VOLUME           = 4'd2;
    localparam P_SUBTITLE_SPEED   = 4'd3;
    localparam P_TRANSITION_MODE  = 4'd4;
    localparam P_SPECTRUM_MODE    = 4'd5;
    localparam P_OSD_LAYER_EN     = 4'd6;

    //========================================================================
    // 参数寄存器
    //========================================================================
    reg [7:0] brightness;
    reg [7:0] contrast;
    reg [7:0] volume;
    reg [7:0] subtitle_speed;
    reg [3:0] transition_mode;
    reg [3:0] spectrum_mode;
    reg [3:0] osd_layer_en;

    //========================================================================
    // 当前选中的参数
    //========================================================================
    reg [3:0] cur_sel;

    //========================================================================
    // 长按连续增减：双阶段定时器
    // 慢速：前 2 秒，每 2 秒增减 1
    // 快速：2 秒后，每 0.1 秒增减 1
    //========================================================================
    localparam [31:0] STEP_SLOW  = 32'd100000000;  // 2s  @ 50MHz
    localparam [31:0] STEP_FAST  = 32'd5000000;    // 0.1s @ 50MHz

    // 慢速定时器：只在慢速阶段计数
    reg [31:0] slow_timer;
    // 快速定时器：只在快速阶段循环计数
    reg [31:0] fast_timer;
    // 是否已进入快速阶段
    reg        fast_phase;

    // 增减方向：0=递减，1=递增
    reg        step_dir;
    // 本拍产生的增减脉冲
    reg        step_pulse;

    //========================================================================
    // OSD 提示超时：3 秒
    //========================================================================
    localparam [31:0] HINT_TIMEOUT = 32'd150000000;
    reg [31:0] hint_timer;

    //========================================================================
    // 辅助函数
    //========================================================================
    wire is_continuous;
    assign is_continuous = (cur_sel < P_TRANSITION_MODE);

    //========================================================================
    // 当前参数值读 mux
    //========================================================================
    reg [7:0] cur_val;
    always @(*) begin
        case (cur_sel)
            P_BRIGHTNESS:      cur_val = brightness;
            P_CONTRAST:        cur_val = contrast;
            P_VOLUME:          cur_val = volume;
            P_SUBTITLE_SPEED:  cur_val = subtitle_speed;
            P_TRANSITION_MODE: cur_val = {4'h0, transition_mode};
            P_SPECTRUM_MODE:   cur_val = {4'h0, spectrum_mode};
            P_OSD_LAYER_EN:    cur_val = {4'h0, osd_layer_en};
            default:            cur_val = 8'd0;
        endcase
    end

    //========================================================================
    // 饱和加减
    //========================================================================
    wire [7:0] val_plus1, val_minus1;
    assign val_plus1  = (cur_val < 8'd255) ? (cur_val + 8'd1) : 8'd255;
    assign val_minus1 = (cur_val > 8'd0)   ? (cur_val - 8'd1) : 8'd0;

    //========================================================================
    // 时序逻辑
    //========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            brightness       <= 8'd128;
            contrast         <= 8'd128;
            volume           <= 8'd200;
            subtitle_speed   <= 8'd4;
            transition_mode  <= 4'd0;
            spectrum_mode   <= 4'd0;
            osd_layer_en   <= 4'b1111;
            cur_sel         <= 4'd0;
            slow_timer      <= {32{1'b0}};
            fast_timer      <= {32{1'b0}};
            fast_phase      <= 1'b0;
            step_dir        <= 1'b0;
            step_pulse     <= 1'b0;
            hint_timer     <= {32{1'b0}};
            osd_hint_id     <= 4'd0;
            osd_hint_val    <= 8'd0;
            osd_hint_vis    <= 1'b0;
            param           <= 64'd0;
        end else begin
            // ---- 默认 ----
            step_pulse <= 1'b0;

            // ---- param 打包 ----
            param <= {
                20'h00000,
                osd_layer_en,
                spectrum_mode,
                transition_mode,
                subtitle_speed,
                volume,
                contrast,
                brightness
            };

            // ---- 参数选择 ----
            if (ext_we)
                cur_sel <= ext_sel;
            else if (|key_press)
                cur_sel <= sw;

            // ---- 外部写入 ----
            if (ext_we) begin
                case (ext_sel)
                    P_BRIGHTNESS:      brightness     <= ext_val;
                    P_CONTRAST:        contrast       <= ext_val;
                    P_VOLUME:          volume         <= ext_val;
                    P_SUBTITLE_SPEED:  subtitle_speed <= ext_val;
                    P_TRANSITION_MODE: transition_mode <= ext_val[3:0];
                    P_SPECTRUM_MODE:   spectrum_mode  <= ext_val[3:0];
                    P_OSD_LAYER_EN:    osd_layer_en  <= ext_val[3:0];
                    default: ;
                endcase
                osd_hint_id   <= ext_sel;
                osd_hint_val  <= ext_val;
                osd_hint_vis  <= 1'b1;
                hint_timer    <= {32{1'b0}};
            end

            // ---- 长按连续增减 ----
            if (key_hold[0]) begin
                // 递增
                step_dir <= 1'b1;
                if (!is_continuous) begin
                    // 离散参数：每次按键增一次
                    step_pulse <= key_press[0];
                end else begin
                    // 连续参数：双定时器
                    if (!fast_phase) begin
                        // 慢速阶段
                        if (slow_timer == (STEP_SLOW - 32'd1)) begin
                            // 进入快速阶段，同时产生一次脉冲
                            fast_phase   <= 1'b1;
                            slow_timer   <= {32{1'b0}};
                            step_pulse   <= 1'b1;
                        end else begin
                            slow_timer <= slow_timer + 32'd1;
                        end
                    end else begin
                        // 快速阶段
                        if (fast_timer == (STEP_FAST - 32'd1)) begin
                            fast_timer  <= {32{1'b0}};
                            step_pulse <= 1'b1;
                        end else begin
                            fast_timer <= fast_timer + 32'd1;
                        end
                    end
                end
            end else if (key_hold[1]) begin
                // 递减
                step_dir <= 1'b0;
                if (!is_continuous) begin
                    step_pulse <= key_press[1];
                end else begin
                    if (!fast_phase) begin
                        if (slow_timer == (STEP_SLOW - 32'd1)) begin
                            fast_phase  <= 1'b1;
                            slow_timer  <= {32{1'b0}};
                            step_pulse  <= 1'b1;
                        end else begin
                            slow_timer <= slow_timer + 32'd1;
                        end
                    end else begin
                        if (fast_timer == (STEP_FAST - 32'd1)) begin
                            fast_timer  <= {32{1'b0}};
                            step_pulse  <= 1'b1;
                        end else begin
                            fast_timer <= fast_timer + 32'd1;
                        end
                    end
                end
            end else begin
                // 释放：清零定时器
                slow_timer  <= {32{1'b0}};
                fast_timer  <= {32{1'b0}};
                fast_phase  <= 1'b0;
            end

            // ---- 确认键（KEY2） ----
            if (key_press[2]) begin
                osd_hint_id   <= cur_sel;
                osd_hint_val  <= cur_val;
                osd_hint_vis  <= 1'b1;
                hint_timer    <= {32{1'b0}};
            end

            // ---- 应用增减 ----
            if (step_pulse) begin
                if (step_dir) begin
                    case (cur_sel)
                        P_BRIGHTNESS:      brightness     <= val_plus1;
                        P_CONTRAST:        contrast       <= val_plus1;
                        P_VOLUME:          volume         <= val_plus1;
                        P_SUBTITLE_SPEED:  subtitle_speed <= val_plus1;
                        P_TRANSITION_MODE: transition_mode <= (transition_mode < 4'd4) ? (transition_mode + 4'd1) : 4'd4;
                        P_SPECTRUM_MODE:   spectrum_mode  <= (spectrum_mode  < 4'd3) ? (spectrum_mode  + 4'd1) : 4'd3;
                        P_OSD_LAYER_EN:    osd_layer_en  <= (osd_layer_en  < 4'hF)  ? (osd_layer_en  + 4'd1) : 4'hF;
                        default: ;
                    endcase
                end else begin
                    case (cur_sel)
                        P_BRIGHTNESS:      brightness     <= val_minus1;
                        P_CONTRAST:        contrast       <= val_minus1;
                        P_VOLUME:          volume         <= val_minus1;
                        P_SUBTITLE_SPEED:  subtitle_speed <= val_minus1;
                        P_TRANSITION_MODE: transition_mode <= (transition_mode > 4'd0) ? (transition_mode - 4'd1) : 4'd0;
                        P_SPECTRUM_MODE:   spectrum_mode  <= (spectrum_mode  > 4'd0) ? (spectrum_mode  - 4'd1) : 4'd0;
                        P_OSD_LAYER_EN:    osd_layer_en  <= (osd_layer_en  > 4'd0) ? (osd_layer_en  - 4'd1) : 4'd0;
                        default: ;
                    endcase
                end
                osd_hint_id   <= cur_sel;
                osd_hint_val  <= cur_val;
                osd_hint_vis  <= 1'b1;
                hint_timer    <= {32{1'b0}};
            end

            // ---- OSD 提示超时（3 秒）----
            if (osd_hint_vis) begin
                if (hint_timer >= HINT_TIMEOUT - 32'd1) begin
                    osd_hint_vis <= 1'b0;
                    hint_timer   <= {32{1'b0}};
                end else begin
                    hint_timer <= hint_timer + 32'd1;
                end
            end else begin
                hint_timer <= {32{1'b0}};
            end
        end
    end

endmodule

//============================================================================
// seg_scan.v  — MedQ D-Group 8 位数码管动态扫描
// Domain: clk_sys
//
// 8 位数码管，动态扫描 1 kHz。
// 输入 8 个 4-bit BCD 值（digit0 在低位），输出段码和位选。
// SEG_ACTIVE_LOW=1 表示共阳数码管（段输出低电平点亮）。
// SEL_ACTIVE_LOW=1 表示位选低有效。
//
// Port names and parameters frozen by doc/arch/interface_contract.yaml.
//============================================================================
`timescale 1ns / 1ps
module seg_scan #(
    parameter integer CLK_HZ      = 50000000,
    parameter integer SCAN_HZ     = 1000,
    parameter         SEG_ACTIVE_LOW = 1,   // 1=共阳(低点亮)，0=共阴(高点亮)
    parameter         SEL_ACTIVE_LOW = 1    // 1=低有效位选，0=高有效
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [31:0] digits,   // 8 个 4-bit BCD，digit0 在低位
    input  wire [7:0]  dp,       // bit[n]=1 表示 digit[n] 显示小数点
    input  wire [7:0]  blank,    // bit[n]=1 表示 digit[n] 熄灭

    output reg  [7:0]  seg_data, // {dp,g,f,e,d,c,b,a}
    output reg  [7:0]  seg_sel   // 位选，低有效
);

    //========================================================================
    // 分频计数：1 kHz 扫描频率
    //========================================================================
    localparam DIV = CLK_HZ / (SCAN_HZ * 8);  // 6250
    localparam DIV_M1 = DIV - 1;

    localparam [13:0] DIV_MAX = DIV_M1[13:0];  // 安全宽度

    reg [13:0] div_cnt;

    //========================================================================
    // 位选计数：0..7 循环
    //========================================================================
    reg [2:0] sel_idx;   // 当前扫描位

    //========================================================================
    // BCD → 7 段译码（共阳：a=1 段亮；共阴：a=0 段亮）
    // seg_raw[6] = g, [5]=f, [4]=e, [3]=d, [2]=c, [1]=b, [0]=a
    //========================================================================
    function [6:0] bcd_to_7seg(input [3:0] bcd);
        begin
            case (bcd)
                4'h0: bcd_to_7seg = 7'b1111110; // 0
                4'h1: bcd_to_7seg = 7'b0110000; // 1
                4'h2: bcd_to_7seg = 7'b1101101; // 2
                4'h3: bcd_to_7seg = 7'b1111001; // 3
                4'h4: bcd_to_7seg = 7'b0110011; // 4
                4'h5: bcd_to_7seg = 7'b1011011; // 5
                4'h6: bcd_to_7seg = 7'b1011111; // 6
                4'h7: bcd_to_7seg = 7'b1110000; // 7
                4'h8: bcd_to_7seg = 7'b1111111; // 8
                4'h9: bcd_to_7seg = 7'b1111011; // 9
                4'hA: bcd_to_7seg = 7'b1110111; // A
                4'hB: bcd_to_7seg = 7'b0011111; // b
                4'hC: bcd_to_7seg = 7'b1001110; // C
                4'hD: bcd_to_7seg = 7'b0111101; // d
                4'hE: bcd_to_7seg = 7'b1001111; // E
                4'hF: bcd_to_7seg = 7'b1000111; // F
                default: bcd_to_7seg = 7'b0000000; // 空白
            endcase
        end
    endfunction

    //========================================================================
    // 当前位选对应的 BCD 值
    //========================================================================
    wire [3:0] cur_bcd;
    wire       cur_dp;
    wire       cur_blank;
    wire [6:0] cur_7seg_raw;

    assign cur_bcd    = digits[sel_idx * 4 +: 4];
    assign cur_dp     = dp[sel_idx];
    assign cur_blank  = blank[sel_idx];
    assign cur_7seg_raw = bcd_to_7seg(cur_bcd);

    //========================================================================
    // 段码输出：{dp, g, f, e, d, c, b, a}
    // SEG_ACTIVE_LOW=1: 段码取反（1→0 亮）
    //========================================================================
    wire [7:0] seg_data_raw;
    assign seg_data_raw = {cur_dp, cur_7seg_raw};

    wire [7:0] seg_data_active;
    generate
        if (SEG_ACTIVE_LOW) begin : gen_seg_active_low
            assign seg_data_active = ~seg_data_raw;
        end else begin : gen_seg_active_high
            assign seg_data_active = seg_data_raw;
        end
    endgenerate

    //========================================================================
    // 位选输出：SEL_ACTIVE_LOW=1 → 低有效
    //========================================================================
    wire [7:0] sel_onehot;
    assign sel_onehot = (8'b00000001 << sel_idx);

    wire [7:0] sel_active;
    generate
        if (SEL_ACTIVE_LOW) begin : gen_sel_active_low
            assign sel_active = ~sel_onehot;
        end else begin : gen_sel_active_high
            assign sel_active = sel_onehot;
        end
    endgenerate

    //========================================================================
    // 时序逻辑
    //========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div_cnt <= {14{1'b0}};
            sel_idx <= 3'd0;
            seg_data <= 8'hFF;   // 全部熄灭（低有效时 FF=灭）
            seg_sel  <= 8'h00;   // 全部关闭（低有效时 00=全部关闭）
        end else begin
            // ---- 分频计数 ----
            if (div_cnt < DIV_MAX) begin
                div_cnt <= div_cnt + 14'd1;
            end else begin
                div_cnt <= {14{1'b0}};

                // ---- 切换到下一位 ----
                if (sel_idx == 3'd7)
                    sel_idx <= 3'd0;
                else
                    sel_idx <= sel_idx + 3'd1;
            end

            // ---- 段码输出：当前位（分频周期结束时稳定）----
            if (div_cnt == DIV_MAX) begin
                if (cur_blank) begin
                    // 熄灭：该位所有段=高（低有效时 0xFF 灭）
                    seg_data <= 8'hFF;
                end else begin
                    seg_data <= seg_data_active;
                end
                seg_sel <= sel_active;
            end
        end
    end

endmodule

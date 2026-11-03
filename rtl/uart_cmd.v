`timescale 1ns / 1ps
// 55 AA CMD ROOM TICKET_H TICKET_L PARAM CRC8/ATM (MSB-first), ACK/NAK.
module uart_cmd (
    input  wire        clk,
    input  wire        rst_n,

    // ---- UART 接收 ----
    input  wire        rx_valid,
    input  wire [7:0] rx_data,

    // ---- UART 发送 ----
    output reg         tx_valid,
    input  wire        tx_ready,
    output reg  [7:0]  tx_data,

    // ---- 命令输出 ----
    output reg         cmd_next,    // 叫下一号
    output reg         cmd_recall,  // 重呼
    output reg         cmd_skip,    // 过号
    output reg         cmd_arrive,  // 取号
    output reg         cmd_page,    // 切页
    output reg         cmd_param_we,     // 参数写使能
    output reg  [3:0]  cmd_param_sel,   // 参数选择
    output reg  [7:0]  cmd_param_val    // 参数值
);


    reg [2:0] index;
    reg [7:0] command,selector,value,crc;
    reg replying;
    function [7:0] update_crc;
        input [7:0] prior,byte_value;
        integer bit_index;
        reg [7:0] work;
        begin
            work=prior^byte_value;
            for(bit_index=0;bit_index<8;bit_index=bit_index+1) work=work[7] ? (work<<1)^8'h07 : work<<1;
            update_crc=work;
        end
    endfunction
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            index<=0; command<=0; selector<=0; value<=0; crc<=0; replying<=0;
            tx_valid<=0; tx_data<=0;
            cmd_next<=0; cmd_recall<=0; cmd_skip<=0; cmd_arrive<=0; cmd_page<=0;
            cmd_param_we<=0; cmd_param_sel<=0; cmd_param_val<=0;
        end else begin
            cmd_next<=0; cmd_recall<=0; cmd_skip<=0; cmd_arrive<=0; cmd_page<=0; cmd_param_we<=0;
            if(tx_valid && tx_ready) begin tx_valid<=0; replying<=0; end
            if(rx_valid && !replying) case(index)
                0: if(rx_data==8'h55) index<=1;
                1: if(rx_data==8'haa) begin index<=2; crc<=0; end
                   else index<=rx_data==8'h55 ? 1 : 0;
                2: begin command<=rx_data; crc<=update_crc(crc,rx_data); index<=3; end
                3: begin selector<=rx_data; crc<=update_crc(crc,rx_data); index<=4; end
                4: begin crc<=update_crc(crc,rx_data); index<=5; end
                5: begin crc<=update_crc(crc,rx_data); index<=6; end
                6: begin value<=rx_data; crc<=update_crc(crc,rx_data); index<=7; end
                7: begin
                    index<=0; tx_valid<=1; replying<=1;
                    if(rx_data==crc && command>=1 && command<=6) begin
                        tx_data<=8'h06;
                        case(command)
                            1:cmd_next<=1;
                            2:cmd_recall<=1;
                            3:cmd_skip<=1;
                            4:cmd_arrive<=1;
                            5:begin cmd_param_we<=1; cmd_param_sel<=selector[3:0]; cmd_param_val<=value; end
                            6:cmd_page<=1;
                        endcase
                    end else tx_data<=8'h15;
                end
            endcase
        end
    end
endmodule

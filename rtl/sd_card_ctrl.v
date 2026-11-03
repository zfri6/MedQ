`timescale 1ns / 1ps
// SD SPI initialization and CMD17 reader, with finite response/token timeouts.
module sd_card_ctrl #(parameter INIT_CLK_DIV=62, DATA_CLK_DIV=1, RESPONSE_LIMIT=255, INIT_RETRIES=1024, TOKEN_LIMIT=65535) (
    input  wire       clk,
    input  wire       rst_n,
    // Read request
    input  wire       rd_req,
    input  wire [31:0] rd_lba,
    output wire       rd_busy,
    output reg        rd_done,
    output reg        rd_err,
    // Byte stream output
    output reg        byte_valid,
    output reg  [7:0] byte_data,
    output reg  [8:0] byte_idx,
    // Status
    output reg        card_ready,
    output reg        card_sdhc,
    output reg        init_fail,
    // SPI physical interface
    output wire       spi_sclk,
    output wire       spi_mosi,
    input  wire       spi_miso,
    output reg        spi_cs_n
);


    localparam POWER=0, ISSUE=1, COMMAND=2, RESPONSE=3, EXTRA=4,
               HANDLE=5, GAP=6, READY=7, TOKEN=8, DATA=9, CRC=10, FAILED=11;
    reg [3:0] state;
    reg [2:0] phase;
    reg [47:0] command_frame;
    reg [2:0] byte_count;
    reg [3:0] power_count;
    reg [15:0] polls, retries;
    reg [7:0] r1;
    reg [31:0] extra_data, pending_lba;
    reg pending, waiting;
    wire tx_ready, rx_valid;
    wire [7:0] rx_data;
    wire sending=state==POWER || state==COMMAND || state==RESPONSE || state==EXTRA ||
                 state==GAP || state==TOKEN || state==DATA || state==CRC;
    wire [7:0] tx_data=state==COMMAND ? command_frame[47-byte_count*8 -: 8] : 8'hff;
    sd_spi_master u_spi (.clk(clk),.rst_n(rst_n),.clk_div(card_ready ? DATA_CLK_DIV[7:0] : INIT_CLK_DIV[7:0]),
        .tx_valid(sending && !waiting),.tx_ready(tx_ready),.tx_data(tx_data),
        .rx_valid(rx_valid),.rx_data(rx_data),.busy(),.spi_sclk(spi_sclk),.spi_mosi(spi_mosi),.spi_miso(spi_miso));
    assign rd_busy=!card_ready || pending || phase==6;
    function [47:0] make_command;
        input [5:0] command;
        input [31:0] argument;
        reg [39:0] message;
        reg [6:0] crc;
        reg feedback;
        integer bit_no;
        begin
            message={2'b01,command,argument}; crc=0;
            for (bit_no=39;bit_no>=0;bit_no=bit_no-1) begin
                feedback=crc[6]^message[bit_no];
                crc={crc[5:0],1'b0};
                if (feedback) crc=crc^7'h09;
            end
            make_command={message,crc,1'b1};
        end
    endfunction
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=POWER; phase<=0; command_frame<=0; byte_count<=0; power_count<=0;
            polls<=0; retries<=0; r1<=0; extra_data<=0; pending_lba<=0;
            pending<=0; waiting<=0; card_ready<=0; card_sdhc<=0; init_fail<=0;
            spi_cs_n<=1; rd_done<=0; rd_err<=0; byte_valid<=0; byte_data<=0; byte_idx<=0;
        end else begin
            rd_done<=0; rd_err<=0; byte_valid<=0;
            if (rd_req && !pending && phase!=6) begin pending<=1; pending_lba<=rd_lba; end
            if (sending && !waiting && tx_ready) waiting<=1;
            if (rx_valid) waiting<=0;
            case (state)
                POWER: if (rx_valid) begin
                    if (power_count==9) state<=ISSUE;
                    else power_count<=power_count+1'b1;
                end
                ISSUE: begin
                    spi_cs_n<=0; byte_count<=0; polls<=0;
                    case (phase)
                        0: command_frame<=make_command(0,0);
                        1: command_frame<=make_command(8,32'h1aa);
                        2: command_frame<=make_command(55,0);
                        3: command_frame<=make_command(41,32'h40000000);
                        4: command_frame<=make_command(58,0);
                        5: command_frame<=make_command(16,512);
                        6: command_frame<=make_command(17,card_sdhc ? pending_lba : pending_lba<<9);
                        default: command_frame<=make_command(0,0);
                    endcase
                    state<=COMMAND;
                end
                COMMAND: if (rx_valid) begin
                    if (byte_count==5) state<=RESPONSE;
                    else byte_count<=byte_count+1'b1;
                end
                RESPONSE: if (rx_valid) begin
                    if (!rx_data[7]) begin
                        r1<=rx_data; byte_count<=0; extra_data<=0;
                        state<=(phase==1 || phase==4) ? EXTRA : HANDLE;
                    end else if (polls==RESPONSE_LIMIT-1) begin
                        spi_cs_n<=1;
                        if (phase==6) begin rd_err<=1; pending<=0; phase<=0; state<=READY; end
                        else begin init_fail<=1; state<=FAILED; end
                    end else polls<=polls+1'b1;
                end
                EXTRA: if (rx_valid) begin
                    extra_data<={extra_data[23:0],rx_data};
                    if (byte_count==3) state<=HANDLE;
                    else byte_count<=byte_count+1'b1;
                end
                HANDLE: begin
                    spi_cs_n<=!(phase==6 && r1==0);
                    state<=GAP;
                    case (phase)
                        0: if (r1==1) phase<=1; else begin init_fail<=1; state<=FAILED; end
                        1: if (r1==1 && extra_data==32'h1aa) phase<=2;
                           else begin init_fail<=1; state<=FAILED; end
                        2: if (r1<=1) phase<=3; else begin init_fail<=1; state<=FAILED; end
                        3: if (r1==0) phase<=4;
                           else if (r1==1 && retries<INIT_RETRIES) begin retries<=retries+1'b1; phase<=2; end
                           else begin init_fail<=1; state<=FAILED; end
                        4: if (r1==0) begin
                            card_sdhc<=extra_data[30];
                            if (extra_data[30]) begin card_ready<=1; state<=READY; phase<=0; end
                            else phase<=5;
                        end else begin init_fail<=1; state<=FAILED; end
                        5: if (r1==0) begin card_ready<=1; state<=READY; phase<=0; end
                           else begin init_fail<=1; state<=FAILED; end
                        6: if (r1==0) begin polls<=0; state<=TOKEN; end
                           else begin rd_err<=1; pending<=0; phase<=0; state<=READY; end
                        default: state<=FAILED;
                    endcase
                end
                GAP: if (rx_valid) state<=ISSUE;
                READY: if (pending) begin phase<=6; state<=ISSUE; end
                TOKEN: if (rx_valid) begin
                    if (rx_data==8'hfe) begin byte_idx<=0; state<=DATA; end
                    else if (polls==TOKEN_LIMIT-1 || rx_data!=8'hff) begin
                        rd_err<=1; pending<=0; phase<=0; spi_cs_n<=1; state<=READY;
                    end else polls<=polls+1'b1;
                end
                DATA: if (rx_valid) begin
                    byte_valid<=1; byte_data<=rx_data;
                    if (byte_idx==511) begin byte_count<=0; state<=CRC; end
                    else byte_idx<=byte_idx+1'b1;
                end
                CRC: if (rx_valid) begin
                    if (byte_count==1) begin
                        rd_done<=1; pending<=0; phase<=0; spi_cs_n<=1; state<=READY;
                    end else byte_count<=byte_count+1'b1;
                end
                FAILED: if (pending) begin rd_err<=1; pending<=0; end
                default: state<=FAILED;
            endcase
        end
    end
endmodule

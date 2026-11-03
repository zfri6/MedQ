`timescale 1ns / 1ps
// SPI mode 0: launch before rising edge; sample on rising, change on falling.
module sd_spi_master (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] clk_div,    // SCLK = clk / (2*(clk_div+1))
    input  wire       tx_valid,
    output wire       tx_ready,
    input  wire [7:0] tx_data,
    output reg        rx_valid,
    output reg  [7:0] rx_data,
    output wire       busy,
    output reg        spi_sclk,
    output reg        spi_mosi,
    input  wire       spi_miso
);


    reg active;
    reg [7:0] divider,limit,tx_shift,rx_shift;
    reg [2:0] bit_index;
    assign tx_ready=!active;
    assign busy=active;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active<=0; divider<=0; limit<=0; tx_shift<=0; rx_shift<=0; bit_index<=0;
            spi_sclk<=0; spi_mosi<=1; rx_valid<=0; rx_data<=0;
        end else begin
            rx_valid<=0;
            if (!active) begin
                spi_sclk<=0;
                if (tx_valid) begin
                    active<=1; divider<=0; limit<=clk_div; tx_shift<=tx_data;
                    spi_mosi<=tx_data[7]; rx_shift<=0; bit_index<=0;
                end
            end else if (divider==limit) begin
                divider<=0;
                if (!spi_sclk) begin
                    spi_sclk<=1;
                    rx_shift<={rx_shift[6:0],spi_miso};
                end else begin
                    spi_sclk<=0;
                    if (bit_index==7) begin
                        active<=0; rx_valid<=1; rx_data<=rx_shift; spi_mosi<=1;
                    end else begin
                        bit_index<=bit_index+1'b1;
                        tx_shift<={tx_shift[6:0],1'b1}; spi_mosi<=tx_shift[6];
                    end
                end
            end else divider<=divider+1'b1;
        end
    end
endmodule

`timescale 1ns / 1ps
// One word per glyph row, MSB-left. ASCII: 0..1535 (96*16),
// Chinese: 1536..3583 (128*16), large: 3584..5503 (40*48).
// AA UI atlas: 8192..16383, 256x512 pixels, 16 two-bit pixels/word.
// All 16384 words are initialized by the supplied font_rom.hex.
module font_rom #(
    parameter ADDR_W  = 14,         // 2^14 = 16384 rows
    parameter HEXFILE = "font_rom.hex"
) (
    input  wire        clk,
    input  wire [ADDR_W-1:0] addr,
    output reg  [31:0] dout         // glyph row, MSB on left
);

    reg [31:0] rom [0:(1<<ADDR_W)-1];

    // Synchronous read
    always @(posedge clk) begin
        dout <= rom[addr];
    end

    // Initialization
    initial begin
        $readmemh(HEXFILE, rom);
    end

endmodule

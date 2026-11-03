`timescale 1ns / 1ps
// 10:1 DDR serializer; non-SIMULATION uses the installed EG4 ODDR primitive.
module tmds_serdes(input wire clk_pix,clk_ser,rst_n,input wire [9:0] din,output wire sdata_p);
`ifdef SIMULATION
    reg [9:0] pixel_word;
    reg pixel_toggle;
    reg seen;
    reg [9:0] shift_word;
    reg [3:0] left;
    reg serial_bit;
    always @(posedge clk_pix or negedge rst_n) begin
        if (!rst_n) begin pixel_word<=0; pixel_toggle<=0; end
        else begin pixel_word<=din; pixel_toggle<=~pixel_toggle; end
    end
    // Behavioral DDR serializer: ten serial edges per pixel, LSB first.
    always @(posedge clk_ser or negedge clk_ser or negedge rst_n) begin
        if (!rst_n) begin seen<=0; shift_word<=0; left<=0; serial_bit<=0; end
        else if (pixel_toggle!=seen) begin
            seen<=pixel_toggle; serial_bit<=pixel_word[0];
            shift_word<={1'b0,pixel_word[9:1]}; left<=9;
        end else if (left!=0) begin
            serial_bit<=shift_word[0]; shift_word<={1'b0,shift_word[9:1]}; left<=left-1'b1;
        end
    end
    assign sdata_p=serial_bit;

`else
    // Related 25/125 MHz PLL clocks, ten DDR bits per pixel, LSB first.
    // A new word is held in the pixel domain for five serial cycles.
    // On coincident positive edges the old toggle/word is sampled; the next
    // serial edge loads the new pair. Keep this related-clock path in STA.
    reg [9:0] pixel_word;
    reg pixel_toggle;
    reg seen;
    reg [7:0] shift_pairs;
    wire load_word = pixel_toggle != seen;
    wire [1:0] pair_bits = load_word ? pixel_word[1:0] : shift_pairs[1:0];
    always @(posedge clk_pix or negedge rst_n) begin
        if (!rst_n) begin pixel_word<=0; pixel_toggle<=0; end
        else begin pixel_word<=din; pixel_toggle<=~pixel_toggle; end
    end
    always @(posedge clk_ser or negedge rst_n) begin
        if (!rst_n) begin seen<=0; shift_pairs<=0; end
        else if (load_word) begin
            seen<=pixel_toggle;
            shift_pairs<=pixel_word[9:2];
        end else shift_pairs<={2'b00,shift_pairs[7:2]};
    end
    // EG4 library: d0 is sampled on posedge; d1 is also captured on that
    // posedge, then emitted on negedge. Both inputs must describe ONE pair.
    EG_LOGIC_ODDR #(.ASYNCRST("ENABLE")) u_oddr (
        .q(sdata_p), .clk(clk_ser), .d0(pair_bits[0]),
        .d1(pair_bits[1]), .rst(~rst_n));
`endif
endmodule

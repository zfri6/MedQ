// =============================================================================
// MedQ - spi_flash_store
// Differentiating Feature G3: Queue-state persistence to SPI NOR Flash
//
// Storage layout per slot (20 bytes):
//   Bytes 0..15 : save_data[127:0]   (LSB = byte 0)
//   Bytes 16..19: CRC-32 of bytes 0..15  (Ethernet polynomial 0x04C11DB7,
//            reflected input, reflected output, final XOR 0xFFFFFFFF)
//
// Dual-slot protocol:
//   - active_slot[0]: last-written slot (0=A, 1=B).  Reset to A.
//   - Save: erase non-active, program it, flip active_slot.
//   - Load: read both slots, CRC-check both, prefer A, fail if both bad.
//   - SLOT_A_ADDR = 0x000000, SLOT_B_ADDR = 0x001000 (4 KiB sectors).
//
// Flash commands: 0x06 WREN, 0x20 SECTOR_ERASE (3-byte addr),
//   0x02 PAGE_PROGRAM (3-byte addr), 0x03 READ (3-byte addr), 0x05 RDSR.
//
// SPI: CPOL=0 CPHA=0, MSB first.  SCLK = 6.25 MHz (div=3 @ 50 MHz).
//
// Pin notes:
//   fl_sclk, fl_mosi, fl_cs_n: output; fl_miso: input.
//   Physical pins pending schematic confirmation (Q4 in risks.md).
//   Simulation: use tb/spi_flash_model.v.
//
// Constraints (EG4S20BG256 / TD 6.2.1):
//   - Verilog-2001 only.
//   - Synchronous reset on all registers.
//   - No initial statements.
//   - All FSM branches close; no silent latches.
// =============================================================================
`timescale 1ns / 1ps

module spi_flash_store (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        save_req,
    input  wire [127:0] save_data,
    output wire        save_busy,
    output wire        save_done,

    input  wire        load_req,
    output wire [127:0] load_data,
    output wire        load_valid,
    output wire        load_fail,

    output wire        fl_sclk,
    output wire        fl_mosi,
    input  wire        fl_miso,
    output wire        fl_cs_n
);

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam SLOT_A_ADDR    = 24'h000000;
    localparam SLOT_B_ADDR    = 24'h001000;
    localparam CMD_WREN        = 8'h06;
    localparam CMD_SECTOR_ERASE= 8'h20;
    localparam CMD_PAGE_PROGRAM = 8'h02;
    localparam CMD_READ        = 8'h03;
    localparam CMD_RDSR        = 8'h05;
    localparam PAYLOAD_BYTES  = 5'd20;   // 16 data + 4 CRC
    localparam SPI_DIV         = 8'd3;    // 50MHz/8 = 6.25 MHz
    localparam ERASE_POLL_MAX  = 16'd5000;
    localparam PGM_POLL_MAX    = 16'd200;

    // =========================================================================
    // SPI physical signals (registered)
    // =========================================================================
    reg sclk_r, mosi_r, cs_n_r;
    assign fl_sclk = sclk_r;
    assign fl_mosi = mosi_r;
    assign fl_cs_n = cs_n_r;

    // =========================================================================
    // Clock divider
    // =========================================================================
    reg [7:0] div_c;
    wire div_t = (div_c == SPI_DIV);
    wire div_h = (div_c == {1'b0, SPI_DIV[7:1]});  // halfway tick
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) div_c <= 8'h0;
        else div_c <= div_t ? 8'h0 : (div_c + 8'h1);
    end

    // =========================================================================
    // SPI byte engine
    //
    // Simple bit-banged SPI, byte-at-a-time.
    // tx_len = number of bytes to send in this transaction.
    // rx_buf_r = last byte received (valid when rx_done pulses).
    // The engine reads tx_byte_r and increments its own counter.
    // =========================================================================
    localparam SE_IDLE = 2'd0;
    localparam SE_BIT  = 2'd1;
    localparam SE_DONE = 2'd2;
    localparam SE_HOLD = 2'd3;

    reg [1:0] se_st;
    reg [7:0] tx_byte_r;
    reg [7:0] tx_byte_sel;
    reg [5:0] tx_len;      // total bytes in this transaction
    reg [5:0] tx_idx;      // bytes sent so far
    reg        tx_go;
    reg        tx_go_d1;
    wire       tx_start = tx_go && !tx_go_d1;
    reg [2:0] bit_idx;
    reg [7:0] rx_byte_r;
    reg        rx_done;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            se_st    <= SE_IDLE;
            sclk_r   <= 1'b0;
            mosi_r   <= 1'b0;
            cs_n_r   <= 1'b1;
            tx_go_d1 <= 1'b0;
            rx_done  <= 1'b0;
            tx_byte_r <= 8'h00;
        end else begin
            tx_go_d1 <= tx_go;
            rx_done  <= 1'b0;
            // The byte engine is the sole owner of its shift register.
            if (se_st == SE_IDLE && tx_go) tx_byte_r <= tx_byte_sel;

            case (se_st)
                SE_IDLE: begin
                    sclk_r <= 1'b0;
                    mosi_r <= 1'b0;
                    bit_idx <= 3'd7;
                    tx_idx  <= 6'd0;
                    if (tx_start) begin
                        cs_n_r <= 1'b0;
                        se_st  <= SE_BIT;
                    end
                end

                SE_BIT: begin
                    cs_n_r <= 1'b0;
                    if (div_h) begin
                        sclk_r <= 1'b1;
                        rx_byte_r <= {rx_byte_r[6:0], fl_miso};
                    end
                    if (div_t) begin
                        sclk_r <= 1'b0;
                        mosi_r <= tx_byte_r[7];
                        tx_byte_r <= {tx_byte_r[6:0], 1'b0};
                        if (bit_idx == 3'd0) begin
                            bit_idx <= 3'd7;
                            tx_idx  <= tx_idx + 6'd1;
                            se_st   <= SE_DONE;
                        end else
                            bit_idx <= bit_idx - 3'd1;
                    end
                end

                SE_DONE: begin
                    cs_n_r <= 1'b0;
                    sclk_r <= 1'b0;
                    rx_done <= 1'b1;
                    if (tx_idx == tx_len) se_st <= SE_HOLD;
                    else se_st <= SE_BIT;
                end

                SE_HOLD: begin
                    cs_n_r <= 1'b1;
                    sclk_r <= 1'b0;
                    se_st  <= SE_IDLE;
                end

                default: se_st <= SE_IDLE;
            endcase
        end
    end

    wire spi_busy = (se_st != SE_IDLE);

    // =========================================================================
    // CRC-32 engine (bit-serial, Ethernet polynomial 0x04C11DB7)
    //
    // crc_init:    pulse to reset acc to 0xFFFFFFFF
    // crc_byte_i:  the byte to feed next
    // crc_feed:    strobe: load crc_byte_i, advance counter
    // crc_done:    pulses after the last bit of the last byte is processed
    // crc_result:  final CRC (reflected + XOR 0xFFFFFFFF), valid at crc_done
    // crc_bytes_n: how many bytes remain to process (0=idle)
    // =========================================================================
    reg        crc_init;
    reg        crc_feed;
    reg [7:0] crc_byte_i;
    reg [7:0] crc_shift;
    reg [31:0] crc_acc;
    reg [4:0]  crc_bytes_n;   // 0 = idle
    reg [2:0]  crc_bit_i;
    reg        crc_last;       // processing last bit of last byte
    reg        crc_done;
    reg [31:0] crc_result;

    wire crc_active = (crc_bytes_n != 5'd0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            crc_shift    <= 8'h00;
            crc_acc      <= 32'hFFFFFFFF;
            crc_bytes_n  <= 5'd0;
            crc_bit_i    <= 3'd0;
            crc_last     <= 1'b0;
            crc_done     <= 1'b0;
            crc_result   <= 32'h0;
        end else begin
            crc_done <= 1'b0;

            if (crc_init) begin
                crc_acc     <= 32'hFFFFFFFF;
                crc_bytes_n <= 5'd0;
                crc_bit_i   <= 3'd0;
                crc_last    <= 1'b0;
            end

            if (crc_feed) begin
                crc_shift <= crc_byte_i;
                crc_bytes_n <= (crc_bytes_n == 5'd0) ? 5'd16 : (crc_bytes_n - 5'd1);
                crc_bit_i  <= 3'd7;
            end

            if (crc_active) begin
                // LFSR step
                crc_acc[0]  <= crc_acc[31] ^ crc_shift[0];
                crc_acc[1]  <= crc_acc[0];
                crc_acc[2]  <= crc_acc[1] ^ crc_acc[31] ^ crc_shift[0];
                crc_acc[3]  <= crc_acc[2];
                crc_acc[4]  <= crc_acc[3] ^ crc_acc[31] ^ crc_shift[0];
                crc_acc[5]  <= crc_acc[4] ^ crc_acc[31] ^ crc_shift[0];
                crc_acc[6]  <= crc_acc[5];
                crc_acc[7]  <= crc_acc[6] ^ crc_acc[31] ^ crc_shift[0];
                crc_acc[8]  <= crc_acc[7] ^ crc_acc[31] ^ crc_shift[0];
                crc_acc[9]  <= crc_acc[8];
                crc_acc[10] <= crc_acc[9] ^ crc_acc[31] ^ crc_shift[0];
                crc_acc[11] <= crc_acc[10] ^ crc_acc[31] ^ crc_shift[0];
                crc_acc[12] <= crc_acc[11] ^ crc_acc[12] ^ crc_acc[13] ^ crc_acc[14]
                             ^ crc_acc[15] ^ crc_acc[18] ^ crc_acc[19] ^ crc_acc[21]
                             ^ crc_acc[22] ^ crc_acc[24] ^ crc_acc[26] ^ crc_acc[27]
                             ^ crc_acc[30] ^ crc_acc[31] ^ crc_shift[0];
                crc_acc[13] <= crc_acc[12] ^ crc_acc[13] ^ crc_acc[14] ^ crc_acc[15]
                             ^ crc_acc[18] ^ crc_acc[19] ^ crc_acc[21] ^ crc_acc[22]
                             ^ crc_acc[24] ^ crc_acc[26] ^ crc_acc[27] ^ crc_acc[30]
                             ^ crc_acc[31] ^ crc_shift[0];
                crc_acc[14] <= crc_acc[13] ^ crc_acc[14] ^ crc_acc[15] ^ crc_acc[18]
                             ^ crc_acc[19] ^ crc_acc[21] ^ crc_acc[22] ^ crc_acc[24]
                             ^ crc_acc[26] ^ crc_acc[27] ^ crc_acc[30] ^ crc_acc[31]
                             ^ crc_shift[0];
                crc_acc[15] <= crc_acc[14] ^ crc_acc[15] ^ crc_acc[18] ^ crc_acc[19]
                             ^ crc_acc[21] ^ crc_acc[22] ^ crc_acc[24] ^ crc_acc[26]
                             ^ crc_acc[27] ^ crc_acc[30] ^ crc_acc[31] ^ crc_shift[0];
                crc_acc[16] <= crc_acc[15] ^ crc_acc[18] ^ crc_acc[19] ^ crc_acc[21]
                             ^ crc_acc[22] ^ crc_acc[24] ^ crc_acc[26] ^ crc_acc[27]
                             ^ crc_acc[30] ^ crc_acc[31] ^ crc_shift[0];
                crc_acc[17] <= crc_acc[16] ^ crc_acc[19] ^ crc_acc[20] ^ crc_acc[22]
                             ^ crc_acc[23] ^ crc_acc[25] ^ crc_acc[27] ^ crc_acc[28]
                             ^ crc_acc[31] ^ crc_shift[0];
                crc_acc[18] <= crc_acc[17] ^ crc_acc[19] ^ crc_acc[20] ^ crc_acc[22]
                             ^ crc_acc[23] ^ crc_acc[25] ^ crc_acc[27] ^ crc_acc[28]
                             ^ crc_acc[29] ^ crc_acc[31] ^ crc_shift[0];
                crc_acc[19] <= crc_acc[18] ^ crc_acc[19] ^ crc_acc[20] ^ crc_acc[22]
                             ^ crc_acc[23] ^ crc_acc[25] ^ crc_acc[27] ^ crc_acc[28]
                             ^ crc_acc[29] ^ crc_acc[31] ^ crc_shift[0];
                crc_acc[20] <= crc_acc[19] ^ crc_acc[20] ^ crc_acc[22] ^ crc_acc[23]
                             ^ crc_acc[25] ^ crc_acc[27] ^ crc_acc[28] ^ crc_acc[29]
                             ^ crc_acc[31] ^ crc_shift[0];
                crc_acc[21] <= crc_acc[20] ^ crc_acc[22] ^ crc_acc[23] ^ crc_acc[25]
                             ^ crc_acc[27] ^ crc_acc[28] ^ crc_acc[29] ^ crc_acc[31]
                             ^ crc_shift[0];
                crc_acc[22] <= crc_acc[21] ^ crc_acc[22];
                crc_acc[23] <= crc_acc[22] ^ crc_acc[23] ^ crc_acc[25] ^ crc_acc[26]
                             ^ crc_acc[29] ^ crc_acc[30] ^ crc_shift[0];
                crc_acc[24] <= crc_acc[23] ^ crc_acc[24] ^ crc_acc[26] ^ crc_acc[27]
                             ^ crc_acc[28] ^ crc_acc[30] ^ crc_acc[31] ^ crc_shift[0];
                crc_acc[25] <= crc_acc[24] ^ crc_acc[26] ^ crc_acc[27] ^ crc_acc[28]
                             ^ crc_acc[30] ^ crc_acc[31] ^ crc_shift[0];
                crc_acc[26] <= crc_acc[25] ^ crc_acc[26] ^ crc_acc[27] ^ crc_acc[28]
                             ^ crc_acc[30] ^ crc_acc[31] ^ crc_shift[0];
                crc_acc[27] <= crc_acc[26] ^ crc_acc[27] ^ crc_acc[28] ^ crc_acc[30]
                             ^ crc_acc[31] ^ crc_shift[0];
                crc_acc[28] <= crc_acc[27] ^ crc_acc[28] ^ crc_acc[29] ^ crc_acc[31]
                             ^ crc_shift[0];
                crc_acc[29] <= crc_acc[28] ^ crc_acc[29] ^ crc_acc[30] ^ crc_acc[31]
                             ^ crc_shift[0];
                crc_acc[30] <= crc_acc[29] ^ crc_acc[30] ^ crc_acc[31] ^ crc_shift[0];
                crc_acc[31] <= crc_acc[30] ^ crc_acc[31] ^ crc_shift[0];
                crc_shift <= {crc_shift[6:0], 1'b0};
                crc_bit_i  <= crc_bit_i + 3'd1;

                if (crc_bit_i == 3'd7) begin
                    if (crc_bytes_n == 5'd1) begin
                        // Final bit of last byte: compute final CRC
                        crc_last <= 1'b1;
                        crc_bytes_n <= 5'd0;
                        // Reflect and XOR 0xFFFFFFFF
                        crc_result[0]  <= crc_acc[31];
                        crc_result[1]  <= crc_acc[30];
                        crc_result[2]  <= crc_acc[29];
                        crc_result[3]  <= crc_acc[28];
                        crc_result[4]  <= crc_acc[27];
                        crc_result[5]  <= crc_acc[26];
                        crc_result[6]  <= crc_acc[25];
                        crc_result[7]  <= crc_acc[24];
                        crc_result[8]  <= crc_acc[23];
                        crc_result[9]  <= crc_acc[22];
                        crc_result[10] <= crc_acc[21];
                        crc_result[11] <= crc_acc[20];
                        crc_result[12] <= crc_acc[19];
                        crc_result[13] <= crc_acc[18];
                        crc_result[14] <= crc_acc[17];
                        crc_result[15] <= crc_acc[16];
                        crc_result[16] <= crc_acc[15];
                        crc_result[17] <= crc_acc[14];
                        crc_result[18] <= crc_acc[13];
                        crc_result[19] <= crc_acc[12];
                        crc_result[20] <= crc_acc[11];
                        crc_result[21] <= crc_acc[10];
                        crc_result[22] <= crc_acc[9];
                        crc_result[23] <= crc_acc[8];
                        crc_result[24] <= crc_acc[7];
                        crc_result[25] <= crc_acc[6];
                        crc_result[26] <= crc_acc[5];
                        crc_result[27] <= crc_acc[4];
                        crc_result[28] <= crc_acc[3];
                        crc_result[29] <= crc_acc[2];
                        crc_result[30] <= crc_acc[1];
                        crc_result[31] <= crc_acc[0];
                        crc_result <= crc_result ^ 32'hFFFFFFFF;
                        crc_done   <= 1'b1;
                    end
                end
            end
        end
    end

    // =========================================================================
    // Read buffer: 5 × 32-bit registers holding 20 received bytes
    // rx_buf[0] = bytes 0..3, rx_buf[1] = bytes 4..7, ..., rx_buf[4] = bytes 16..19
    // =========================================================================
    reg [31:0] rx_buf [0:4];
    reg [2:0]  rx_word_idx;   // 0..4 for the 5 words
    reg [1:0]  rx_byte_in_word; // 0..3 byte position within word
    reg [4:0]  rx_total;      // 0..19 total byte counter

    wire [31:0] rx_128 = {rx_buf[3][31:0]};
    wire [31:0] rx_96  = {rx_buf[2][31:0]};
    wire [31:0] rx_64  = {rx_buf[1][31:0]};
    wire [31:0] rx_32  = {rx_buf[0][31:0]};
    wire [31:0] rx_crc = {rx_buf[4][31:0]};

    // Assembled 128-bit load value
    wire [127:0] rx_assembled = {rx_buf[3], rx_buf[2], rx_buf[1], rx_buf[0]};

    // =========================================================================
    // Save data registers
    // =========================================================================
    reg [127:0] save_data_r;
    reg [31:0]  save_crc_r;

    // =========================================================================
    // Active slot tracker
    // =========================================================================
    reg save_busy_r, save_done_r;
    reg active_slot;  // 0=A, 1=B
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) active_slot <= 1'b0;
        else if (save_done_r) active_slot <= ~active_slot;
    end

    wire [23:0] write_addr = active_slot ? SLOT_B_ADDR : SLOT_A_ADDR;

    // =========================================================================
    // Request edge detection
    // =========================================================================
    reg save_req_d1, load_req_d1;
    wire save_req_pulse = save_req && !save_req_d1;
    wire load_req_pulse = load_req && !load_req_d1;

    // =========================================================================
    // Top-level operation FSM
    // =========================================================================
    // Each state sends ONE SPI command and waits for it to complete.
    // Bytes sent by FSM: command (always byte 0), then address bytes,
    // then payload bytes (for program), then FSM receives bytes (for read).
    // The CRC engine runs in parallel with programming.
    // =========================================================================
    localparam [3:0] OP_IDLE   = 4'd0;
    localparam [3:0] OP_CRCI   = 4'd1;  // CRC init
    localparam [3:0] OP_CRCD   = 4'd2;  // CRC feed data bytes
    localparam [3:0] OP_CRCW   = 4'd3;  // CRC wait result -> save_crc_r
    localparam [3:0] OP_WWEN   = 4'd4;  // WREN before erase
    localparam [3:0] OP_ERASE  = 4'd5;  // Sector erase command
    localparam [3:0] OP_EBUSY  = 4'd6;  // Poll erase done
    localparam [3:0] OP_PWEN   = 4'd7;  // WREN before program
    localparam [3:0] OP_PCMD   = 4'd8;  // Page program command (send all 24 bytes)
    localparam [3:0] OP_WBUSY  = 4'd9;  // Poll program done
    localparam [3:0] OP_RDA    = 4'd10; // Read slot A (20 bytes)
    localparam [3:0] OP_CRCA   = 4'd11; // CRC-check slot A
    localparam [3:0] OP_RDB    = 4'd12; // Read slot B
    localparam [3:0] OP_CRCB   = 4'd13; // CRC-check slot B
    localparam [3:0] OP_DONE   = 4'd14; // Deliver result

    reg [3:0] op_st;

    // Output flags
    reg load_valid_r, load_fail_r;
    reg [127:0] load_data_out;
    assign save_busy  = save_busy_r;
    assign save_done  = save_done_r;
    assign load_valid = load_valid_r;
    assign load_fail  = load_fail_r;
    assign load_data  = load_data_out;

    // SPI transaction descriptor (set before pulsing tx_go)
    reg [7:0]  tx_cmd;
    reg [23:0] tx_addr;
    reg [5:0]  tx_len_r;    // total bytes to send
    reg [4:0]  tx_payload_idx;  // index into payload (0..23 for program)
    reg        send_addr;
    reg [4:0]  rx_len;      // how many bytes to receive (for READ)

    // CRC context
    reg [4:0] crc_data_idx;  // index of next byte to feed to CRC

    // Status polling
    reg [15:0] poll_cnt;

    // CRC result holding
    reg [31:0] crc_check_result;

    // CRC check context for reads
    reg [4:0] crc_rx_idx;
    reg        crc_rx_running;

    // Load context
    reg read_slot_a;

    // =========================================================================
    // Byte selection for programming payload
    // Returns byte N of the 20-byte slot (16 data + 4 CRC)
    // =========================================================================
    function [7:0] pay_byte;
        input [4:0] i;
        input [127:0] d;
        input [31:0]  c;
        begin
            case (i)
                5'd0:  pay_byte = d[7:0];
                5'd1:  pay_byte = d[15:8];
                5'd2:  pay_byte = d[23:16];
                5'd3:  pay_byte = d[31:24];
                5'd4:  pay_byte = d[39:32];
                5'd5:  pay_byte = d[47:40];
                5'd6:  pay_byte = d[55:48];
                5'd7:  pay_byte = d[63:56];
                5'd8:  pay_byte = d[71:64];
                5'd9:  pay_byte = d[79:72];
                5'd10: pay_byte = d[87:80];
                5'd11: pay_byte = d[95:88];
                5'd12: pay_byte = d[103:96];
                5'd13: pay_byte = d[111:104];
                5'd14: pay_byte = d[119:112];
                5'd15: pay_byte = d[127:120];
                5'd16: pay_byte = c[31:24];
                5'd17: pay_byte = c[23:16];
                5'd18: pay_byte = c[15:8];
                5'd19: pay_byte = c[7:0];
                default: pay_byte = 8'h00;
            endcase
        end
    endfunction

    // =========================================================================
    // Main FSM
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            op_st        <= OP_IDLE;
            save_busy_r  <= 1'b0;
            save_done_r  <= 1'b0;
            load_valid_r <= 1'b0;
            load_fail_r  <= 1'b0;
            load_data_out <= 128'h0;
            save_data_r  <= 128'h0;
            save_crc_r   <= 32'h0;
            crc_init     <= 1'b0;
            crc_feed     <= 1'b0;
            crc_byte_i   <= 8'h00;
            crc_data_idx <= 5'd0;
            tx_cmd       <= 8'h00;
            tx_addr      <= 24'h0;
            tx_len_r     <= 6'd0;
            tx_payload_idx <= 5'd0;
            send_addr    <= 1'b0;
            rx_len       <= 5'd0;
            rx_word_idx  <= 3'd0;
            rx_byte_in_word <= 2'd0;
            rx_total     <= 5'd0;
            poll_cnt     <= 16'h0;
            tx_go        <= 1'b0;
            crc_rx_running <= 1'b0;
            crc_rx_idx   <= 5'd0;
            crc_check_result <= 32'h0;
            read_slot_a  <= 1'b1;
            save_req_d1  <= 1'b0;
            load_req_d1  <= 1'b0;
        end else begin
            save_req_d1  <= save_req;
            load_req_d1  <= load_req;
            save_done_r  <= 1'b0;
            load_valid_r <= 1'b0;
            load_fail_r  <= 1'b0;
            tx_go        <= 1'b0;
            crc_feed     <= 1'b0;
            crc_init     <= 1'b0;

            case (op_st)
                // -----------------------------------------------------------------
                OP_IDLE: begin
                    crc_init <= 1'b0;
                    if (save_req_pulse) begin
                        save_data_r  <= save_data;
                        save_busy_r  <= 1'b1;
                        crc_init     <= 1'b1;
                        crc_data_idx <= 5'd0;
                        op_st        <= OP_CRCI;
                    end else if (load_req_pulse) begin
                        read_slot_a <= 1'b1;
                        rx_total    <= 5'd0;
                        rx_word_idx <= 3'd0;
                        rx_byte_in_word <= 2'd0;
                        op_st       <= OP_RDA;
                    end
                end

                // -----------------------------------------------------------------
                // Compute CRC of save_data (16 bytes)
                // -----------------------------------------------------------------
                OP_CRCI: begin
                    // Initialize CRC; FSM feeds bytes in OP_CRCD
                    op_st <= OP_CRCD;
                end

                OP_CRCD: begin
                    // Feed one byte per cycle
                    if (!crc_active) begin
                        crc_byte_i   <= save_data_r[7:0];
                        crc_data_idx <= 5'd1;
                        crc_feed     <= 1'b1;
                    end else if (!crc_active || (crc_bytes_n == 5'd0)) begin
                        // CRC engine is idle: feed next byte
                        if (crc_data_idx < 5'd16) begin
                            crc_byte_i   <= save_data_r[crc_data_idx * 8 +: 8];
                            crc_data_idx <= crc_data_idx + 5'd1;
                            crc_feed     <= 1'b1;
                        end
                    end
                    if (crc_done) begin
                        save_crc_r <= crc_result;
                        op_st      <= OP_WWEN;
                    end
                end

                // -----------------------------------------------------------------
                // WREN -> ERASE -> Poll -> WREN -> PROGRAM -> Poll
                // -----------------------------------------------------------------
                OP_WWEN: begin
                    if (!spi_busy) begin
                        tx_cmd   <= CMD_WREN;
                        tx_len_r <= 6'd1;
                        tx_go    <= 1'b1;
                        op_st    <= OP_ERASE;
                    end
                end

                OP_ERASE: begin
                    if (!spi_busy) begin
                        tx_cmd   <= CMD_SECTOR_ERASE;
                        tx_addr  <= write_addr;
                        tx_len_r <= 6'd4;   // 1 cmd + 3 addr
                        send_addr <= 1'b1;
                        tx_go    <= 1'b1;
                        poll_cnt <= 16'h0;
                        op_st    <= OP_EBUSY;
                    end
                end

                OP_EBUSY: begin
                    if (!spi_busy) begin
                        tx_cmd   <= CMD_RDSR;
                        tx_len_r <= 6'd1;
                        tx_go    <= 1'b1;
                    end
                    if (rx_done) begin
                        if (rx_byte_r[0] == 1'b0) begin
                            op_st    <= OP_PWEN;
                        end else begin
                            poll_cnt <= poll_cnt + 16'h1;
                            if (poll_cnt >= ERASE_POLL_MAX) op_st <= OP_PWEN;
                        end
                    end
                end

                OP_PWEN: begin
                    if (!spi_busy) begin
                        tx_cmd   <= CMD_WREN;
                        tx_len_r <= 6'd1;
                        tx_go    <= 1'b1;
                        op_st    <= OP_PCMD;
                    end
                end

                OP_PCMD: begin
                    if (!spi_busy) begin
                        tx_cmd        <= CMD_PAGE_PROGRAM;
                        tx_addr       <= write_addr;
                        tx_len_r      <= 6'd4 + PAYLOAD_BYTES;  // 1+3+20
                        send_addr     <= 1'b1;
                        tx_payload_idx <= 5'd0;
                        tx_go         <= 1'b1;
                        poll_cnt      <= 16'h0;
                        op_st         <= OP_WBUSY;
                    end
                end

                OP_WBUSY: begin
                    if (!spi_busy) begin
                        tx_cmd   <= CMD_RDSR;
                        tx_len_r <= 6'd1;
                        tx_go    <= 1'b1;
                    end
                    if (rx_done) begin
                        if (rx_byte_r[0] == 1'b0) begin
                            save_busy_r  <= 1'b0;
                            save_done_r  <= 1'b1;
                            op_st        <= OP_IDLE;
                        end else begin
                            poll_cnt <= poll_cnt + 16'h1;
                            if (poll_cnt >= PGM_POLL_MAX) begin
                                save_busy_r  <= 1'b0;
                                save_done_r  <= 1'b1;
                                op_st        <= OP_IDLE;
                            end
                        end
                    end
                end

                // -----------------------------------------------------------------
                // Load: Read slot A
                // -----------------------------------------------------------------
                OP_RDA: begin
                    if (!spi_busy) begin
                        tx_cmd   <= CMD_READ;
                        tx_addr  <= SLOT_A_ADDR;
                        tx_len_r <= 6'd4 + PAYLOAD_BYTES;  // 1+3+20
                        send_addr <= 1'b1;
                        rx_len    <= PAYLOAD_BYTES;
                        rx_total  <= 5'd0;
                        rx_word_idx <= 3'd0;
                        rx_byte_in_word <= 2'd0;
                        crc_rx_running <= 1'b1;
                        crc_rx_idx   <= 5'd0;
                        crc_init     <= 1'b1;
                        crc_byte_i   <= 8'h00;
                        tx_go    <= 1'b1;
                        op_st    <= OP_CRCA;
                    end
                end

                // -----------------------------------------------------------------
                // CRC-check slot A: receive bytes, feed CRC, decide
                // -----------------------------------------------------------------
                OP_CRCA: begin
                    // While receiving bytes, feed them to CRC engine
                    if (rx_done && crc_rx_running) begin
                        rx_buf[rx_word_idx][rx_byte_in_word*8 +: 8] <= rx_byte_r;
                        rx_byte_in_word <= rx_byte_in_word + 2'd1;
                        if (rx_byte_in_word == 2'd3) begin
                            rx_byte_in_word <= 2'd0;
                            rx_word_idx <= rx_word_idx + 3'd1;
                        end
                        rx_total <= rx_total + 5'd1;

                        // Feed to CRC if within first 16 data bytes
                        if (rx_total < 5'd16) begin
                            crc_feed   <= 1'b1;
                            crc_byte_i <= rx_byte_r;
                        end else if (rx_total == 5'd16) begin
                            // Last data byte fed; CRC will complete in 8 more cycles
                            crc_rx_running <= 1'b0;
                        end
                    end
                    // Wait for all bytes received + CRC done
                    if (rx_done && (rx_total >= (PAYLOAD_BYTES - 5'd1))) begin
                        // Full slot received; wait for CRC
                        if (crc_done) begin
                            crc_check_result <= crc_result;
                            if (crc_result == rx_crc) begin
                                // Slot A valid
                                load_data_out <= rx_assembled;
                                load_valid_r  <= 1'b1;
                                op_st <= OP_IDLE;
                            end else begin
                                // Slot A bad — read slot B
                                read_slot_a <= 1'b0;
                                rx_total    <= 5'd0;
                                rx_word_idx <= 3'd0;
                                rx_byte_in_word <= 2'd0;
                                crc_rx_running <= 1'b1;
                                crc_rx_idx   <= 5'd0;
                                crc_init     <= 1'b1;
                                op_st <= OP_RDB;
                            end
                        end
                    end
                end

                // -----------------------------------------------------------------
                // Load: Read slot B
                // -----------------------------------------------------------------
                OP_RDB: begin
                    if (!spi_busy) begin
                        tx_cmd   <= CMD_READ;
                        tx_addr  <= SLOT_B_ADDR;
                        tx_len_r <= 6'd4 + PAYLOAD_BYTES;
                        send_addr <= 1'b1;
                        rx_len    <= PAYLOAD_BYTES;
                        rx_total  <= 5'd0;
                        rx_word_idx <= 3'd0;
                        rx_byte_in_word <= 2'd0;
                        crc_rx_running <= 1'b1;
                        crc_rx_idx   <= 5'd0;
                        crc_init     <= 1'b1;
                        tx_go    <= 1'b1;
                        op_st    <= OP_CRCB;
                    end
                end

                // -----------------------------------------------------------------
                // CRC-check slot B
                // -----------------------------------------------------------------
                OP_CRCB: begin
                    if (rx_done && crc_rx_running) begin
                        rx_buf[rx_word_idx][rx_byte_in_word*8 +: 8] <= rx_byte_r;
                        rx_byte_in_word <= rx_byte_in_word + 2'd1;
                        if (rx_byte_in_word == 2'd3) begin
                            rx_byte_in_word <= 2'd0;
                            rx_word_idx <= rx_word_idx + 3'd1;
                        end
                        rx_total <= rx_total + 5'd1;

                        if (rx_total < 5'd16) begin
                            crc_feed   <= 1'b1;
                            crc_byte_i <= rx_byte_r;
                        end else if (rx_total == 5'd16) begin
                            crc_rx_running <= 1'b0;
                        end
                    end
                    if (rx_done && (rx_total >= (PAYLOAD_BYTES - 5'd1))) begin
                        if (crc_done) begin
                            crc_check_result <= crc_result;
                            if (crc_result == rx_crc) begin
                                load_data_out <= rx_assembled;
                                load_valid_r  <= 1'b1;
                            end else begin
                                load_fail_r <= 1'b1;
                            end
                            op_st <= OP_IDLE;
                        end
                    end
                end

                // -----------------------------------------------------------------
                default: op_st <= OP_IDLE;
            endcase
        end
    end

    // =========================================================================
    // SPI TX byte selector
    // The FSM sets: tx_cmd, tx_addr, tx_len_r, send_addr, tx_payload_idx.
    // This block selects which byte to send based on the current position.
    // =========================================================================
    reg [5:0] tx_sent_cnt;  // how many bytes of the current transaction have been sent

    // Track how many bytes we've sent in the current transaction
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_sent_cnt <= 6'd0;
        end else begin
            if (se_st == SE_IDLE && tx_go && !tx_go_d1) begin
                tx_sent_cnt <= 6'd0;
            end else if (rx_done) begin
                tx_sent_cnt <= tx_sent_cnt + 6'd1;
            end
        end
    end

    // Select byte to send
    always @(*) begin
        // Byte 0 is always the command
        if (tx_sent_cnt == 6'd0) begin
            tx_byte_sel = tx_cmd;
        end else if (send_addr && tx_sent_cnt <= 6'd3) begin
            // Bytes 1-3 are address (if send_addr is set)
            case (tx_sent_cnt)
                6'd1: tx_byte_sel = tx_addr[23:16];
                6'd2: tx_byte_sel = tx_addr[15:8];
                6'd3: tx_byte_sel = tx_addr[7:0];
                default: tx_byte_sel = 8'h00;
            endcase
        end else begin
            // Payload bytes (programming)
            tx_byte_sel = pay_byte(tx_sent_cnt - 6'd4, save_data_r, save_crc_r);
        end
    end

    // Clear send_addr after erase command completes
    reg send_addr_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) send_addr_r <= 1'b0;
        else begin
            if (tx_go) send_addr_r <= send_addr;
        end
    end

endmodule

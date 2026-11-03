`timescale 1ns / 1ps
// Burst-locked arbiter; canonical valid/ready directions from interface_contract.yaml.
module sdram_arbiter #(
    parameter STARVE_MAX = 64  // cycles of continuous denial before wr promotion
) (
    input  wire clk,
    input  wire rst_n,

    // ---- Master port A: audio (highest priority) ----
    input  wire        aud_req_valid,
    output wire        aud_req_ready,
    input  wire [21:0] aud_req_addr,
    input  wire        aud_req_we,
    input  wire [8:0]  aud_req_len,
    input  wire        aud_wr_valid,
    output wire        aud_wr_ready,
    input  wire [31:0] aud_wr_data,
    output wire        aud_rd_valid,
    input  wire        aud_rd_ready,
    output wire [31:0] aud_rd_data,

    // ---- Master port D: display (second priority) ----
    input  wire        disp_req_valid,
    input  wire        disp_urgent,
    output wire        disp_req_ready,
    input  wire [21:0] disp_req_addr,
    input  wire        disp_req_we,
    input  wire [8:0]  disp_req_len,
    input  wire        disp_wr_valid,
    output wire        disp_wr_ready,
    input  wire [31:0] disp_wr_data,
    output wire        disp_rd_valid,
    input  wire        disp_rd_ready,
    output wire [31:0] disp_rd_data,

    // ---- Master port T: transition (third priority) ----
    input  wire        tr_req_valid,
    output wire        tr_req_ready,
    input  wire [21:0] tr_req_addr,
    input  wire        tr_req_we,
    input  wire [8:0]  tr_req_len,
    input  wire        tr_wr_valid,
    output wire        tr_wr_ready,
    input  wire [31:0] tr_wr_data,
    output wire        tr_rd_valid,
    input  wire        tr_rd_ready,
    output wire [31:0] tr_rd_data,

    // ---- Master port W: asset_loader write (lowest priority, starvation protected) ----
    input  wire        wr_req_valid,
    output wire        wr_req_ready,
    input  wire [21:0] wr_req_addr,
    input  wire        wr_req_we,
    input  wire [8:0]  wr_req_len,
    input  wire        wr_wr_valid,
    output wire        wr_wr_ready,
    input  wire [31:0] wr_wr_data,
    output wire        wr_rd_valid,
    input  wire        wr_rd_ready,
    output wire [31:0] wr_rd_data,

    // ---- Slave port M: to SDRAM controller ----
    output wire        mem_req_valid,
    input  wire        mem_req_ready,
    output wire [21:0] mem_req_addr,
    output wire        mem_req_we,
    output wire [8:0]  mem_req_len,
    output wire        mem_wr_valid,
    input  wire        mem_wr_ready,
    output wire [31:0] mem_wr_data,
    input  wire        mem_rd_valid,
    output wire        mem_rd_ready,
    input  wire [31:0] mem_rd_data
);


    localparam IDLE=0, REQUEST=1, DATA=2;
    reg [1:0] state, owner, winner;
    reg [21:0] addr;
    reg we;
    reg [8:0] length, remaining;
    reg [31:0] denied;
    reg have_request;
    always @* begin
        winner=0; have_request=1;
        if (aud_req_valid) winner=0;
        // Reserve the turnaround slot too: the reader needs an IDLE cycle
        // before it can raise its next request. Otherwise a pending writer wins
        // that one-cycle gap after every display burst despite a low FIFO.
        else if (disp_urgent) begin
            if(disp_req_valid)winner=1;
            else have_request=0;
        end
        else if (wr_req_valid && denied >= STARVE_MAX) winner=3;
        else if (disp_req_valid) winner=1;
        else if (tr_req_valid) winner=2;
        else if (wr_req_valid) winner=3;
        else have_request=0;
    end
    assign mem_req_valid = state==REQUEST;
    assign mem_req_addr = addr;
    assign mem_req_we = we;
    assign mem_req_len = length;
    assign mem_wr_valid = state==DATA && we &&
        (owner==0 ? aud_wr_valid : owner==1 ? disp_wr_valid : owner==2 ? tr_wr_valid : wr_wr_valid);
    assign mem_wr_data = owner==0 ? aud_wr_data : owner==1 ? disp_wr_data : owner==2 ? tr_wr_data : wr_wr_data;
    assign mem_rd_ready = state==DATA && !we &&
        (owner==0 ? aud_rd_ready : owner==1 ? disp_rd_ready : owner==2 ? tr_rd_ready : wr_rd_ready);
    wire beat = we ? mem_wr_valid && mem_wr_ready : mem_rd_valid && mem_rd_ready;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; owner<=0; addr<=0; we<=0; length<=0; remaining<=0; denied<=0;
        end else begin
            if (!wr_req_valid || (state==REQUEST && mem_req_ready && owner==3)) denied<=0;
            else if (denied < STARVE_MAX) denied<=denied+1'b1;
            case (state)
                IDLE: if (have_request) begin
                    owner<=winner;
                    case (winner)
                        0: begin addr<=aud_req_addr; we<=aud_req_we; length<=aud_req_len; end
                        1: begin addr<=disp_req_addr; we<=disp_req_we; length<=disp_req_len; end
                        2: begin addr<=tr_req_addr; we<=tr_req_we; length<=tr_req_len; end
                        3: begin addr<=wr_req_addr; we<=wr_req_we; length<=wr_req_len; end
                    endcase
                    state<=REQUEST;
                end
                REQUEST: if (mem_req_ready) begin remaining<=length; state<=DATA; end
                DATA: if (beat) begin
                    remaining<=remaining-1'b1;
                    if (remaining==1) state<=IDLE;
                end
                default: state<=IDLE;
            endcase
        end
    end
    assign aud_req_ready = state==REQUEST && owner==0 && mem_req_ready;
    assign aud_wr_ready = state==DATA && owner==0 && we && mem_wr_ready;
    assign aud_rd_valid = state==DATA && owner==0 && !we && mem_rd_valid;
    assign aud_rd_data = mem_rd_data;
    assign disp_req_ready = state==REQUEST && owner==1 && mem_req_ready;
    assign disp_wr_ready = state==DATA && owner==1 && we && mem_wr_ready;
    assign disp_rd_valid = state==DATA && owner==1 && !we && mem_rd_valid;
    assign disp_rd_data = mem_rd_data;
    assign tr_req_ready = state==REQUEST && owner==2 && mem_req_ready;
    assign tr_wr_ready = state==DATA && owner==2 && we && mem_wr_ready;
    assign tr_rd_valid = state==DATA && owner==2 && !we && mem_rd_valid;
    assign tr_rd_data = mem_rd_data;
    assign wr_req_ready = state==REQUEST && owner==3 && mem_req_ready;
    assign wr_wr_ready = state==DATA && owner==3 && we && mem_wr_ready;
    assign wr_rd_valid = state==DATA && owner==3 && !we && mem_rd_valid;
    assign wr_rd_data = mem_rd_data;
endmodule

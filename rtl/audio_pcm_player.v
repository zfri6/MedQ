`timescale 1ns / 1ps
// 16 kHz mono PCM, signed linear 3x interpolation and repeated playback mailbox.
module audio_pcm_player #(parameter CONTROLLED=0) (
    // Pixel clock domain (audio output)
    input  wire        clk_pix,
    input  wire        rst_n_pix,
    // SDRAM clock domain
    input  wire        clk_mem,
    input  wire        rst_n_mem,
    // 48 kHz sample gate
    input  wire        stb,
    input  wire        run_enable,
    input  wire        abort_play,
    // Playback request (clk_pix)
    input  wire        play_req,
    input  wire [21:0] play_base,
    input  wire [21:0] play_samples,
    // Status (clk_pix)
    output reg         play_busy,
    output reg         play_done,
    output reg  [15:0] sample,
    output reg         underrun,
    // SDRAM master port (clk_mem) -- all handshaking in clk_mem
    output wire        aud_req_valid,
    input  wire        aud_req_ready,
    output wire [21:0] aud_req_addr,
    output wire        aud_req_we,
    output wire [8:0]  aud_req_len,
    output wire        aud_wr_valid,
    input  wire        aud_wr_ready,
    output wire [31:0] aud_wr_data,
    input  wire        aud_rd_valid,
    output wire        aud_rd_ready,
    input  wire [31:0] aud_rd_data
);


    wire run_i=CONTROLLED ? run_enable : 1'b1;
    wire abort_i=CONTROLLED ? abort_play : 1'b0;
    reg request_toggle,cancel_toggle,cancel_ack;
    (* ASYNC_REG="TRUE" *) reg [1:0] cancel_sync,ack_sync;
    reg [21:0] base_hold,count_hold;
    reg [1:0] req_sync;
    reg req_seen;
    reg [1:0] mem_state;
    reg [21:0] read_addr,words_left;
    reg [8:0] burst_len,beats_left;
    wire fifo_wready,fifo_rvalid,fifo_pop;
    wire [31:0] fifo_data;
    wire [9:0] wlevel,rlevel;
    medq_async_fifo #(.W(32),.AW(9)) u_fifo(
        .wclk(clk_mem),.wrst_n(rst_n_mem),.wvalid(aud_rd_valid && mem_state==2),.wdata(aud_rd_data),.wready(fifo_wready),.wlevel(wlevel),
        .rclk(clk_pix),.rrst_n(rst_n_pix),.rready(fifo_pop),.rvalid(fifo_rvalid),.rdata(fifo_data),.rlevel(rlevel));
    assign aud_req_valid=mem_state==1;
    assign aud_req_addr=read_addr;
    assign aud_req_len=burst_len;
    assign aud_req_we=0;
    assign aud_wr_valid=0;
    assign aud_wr_data=0;
    assign aud_rd_ready=mem_state==2 && fifo_wready;
    always @(posedge clk_mem or negedge rst_n_mem) begin
        if (!rst_n_mem) begin
            req_sync<=0; req_seen<=0; mem_state<=0; read_addr<=0; words_left<=0; burst_len<=0; beats_left<=0;
            cancel_sync<=0;cancel_ack<=0;
        end else begin
            req_sync<={req_sync[0],request_toggle};
            cancel_sync<={cancel_sync[0],cancel_toggle};
            if (req_sync[1]!=req_seen) begin
                req_seen<=req_sync[1]; read_addr<=base_hold;
                words_left<=({1'b0,count_hold}+1)>>1; mem_state<=0;
            end else if(cancel_sync[1]!=cancel_ack && mem_state==0)begin
                // Only acknowledge after an issued request/burst has completed.
                words_left<=0;cancel_ack<=cancel_sync[1];
            end else case (mem_state)
                0: if (words_left!=0 && wlevel<=448) begin
                    burst_len<=words_left>64 ? 9'd64 : words_left[8:0]; mem_state<=1;
                end
                1: if (aud_req_ready) begin beats_left<=burst_len; mem_state<=2; end
                2: if (aud_rd_valid && aud_rd_ready) begin
                    beats_left<=beats_left-1'b1; words_left<=words_left-1'b1; read_addr<=read_addr+1'b1;
                    if (beats_left==1) mem_state<=0;
                end
                default: mem_state<=0;
            endcase
        end
    end
    localparam IDLE=0, FIRST=1, NEXT=2, RUN=3, ABORT=4;
    reg [2:0] state;
    reg [1:0] phase;
    reg [3:0] empty_age;
    reg play_started;
    reg half_word;
    reg [21:0] fetched,sources_left;
    reg signed [15:0] current_sample,next_sample;
    wire fetching=state==FIRST || state==NEXT;
    wire [15:0] incoming=half_word ? fifo_data[31:16] : fifo_data[15:0];
    assign fifo_pop=fifo_rvalid && ((state==ABORT) || (run_i && fetching && (half_word || fetched+1==count_hold)));
    wire signed [31:0] difference=$signed(next_sample)-$signed(current_sample);
    wire signed [31:0] interpolated=$signed(current_sample)+difference*$signed({1'b0,phase})/32'sd3;
    always @(posedge clk_pix or negedge rst_n_pix) begin
        if (!rst_n_pix) begin
            request_toggle<=0; base_hold<=0; count_hold<=0;
            cancel_toggle<=0;ack_sync<=0;empty_age<=0;
            state<=IDLE; phase<=0; half_word<=0; fetched<=0; sources_left<=0;
            current_sample<=0; next_sample<=0; sample<=0; play_busy<=0; play_done<=0; underrun<=0;play_started<=0;
        end else begin
            play_done<=0;
            ack_sync<={ack_sync[0],cancel_ack};
            if(!run_i)sample<=0;
            if(abort_i && play_busy && state!=ABORT)begin
                cancel_toggle<=~cancel_toggle;state<=ABORT;sample<=0;empty_age<=0;
            end else if(state==ABORT)begin
                sample<=0;
                // Ack and FIFO pointers cross independently. Allow synchronizer
                // and synchronous FWFT latency before declaring the FIFO drained.
                if(ack_sync[1]==cancel_toggle && !fifo_rvalid)begin
                    if(empty_age==7)begin state<=IDLE;play_busy<=0;play_done<=1;end
                    else empty_age<=empty_age+1'b1;
                end else empty_age<=0;
            end else if (run_i && play_req && !play_busy) begin
                sample<=0; underrun<=0; phase<=0; half_word<=0; fetched<=0;play_started<=0;
                base_hold<=play_base; count_hold<=play_samples; sources_left<=play_samples;
                if (play_samples==0) begin play_done<=1; state<=IDLE; end
                else begin request_toggle<=~request_toggle; state<=FIRST; play_busy<=1; end
            end else begin
                if (run_i && fetching && fifo_rvalid) begin
                    fetched<=fetched+1'b1; half_word<=!half_word;
                    if (state==FIRST) begin
                        current_sample<=incoming;
                        if (count_hold==1) begin next_sample<=incoming; state<=RUN;play_started<=1; end
                        else state<=NEXT;
                    end else begin next_sample<=incoming; state<=RUN;play_started<=1; end
                end
                if (run_i && stb && play_busy) begin
                    if (state==RUN) begin
                        sample<=interpolated[15:0];
                        if (phase==2) begin
                            phase<=0;
                            if (sources_left==1) begin play_busy<=0; play_done<=1; state<=IDLE; end
                            else begin
                                current_sample<=next_sample; sources_left<=sources_left-1'b1;
                                if (sources_left>2) state<=NEXT;
                            end
                        end else phase<=phase+1'b1;
                    // Busy includes descriptor CDC/initial prefetch. Output
                    // silence until primed; only a gap after playback started
                    // is a real underrun. Mid-clip starvation remains sticky.
                    end else begin sample<=0;if(play_started)underrun<=1;end
                end
            end
        end
    end
endmodule

`timescale 1ns / 1ps
// MedQ mount/scan/preload pipeline. Every byte/pixel/SDRAM beat has bounded buffering.
module asset_loader #(parameter SD_INIT_DIV=62, SD_DATA_DIV=1, SD_RESPONSE_LIMIT=255, MEDIA_PROFILE=0) (
    input  wire       clk_sys,
    input  wire       rst_n_sys,
    input  wire       clk_mem,
    input  wire       rst_n_mem,
    // Load request (accepted in READY state)
    input  wire       load_req,
    input  wire [4:0] img_sel,
    input  wire [1:0] fb_sel,
    output reg        load_busy,
    output reg        load_done,
    output reg        load_err,
    output reg  [5:0] img_count,
    output reg  [6:0] pcm_count,
    output reg        assets_ok,
    output reg  [2:0] media_valid,
    output reg  [3:0] progress,
    // Audio clip query (any time)
    input  wire [5:0] clip_sel,
    output wire [21:0] clip_base,    // word addr offset from AUDIO_POOL_BASE
    output wire [21:0] clip_samples,  // sample count = bytes/2
    // SPI to TF card
    output wire       sd_spi_sclk,
    output wire       sd_spi_mosi,
    input  wire       sd_spi_miso,
    output wire       sd_spi_cs_n,
    // SDRAM write master (clk_mem)
    output reg        wr_req_valid,
    input  wire       wr_req_ready,
    output reg  [21:0] wr_req_addr,
    output reg        wr_req_we,
    output reg  [8:0] wr_req_len,
    output reg        wr_wr_valid,
    input  wire       wr_wr_ready,
    output reg  [31:0] wr_wr_data,
    input  wire       wr_rd_valid,
    output reg        wr_rd_ready,
    input  wire [31:0] wr_rd_data
);


    localparam MOUNT=0, MOUNT_WAIT=1, SCAN_BMP=2, SCAN_BMP_WAIT=3, SCAN_PCM=4,
               SCAN_PCM_WAIT=5, SELECT_FILE=6, START_FILE=7, LOAD=8, DRAIN=9, READY=10, FAILED=11, META_WAIT=12,SELECT_IMAGE=13;
    reg [3:0] state;
    localparam IMG_SLOTS=MEDIA_PROFILE ? 3 : 32;
    reg [31:0] img_size_r[0:IMG_SLOTS-1],img_clus_r[0:IMG_SLOTS-1];
    reg [2:0] image_present;
    reg preloading_images;
    reg [31:0] aud_size_r[0:63],aud_clus_r[0:63];
    reg [63:0] aud_valid;
    reg [31:0] query_size,load_size,load_cluster;
    reg [21:0] query_base;
    reg [21:0] aud_pool_off_r[0:63];
    reg [6:0] pcm_index;
    reg [4:0] image_index;
    reg image_mode;
    reg [21:0] image_base,pool_pointer,file_base;
    reg [31:0] file_bytes,bytes_left;
    reg [1:0] pcm_byte_index;
    reg [31:0] pcm_word;
    reg pcm_word_valid,pcm_word_last;
    reg [21:0] pcm_addr,pcm_word_addr;
    reg flush;
    integer k;
    wire sd_req,sd_done,sd_error,sd_byte_valid,sd_ready;
    wire [31:0] sd_lba;
    wire [7:0] sd_byte;
    sd_card_ctrl #(.INIT_CLK_DIV(SD_INIT_DIV),.DATA_CLK_DIV(SD_DATA_DIV),.RESPONSE_LIMIT(SD_RESPONSE_LIMIT))
        u_sd_card_ctrl(.clk(clk_sys),.rst_n(rst_n_sys),.rd_req(sd_req),.rd_lba(sd_lba),
        .rd_busy(),.rd_done(sd_done),.rd_err(sd_error),.byte_valid(sd_byte_valid),.byte_data(sd_byte),.byte_idx(),
        .card_ready(sd_ready),.card_sdhc(),.init_fail(),.spi_sclk(sd_spi_sclk),.spi_mosi(sd_spi_mosi),
        .spi_miso(sd_spi_miso),.spi_cs_n(sd_spi_cs_n));
    reg mount_req,scan_req,read_req,bmp_start;
    wire mount_done,mount_err,file_valid,scan_done,read_done,read_err,fr_valid;
    wire [5:0] file_index;
    wire [31:0] file_size,file_cluster;
    wire [7:0] fr_data;
    wire fr_ready;
    wire [31:0] cluster=image_mode ? img_clus_r[image_index] : load_cluster;
    fat32_reader #(.NAMED_PCM(1),.NAMED_BMP(MEDIA_PROFILE)) u_fat32(.clk(clk_sys),.rst_n(rst_n_sys),.mount_req(mount_req),.mount_done(mount_done),.mount_err(mount_err),
        .scan_req(scan_req),.scan_ext(state==SCAN_BMP || state==SCAN_BMP_WAIT ? 24'h424d50 : 24'h50434d),
        .file_valid(file_valid),.file_index(file_index),.file_size(file_size),.file_cluster(file_cluster),.scan_done(scan_done),.file_count(),
        .read_req(read_req),.read_cluster(cluster),.read_len(file_bytes),.read_busy(),.read_done(read_done),.read_err(read_err),
        .out_ready(fr_ready),.out_valid(fr_valid),.out_data(fr_data),.sd_rd_req(sd_req),.sd_rd_lba(sd_lba),
        .sd_rd_done(sd_done),.sd_rd_err(sd_error),.sd_byte_valid(sd_byte_valid),.sd_byte_data(sd_byte));
    wire bp_header,bp_valid,bp_done,bp_error;
    wire [10:0] bp_width,bp_height,bp_x,bp_y;
    wire [23:0] bp_rgb;
    wire [5:0] bp_bpp;
    wire bp_topdown;
    // Header dimensions are stable before pixels start. Decode native size once,
    // rather than putting the BMP width comparator on every scaler handshake.
    reg native_size;
    always @(posedge clk_sys or negedge rst_n_sys) begin
        if(!rst_n_sys) native_size<=0;
        else if(bmp_start) native_size<=0;
        else if(bp_header) native_size<=bp_width==640 && bp_height==480;
    end
    bmp_parser u_bmp(.clk(clk_sys),.rst_n(rst_n_sys),.start(bmp_start),.in_valid(fr_valid && fr_ready && image_mode),.in_data(fr_data),
        .hdr_valid(bp_header),.img_width(bp_width),.img_height(bp_height),.img_bpp(bp_bpp),.img_topdown(bp_topdown),
        .px_valid(bp_valid),.px_rgb(bp_rgb),.px_x(bp_x),.px_y(bp_y),.done(bp_done),.err(bp_error),.err_code());
    // A skid FIFO absorbs the registered FAT/BMP output while input is stalled.
    reg [45:0] pixel_fifo[0:15];
    reg [3:0] pixel_w,pixel_r;
    reg [4:0] pixel_count;
    wire sc_ready,sc_valid,sc_last,sc_out_ready;
    wire [23:0] sc_rgb;
    wire [9:0] sc_x,sc_y;
    wire pixel_pop=pixel_count!=0 && sc_ready;
    always @(posedge clk_sys or negedge rst_n_sys) begin
        if (!rst_n_sys) begin pixel_w<=0; pixel_r<=0; pixel_count<=0; end
        else if (bmp_start) begin pixel_w<=0; pixel_r<=0; pixel_count<=0; end
        else begin
            if (bp_valid) begin pixel_fifo[pixel_w]<={bp_y,bp_x,bp_rgb}; pixel_w<=pixel_w+1'b1; end
            if (pixel_pop) pixel_r<=pixel_r+1'b1;
            case ({bp_valid,pixel_pop})
                2'b10: pixel_count<=pixel_count+1'b1;
                2'b01: pixel_count<=pixel_count-1'b1;
                default: pixel_count<=pixel_count;
            endcase
        end
    end
    generate if(MEDIA_PROFILE)begin: g_native
        assign sc_ready=sc_out_ready;
        assign sc_valid=pixel_count!=0;
        assign sc_rgb=pixel_fifo[pixel_r][23:0];
        assign sc_x=pixel_fifo[pixel_r][33:24];
        assign sc_y=pixel_fifo[pixel_r][44:35];
        assign sc_last=sc_x==639 && sc_y==(bp_topdown ? 479 : 0);
    end else begin: g_legacy_scaler
    bilinear_scaler u_scaler(.clk(clk_sys),.rst_n(rst_n_sys),.bypass(native_size),
        .src_w(bp_width),.src_h(bp_height),.in_valid(pixel_count!=0),.in_ready(sc_ready),
        .in_rgb(pixel_fifo[pixel_r][23:0]),.in_x(pixel_fifo[pixel_r][34:24]),.in_y(pixel_fifo[pixel_r][45:35]),.in_last(1'b0),
        .out_ready(sc_out_ready),.out_valid(sc_valid),.out_rgb(sc_rgb),.out_x(sc_x),.out_y(sc_y),.out_last(sc_last));
    end endgenerate
    wire word_ready,word_valid;
    wire [56:0] word_data;
    wire [10:0] word_wlevel,word_rlevel;
    wire word_push=image_mode ? sc_valid : pcm_word_valid;
    wire [56:0] word_input=image_mode ? {sc_x[9:8],sc_last,(image_base+sc_y*22'd640+sc_x),sc_x[7:0],sc_rgb} :
                                                     {2'd0,pcm_word_last,pcm_word_addr,pcm_word};
    wire word_pop;
    medq_async_fifo #(.W(57),.AW(10)) u_words(
        .wclk(clk_sys),.wrst_n(rst_n_sys),.wvalid(word_push),.wdata(word_input),.wready(word_ready),.wlevel(word_wlevel),
        .rclk(clk_mem),.rrst_n(rst_n_mem),.rready(word_pop),.rvalid(word_valid),.rdata(word_data),.rlevel(word_rlevel));
    assign sc_out_ready=word_ready;
    assign fr_ready=image_mode ? pixel_count<12 : word_wlevel<1000;
    reg [1:0] wm_state;
    reg [8:0] wm_len,wm_left;
    reg [8:0] wm_available,wm_row_limit;
    reg [21:0] wm_addr;
    reg done_toggle,done_target;
    reg [1:0] flush_sync,mode_sync,done_sync;
    wire [9:0] row_left=10'd640-{word_data[56:55],word_data[31:24]};
    wire [10:0] available=word_rlevel>64 ? 11'd64 : word_rlevel;
    wire [10:0] burst_length=mode_sync[1] && row_left<available ? row_left : available;
    always @(posedge clk_mem or negedge rst_n_mem) begin
        if (!rst_n_mem) begin
            wm_state<=0; wm_len<=0; wm_left<=0; wm_addr<=0; done_toggle<=0; flush_sync<=0; mode_sync<=0;
            wm_available<=0;wm_row_limit<=0;
        end else begin
            flush_sync<={flush_sync[0],flush}; mode_sync<={mode_sync[0],image_mode};
            case (wm_state)
                0: if (word_valid && (word_rlevel>=64 || flush_sync[1])) begin
                    // The FIFO head cannot move until DATA. Snapshot a safe
                    // lower bound, then compare it with the row limit next cycle.
                    wm_addr<=word_data[53:32];
                    wm_available<=available[8:0];
                    wm_row_limit<=mode_sync[1] && row_left<64 ? row_left[8:0] : 9'd64;
                    wm_state<=3;
                end
                3: begin
                    wm_len<=wm_row_limit<wm_available ? wm_row_limit : wm_available;
                    wm_left<=wm_row_limit<wm_available ? wm_row_limit : wm_available;
                    wm_state<=1;
                end
                1: if (wr_req_ready) wm_state<=2;
                2: if (wr_wr_valid && wr_wr_ready) begin
                    wm_left<=wm_left-1'b1;
                    if (word_data[54]) done_toggle<=~done_toggle;
                    if (wm_left==1) wm_state<=0;
                end
                default: wm_state<=0;
            endcase
        end
    end
    always @* begin
        wr_req_valid=wm_state==1; wr_req_addr=wm_addr; wr_req_we=1; wr_req_len=wm_len;
        wr_wr_valid=wm_state==2 && word_valid; wr_wr_data=mode_sync[1] ? {8'd0,word_data[23:0]} : word_data[31:0]; wr_rd_ready=0;
    end
    assign word_pop=wm_state==2 && wr_wr_ready;
    // Metadata RAM has one registered read cycle. Only initialized, loaded
    // entries are exposed; payload arrays deliberately have no reset.
    always @(posedge clk_sys) begin
        query_size<=aud_size_r[clip_sel];query_base<=aud_pool_off_r[clip_sel];
        load_size<=aud_size_r[pcm_index[5:0]];load_cluster<=aud_clus_r[pcm_index[5:0]];
        if(file_valid && state==SCAN_PCM_WAIT)begin
            aud_size_r[file_index]<=file_size;aud_clus_r[file_index]<=file_cluster;
        end
        if(state==SELECT_FILE && pcm_index<64 && aud_valid[pcm_index[5:0]])
            aud_pool_off_r[pcm_index[5:0]]<=pool_pointer;
    end
    assign clip_base=assets_ok && aud_valid[clip_sel] ? query_base : 22'd0;
    assign clip_samples=assets_ok && aud_valid[clip_sel] ? query_size>>1 : 22'd0;
    always @(posedge clk_sys or negedge rst_n_sys) begin
        if (!rst_n_sys) begin
            state<=MOUNT; mount_req<=0; scan_req<=0; read_req<=0; bmp_start<=0;
            img_count<=0; pcm_count<=0; assets_ok<=0; media_valid<=0; image_present<=0; preloading_images<=0; progress<=0;
            pcm_index<=0; aud_valid<=0; image_index<=0; image_mode<=0; image_base<=0; pool_pointer<=22'h0e1000;
            file_base<=0; file_bytes<=0; bytes_left<=0; pcm_byte_index<=0; pcm_word<=0;
            pcm_word_valid<=0; pcm_word_last<=0; pcm_addr<=0; pcm_word_addr<=0;
            load_busy<=1; load_done<=0; load_err<=0; flush<=0; done_target<=0; done_sync<=0;
            for(k=0;k<IMG_SLOTS;k=k+1) begin img_size_r[k]<=0; img_clus_r[k]<=0; end
        end else begin
            mount_req<=0; scan_req<=0; read_req<=0; bmp_start<=0; load_done<=0; pcm_word_valid<=0;
            done_sync<={done_sync[0],done_toggle};
            if (file_valid) begin
                if (state==SCAN_BMP_WAIT && file_index<IMG_SLOTS) begin
                    img_size_r[file_index[4:0]]<=file_size; img_clus_r[file_index[4:0]]<=file_cluster;
                    img_count<=MEDIA_PROFILE ? img_count+1'b1 : file_index+1'b1;
                    if(MEDIA_PROFILE)image_present[file_index[1:0]]<=1;
                end
                if (state==SCAN_PCM_WAIT) begin aud_valid[file_index]<=1; pcm_count<=pcm_count+1'b1; end
            end
            if (!image_mode && fr_valid && fr_ready && state==LOAD) begin
                if(pcm_byte_index==0) pcm_word<={24'd0,fr_data};
                else pcm_word[pcm_byte_index*8+:8]<=fr_data;
                bytes_left<=bytes_left-1'b1;
                if (pcm_byte_index==3 || bytes_left==1) begin
                    pcm_word_valid<=1; pcm_word_last<=bytes_left==1; pcm_word_addr<=pcm_addr;
                    pcm_addr<=pcm_addr+1'b1; pcm_byte_index<=0;
                end else pcm_byte_index<=pcm_byte_index+1'b1;
            end
            case (state)
                MOUNT: begin mount_req<=1; state<=MOUNT_WAIT; end
                MOUNT_WAIT: if (mount_err) state<=FAILED; else if (mount_done) begin progress<=2; state<=SCAN_BMP; end
                SCAN_BMP: begin scan_req<=1; state<=SCAN_BMP_WAIT; end
                SCAN_BMP_WAIT: if (scan_done) begin progress<=4; state<=SCAN_PCM; end
                SCAN_PCM: begin scan_req<=1; state<=SCAN_PCM_WAIT; end
                SCAN_PCM_WAIT: if (scan_done) begin
                    progress<=6; pcm_index<=0;
                    if(MEDIA_PROFILE)begin image_index<=0;preloading_images<=1;state<=SELECT_IMAGE;end
                    else state<=META_WAIT;
                end
                SELECT_IMAGE: begin
                    flush<=0;
                    if(image_index<3)begin
                        if(image_present[image_index[1:0]])begin
                            image_mode<=1;image_base<=image_index==0 ? 22'd0 : image_index==1 ? 22'h04b000 : 22'h096000;
                            file_bytes<=img_size_r[image_index];state<=START_FILE;
                        end else image_index<=image_index+1'b1;
                    end else begin preloading_images<=0;image_mode<=0;state<=META_WAIT;end
                end
                META_WAIT: state<=SELECT_FILE;
                SELECT_FILE: begin
                    flush<=0;
                    if (pcm_index<64) begin
                      if(!aud_valid[pcm_index[5:0]])begin pcm_index<=pcm_index+1'b1;state<=META_WAIT;end
                      else begin
                        image_mode<=0; file_bytes<=load_size; file_base<=pool_pointer;
                        pool_pointer<=pool_pointer+((load_size+3)>>2);
                        if (load_size[0] || load_size==0 ||
                            pool_pointer+((load_size+3)>>2)>22'h18f000) state<=FAILED;
                        else state<=START_FILE;
                      end
                    end else if (!MEDIA_PROFILE && img_count!=0) begin
                        image_mode<=1; image_index<=0; image_base<=0; file_bytes<=img_size_r[0]; state<=START_FILE;
                    end else begin assets_ok<=1; progress<=15; load_busy<=0; load_done<=1; state<=READY; end
                end
                START_FILE: begin
                    read_req<=1; bmp_start<=image_mode; bytes_left<=file_bytes; pcm_byte_index<=0; pcm_word<=0;
                    pcm_addr<=file_base; done_target<=~done_sync[1]; flush<=0; state<=LOAD;
                end
                LOAD: begin
                    if ((!image_mode && read_done) || (image_mode && sc_valid && sc_out_ready && sc_last)) begin flush<=1; state<=DRAIN; end
                end
                DRAIN: if (done_sync[1]==done_target) begin
                    if (!image_mode) begin pcm_index<=pcm_index+1'b1; state<=META_WAIT; progress<=8; end
                    else if(MEDIA_PROFILE && preloading_images)begin
                        media_valid[image_index[1:0]]<=1;image_index<=image_index+1'b1;state<=SELECT_IMAGE;
                    end
                    else begin assets_ok<=1; progress<=15; load_busy<=0; load_done<=1; state<=READY; end
                end
                READY: if (load_req) begin
                    if (img_sel>=img_count) load_err<=1;
                    else begin
                        image_mode<=1; image_index<=img_sel; image_base<=fb_sel==0 ? 22'd0 : fb_sel==1 ? 22'h04b000 : 22'h096000;
                        file_bytes<=img_size_r[img_sel]; flush<=0; load_busy<=1; state<=START_FILE;
                    end
                end
                FAILED: begin load_err<=1; assets_ok<=0; load_busy<=0; end
                default: state<=FAILED;
            endcase
            if (read_err || (image_mode && bp_error) || pixel_count>15 || (word_push && !word_ready && !image_mode)) state<=FAILED;
            if(MEDIA_PROFILE && image_mode && bp_header && (bp_width!=640 || bp_height!=480 || bp_bpp!=24))state<=FAILED;
        end
    end
endmodule

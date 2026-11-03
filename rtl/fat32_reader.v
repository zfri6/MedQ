`timescale 1ns / 1ps
// Read-only FAT32: MBR or superfloppy, multi-sector clusters and full 28-bit FAT chains.
module fat32_reader #(parameter NAMED_PCM=0,NAMED_BMP=0) (
    input  wire       clk,
    input  wire       rst_n,
    // Mount control
    input  wire       mount_req,
    output reg        mount_done,
    output reg        mount_err,
    // Scan control
    input  wire       scan_req,
    input  wire [23:0] scan_ext,      // Extension to match, e.g. "BMP"=0x424D50
    output reg        file_valid,
    output reg  [5:0] file_index,
    output reg  [31:0] file_size,
    output reg  [31:0] file_cluster,
    output reg        scan_done,
    output reg  [6:0] file_count,
    // File read control
    input  wire       read_req,
    input  wire [31:0] read_cluster,
    input  wire [31:0] read_len,
    output reg        read_busy,
    output reg        read_done,
    output reg        read_err,
    // Byte stream output
    input wire        out_ready,
    output wire       out_valid,
    output wire [7:0] out_data,
    // SD card interface
    output reg        sd_rd_req,
    output reg  [31:0] sd_rd_lba,
    input  wire       sd_rd_done,
    input  wire       sd_rd_err,
    input  wire       sd_byte_valid,
    input  wire [7:0] sd_byte_data
);


    localparam IDLE=0, WAIT_SECTOR=1, MBR=2, BPB=3, SCAN_FETCH=4, SCAN_PARSE=5,
               SCAN_NEXT=6, READ_FETCH=7, READ_STREAM=8, READ_NEXT=9, FAT_FETCH=10, FAT_PARSE=11,
               SCAN_PREP=12, SCAN_LOAD=13, READ_PREP=14, FAT_PREP=15, BPB_SIZE=16;
    reg [4:0] state, continuation;
    // One synchronous read port. Four byte lanes permit byte writes without
    // parallel variable-index read muxes across the entire 512-byte sector.
    reg [7:0] sector0 [0:127], sector1 [0:127], sector2 [0:127], sector3 [0:127];
    reg [31:0] sector_word;
    reg [31:0] dir_words [0:7];
    reg [2:0] dir_index;
    reg [15:0] boot_signature,boot_bytes,boot_reserved;
    reg [7:0] boot_spc,boot_fats,partition_type;
    reg [31:0] boot_fat_size,boot_root,partition_start;
    reg [9:0] byte_count, cursor;
    reg [31:0] partition_lba,fat_start,data_start,root_clus,current_cluster,remaining;
    reg [7:0] sec_per_clus,sec_in_clus;
    reg [2:0] clus_shift,mul_step;
    reg [7:0] fat_multiplier;
    reg [31:0] fat_accum,fat_addend;
    function [2:0] cluster_shift;
        input [7:0] count;
        begin
            case(count)
                1:cluster_shift=0;2:cluster_shift=1;4:cluster_shift=2;8:cluster_shift=3;
                16:cluster_shift=4;32:cluster_shift=5;64:cluster_shift=6;default:cluster_shift=7;
            endcase
        end
    endfunction
    reg [23:0] extension;
    reg [63:0] scan_seen;
    wire named_pcm_scan=NAMED_PCM && extension==24'h50434d;
    wire named_bmp_scan=NAMED_BMP && extension==24'h424d50;
    wire named_scan=named_pcm_scan || named_bmp_scan;
    wire [7:0] clip_tens=dir_words[1][7:0],clip_ones=dir_words[1][15:8];
    wire [6:0] pcm_named_id=({3'd0,clip_tens[3:0]}<<3)+({3'd0,clip_tens[3:0]}<<1)+{3'd0,clip_ones[3:0]};
    wire pcm_named_valid=dir_words[0]==32'h50494c43 && dir_words[1][31:16]==16'h2020 &&
       clip_tens>=8'h30 && clip_tens<=8'h36 && clip_ones>=8'h30 && clip_ones<=8'h39 && pcm_named_id<54;
    wire cover_name=dir_words[0]==32'h45564f43 && dir_words[1]==32'h20202052;
    wire doctor1_name=dir_words[0]==32'h30434f44 && dir_words[1]==32'h20202031;
    wire doctor2_name=dir_words[0]==32'h30434f44 && dir_words[1]==32'h20202032;
    wire [6:0] named_id=named_bmp_scan ? (cover_name ? 7'd0 : doctor1_name ? 7'd1 : 7'd2) : pcm_named_id;
    wire named_valid=named_bmp_scan ? (cover_name || doctor1_name || doctor2_name) : pcm_named_valid;
    reg mounted,reading;
    reg [31:0] watchdog;
    reg [15:0] chain_hops;
    task fetch;
        input [31:0] lba;
        input [4:0] resume_state;
        begin
            sd_rd_req<=1; sd_rd_lba<=lba; byte_count<=0;
            continuation<=resume_state; state<=WAIT_SECTOR; watchdog<=0;
        end
    endtask
    task fail;
        begin
            if (!mounted) mount_err<=1;
            else begin read_err<=1; if (!reading) scan_done<=1; end
            read_busy<=0; state<=IDLE;
        end
    endtask
    // BPB validation guarantees a power-of-two cluster size (1..128).
    wire [31:0] data_lba=data_start+((current_cluster-32'd2)<<clus_shift)+sec_in_clus;
    assign out_valid=state==READ_STREAM;
    assign out_data=out_valid ? (sector_word >> {cursor[1:0],3'b000}) : 8'd0;
    wire [31:0] fat_next=sector_word & 32'h0fffffff;
    wire [6:0] sector_read_addr = state==FAT_PREP || state==FAT_PARSE ? current_cluster[6:0] :
                                  state==SCAN_LOAD ? cursor[8:2]+{4'd0,dir_index}+7'd1 : cursor[8:2];
    // No reset on memory/read data, preserving block-RAM inference. Data is
    // exposed only after a complete sector and an explicit prefetch cycle.
    always @(posedge clk) begin
        if (state==WAIT_SECTOR && sd_byte_valid && byte_count<512) begin
            case (byte_count[1:0])
                0: sector0[byte_count[8:2]]<=sd_byte_data;
                1: sector1[byte_count[8:2]]<=sd_byte_data;
                2: sector2[byte_count[8:2]]<=sd_byte_data;
                3: sector3[byte_count[8:2]]<=sd_byte_data;
            endcase
        end
        sector_word<={sector3[sector_read_addr],sector2[sector_read_addr],
                      sector1[sector_read_addr],sector0[sector_read_addr]};
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; continuation<=0; byte_count<=0; cursor<=0;
            partition_lba<=0; fat_start<=0; data_start<=0; root_clus<=0;
            current_cluster<=0; remaining<=0; sec_per_clus<=0; sec_in_clus<=0;
            clus_shift<=0;mul_step<=0;fat_multiplier<=0;fat_accum<=0;fat_addend<=0;
            extension<=0; mounted<=0; reading<=0; watchdog<=0; chain_hops<=0;
            mount_done<=0; mount_err<=0; file_valid<=0; file_index<=0; file_size<=0; file_cluster<=0;
            scan_done<=0; file_count<=0; scan_seen<=0; read_busy<=0; read_done<=0; read_err<=0;
            sd_rd_req<=0; sd_rd_lba<=0;
            dir_index<=0; boot_signature<=0; boot_bytes<=0; boot_reserved<=0;
            boot_spc<=0; boot_fats<=0; partition_type<=0;
            boot_fat_size<=0; boot_root<=0; partition_start<=0;
        end else begin
            mount_done<=0; mount_err<=0; file_valid<=0; scan_done<=0;
            read_done<=0; read_err<=0; sd_rd_req<=0;
            case (state)
                IDLE: begin
                    if (mount_req) begin mounted<=0; partition_lba<=0; fetch(0,MBR); end
                    else if (scan_req && mounted) begin
                        extension<=scan_ext; file_count<=0; scan_seen<=0; current_cluster<=root_clus;
                        sec_in_clus<=0; chain_hops<=0; reading<=0; state<=SCAN_FETCH;
                    end else if (read_req && mounted) begin
                        if (read_cluster<2) read_err<=1;
                        else if (read_len==0) read_done<=1;
                        else begin
                            current_cluster<=read_cluster; remaining<=read_len; sec_in_clus<=0;
                            read_busy<=1; reading<=1; chain_hops<=0; state<=READ_FETCH;
                        end
                    end else if ((scan_req || read_req) && !mounted) fail;
                end
                WAIT_SECTOR: begin
                    watchdog<=watchdog+1'b1;
                    if (sd_byte_valid) begin
                        // Capture only the fields needed for MBR/BPB parsing.
                        case (byte_count)
                            11: boot_bytes[7:0]<=sd_byte_data;
                            12: boot_bytes[15:8]<=sd_byte_data;
                            13: boot_spc<=sd_byte_data;
                            14: boot_reserved[7:0]<=sd_byte_data;
                            15: boot_reserved[15:8]<=sd_byte_data;
                            16: boot_fats<=sd_byte_data;
                            36: boot_fat_size[7:0]<=sd_byte_data;
                            37: boot_fat_size[15:8]<=sd_byte_data;
                            38: boot_fat_size[23:16]<=sd_byte_data;
                            39: boot_fat_size[31:24]<=sd_byte_data;
                            44: boot_root[7:0]<=sd_byte_data;
                            45: boot_root[15:8]<=sd_byte_data;
                            46: boot_root[23:16]<=sd_byte_data;
                            47: boot_root[31:24]<=sd_byte_data;
                            450: partition_type<=sd_byte_data;
                            454: partition_start[7:0]<=sd_byte_data;
                            455: partition_start[15:8]<=sd_byte_data;
                            456: partition_start[23:16]<=sd_byte_data;
                            457: partition_start[31:24]<=sd_byte_data;
                            510: boot_signature[7:0]<=sd_byte_data;
                            511: boot_signature[15:8]<=sd_byte_data;
                            default: begin end
                        endcase
                        byte_count<=byte_count+1'b1;
                    end
                    if (sd_rd_err || watchdog==32'd100000000) fail;
                    else if (sd_rd_done) begin
                        if (byte_count+(sd_byte_valid ? 1 : 0)!=512) fail;
                        else begin state<=continuation; cursor<=0; end
                    end
                end
                MBR: begin
                    if (boot_signature!=16'haa55) fail;
                    else if (boot_bytes==512) state<=BPB;
                    else if (partition_type==8'h0b || partition_type==8'h0c) begin
                        partition_lba<=partition_start; fetch(partition_start,BPB);
                    end else fail;
                end
                BPB: begin
                    if (boot_signature!=16'haa55 || boot_bytes!=512 || boot_spc==0 ||
                        (boot_spc & (boot_spc-1))!=0 || boot_reserved==0 ||
                        boot_fats==0 || boot_fat_size==0 || boot_root<2) fail;
                    else begin
                        sec_per_clus<=boot_spc; root_clus<=boot_root&32'h0fffffff;
                        clus_shift<=cluster_shift(boot_spc);
                        fat_start<=partition_lba+boot_reserved;
                        // This product is needed once per mount; eight serial
                        // shift/add cycles replace a permanent wide multiplier.
                        fat_multiplier<=boot_fats;fat_addend<=boot_fat_size;
                        fat_accum<=0;mul_step<=0;state<=BPB_SIZE;
                    end
                end
                BPB_SIZE: begin
                    if(fat_multiplier[0])fat_accum<=fat_accum+fat_addend;
                    fat_multiplier<=fat_multiplier>>1;fat_addend<=fat_addend<<1;
                    if(mul_step==7)begin
                        data_start<=partition_lba+boot_reserved+fat_accum+(fat_multiplier[0] ? fat_addend : 32'd0);
                        mounted<=1;mount_done<=1;state<=IDLE;
                    end else mul_step<=mul_step+1'b1;
                end
                SCAN_FETCH: fetch(data_lba,SCAN_PREP);
                SCAN_PREP: begin dir_index<=0; state<=SCAN_LOAD; end
                SCAN_LOAD: begin
                    dir_words[dir_index]<=sector_word;
                    if (dir_index==7) state<=SCAN_PARSE;
                    else dir_index<=dir_index+1'b1;
                end
                SCAN_PARSE: begin
                    if (dir_words[0][7:0]==0 || (!named_scan && file_count==32)) begin scan_done<=1; state<=IDLE; end
                    else begin
                        if (named_scan && named_valid && scan_seen[named_id[5:0]] &&
                            (dir_words[2][31:24]&8'h18)==0 && dir_words[2][31:24]!=8'h0f &&
                            {dir_words[2][7:0],dir_words[2][15:8],dir_words[2][23:16]}==extension) fail;
                        else begin
                        if (dir_words[0][7:0]!=8'he5 && (dir_words[2][31:24]&8'h18)==0 &&
                            dir_words[2][31:24]!=8'h0f &&
                            {dir_words[2][7:0],dir_words[2][15:8],dir_words[2][23:16]}==extension && (!named_scan || named_valid)) begin
                            file_valid<=1; file_index<=named_scan ? named_id[5:0] : file_count[5:0]; file_count<=file_count+1'b1;
                            if(named_scan)scan_seen[named_id[5:0]]<=1;
                            file_size<=dir_words[7];
                            file_cluster<={dir_words[5][15:0],dir_words[6][31:16]} & 32'h0fffffff;
                        end
                        if (cursor==480) state<=SCAN_NEXT;
                        else begin cursor<=cursor+32; state<=SCAN_PREP; end
                        end
                    end
                end
                SCAN_NEXT: if (sec_in_clus+1<sec_per_clus) begin
                    sec_in_clus<=sec_in_clus+1'b1; state<=SCAN_FETCH;
                end else state<=FAT_FETCH;
                READ_FETCH: fetch(data_lba,READ_PREP);
                READ_PREP: state<=READ_STREAM;
                READ_STREAM: if (out_ready) begin
                    remaining<=remaining-1'b1;
                    if (remaining==1) begin read_done<=1; read_busy<=0; state<=IDLE; end
                    else if (cursor==511) state<=READ_NEXT;
                    else begin cursor<=cursor+1'b1; state<=READ_PREP; end
                end
                READ_NEXT: if (sec_in_clus+1<sec_per_clus) begin
                    sec_in_clus<=sec_in_clus+1'b1; state<=READ_FETCH;
                end else state<=FAT_FETCH;
                FAT_FETCH: fetch(fat_start+(current_cluster>>7),FAT_PREP);
                FAT_PREP: state<=FAT_PARSE;
                FAT_PARSE: begin
                    if (fat_next>=32'h0ffffff8) begin
                        if (reading) fail;
                        else begin scan_done<=1; state<=IDLE; end
                    end else if (fat_next<2 || fat_next==32'h0ffffff7 || chain_hops==65535) fail;
                    else begin
                        current_cluster<=fat_next; sec_in_clus<=0; chain_hops<=chain_hops+1'b1;
                        state<=reading ? READ_FETCH : SCAN_FETCH;
                    end
                end
                default: fail;
            endcase
        end
    end
endmodule

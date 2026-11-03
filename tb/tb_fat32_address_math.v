`timescale 1ns / 1ps
// Check public SD LBAs against independent multiply expressions, including
// all legal cluster shifts and 32-bit modular products at mount time.
module tb_fat32_address_math;
    reg clk=0;always #10 clk=~clk;
    reg rst=0,mount=0,read_req=0;
    reg [7:0] spc=1,fats=1;
    reg [31:0] fat_size=1,expected_lba=0;
    wire mounted,mount_err,read_done,read_err,request,valid;
    wire [31:0] lba;wire [7:0] data;
    reg sd_valid=0,sd_done=0;reg [7:0] sd_data=0;
    reg boot_phase=1;
    localparam [31:0] CLUSTER=32'h0fff0003;
    fat32_reader dut(.clk(clk),.rst_n(rst),.mount_req(mount),.mount_done(mounted),.mount_err(mount_err),
        .scan_req(1'b0),.scan_ext(24'd0),.file_valid(),.file_index(),.file_size(),.file_cluster(),.scan_done(),.file_count(),
        .read_req(read_req),.read_cluster(CLUSTER),.read_len(32'd1),.read_busy(),.read_done(read_done),.read_err(read_err),
        .out_ready(1'b1),.out_valid(valid),.out_data(data),.sd_rd_req(request),.sd_rd_lba(lba),
        .sd_rd_done(sd_done),.sd_rd_err(1'b0),.sd_byte_valid(sd_valid),.sd_byte_data(sd_data));
    function [7:0] boot_byte;
        input integer n;
        begin
            case(n)
                11:boot_byte=0;12:boot_byte=2;13:boot_byte=spc;14:boot_byte=8'h34;15:boot_byte=8'h12;16:boot_byte=fats;
                36:boot_byte=fat_size[7:0];37:boot_byte=fat_size[15:8];38:boot_byte=fat_size[23:16];39:boot_byte=fat_size[31:24];
                44:boot_byte=2;510:boot_byte=8'h55;511:boot_byte=8'haa;default:boot_byte=0;
            endcase
        end
    endfunction
    integer n,shift_index,variant,seen=0,cases=0;
    reg [31:0] captured;
    always begin
        @(posedge clk);
        if(request)begin
            captured=lba;
            if(captured!==expected_lba)$fatal(1,"ERROR LBA spc=%0d fats=%0d size=%h exp=%h got=%h",spc,fats,fat_size,expected_lba,captured);
            @(negedge clk);
            for(n=0;n<512;n=n+1)begin
                sd_valid=1;sd_data=boot_phase ? boot_byte(n) : 8'(n^165);sd_done=n==511;
                @(negedge clk);
            end
            sd_valid=0;sd_done=0;
        end
    end
    always @(posedge clk)if(rst && valid)begin
        if(data!==8'ha5)$fatal(1,"ERROR read data");seen=seen+1;
    end
    initial begin
        for(shift_index=0;shift_index<8;shift_index=shift_index+1)for(variant=0;variant<4;variant=variant+1)begin
            rst=0;repeat(3)@(negedge clk);rst=1;boot_phase=1;expected_lba=0;spc=1<<shift_index;
            case(variant)
                0:begin fats=1;fat_size=1;end
                1:begin fats=2;fat_size=32'h01020304;end
                2:begin fats=3;fat_size=32'h80000001;end
                default:begin fats=255;fat_size=32'hffffffff;end
            endcase
            mount=1;@(negedge clk);mount=0;wait(mounted);@(negedge clk);
            boot_phase=0;expected_lba=32'h1234+fats*fat_size+(CLUSTER-2)*spc;seen=0;
            read_req=1;@(negedge clk);read_req=0;wait(read_done);@(negedge clk);
            if(seen!=1 || read_err || mount_err)$fatal(1,"ERROR FAT arithmetic transaction");
            cases=cases+1;
        end
        $display("PASS FAT address math: %0d mount/read cases, cluster sizes 1..128, FAT counts 1/2/3/255 and modular products",cases);$finish;
    end
    initial begin #3000000;$fatal(1,"TIMEOUT FAT arithmetic");end
endmodule

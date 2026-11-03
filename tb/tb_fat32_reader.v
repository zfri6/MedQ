`timescale 1ns / 1ps
module tb_fat32_reader;
`ifdef FAT_BOUNDARY
    localparam [31:0] FIRST_CLUSTER=32'h0001007f,SECOND_CLUSTER=32'h00010080;
`else
    localparam [31:0] FIRST_CLUSTER=32'h00010003,SECOND_CLUSTER=32'h00010005;
`endif
    localparam [31:0] DATA_FIRST=1026+FIRST_CLUSTER-2,DATA_SECOND=1026+SECOND_CLUSTER-2;
    reg clk=0;always #10 clk=~clk;
    reg rst=0,mount_req=0,scan_req=0,read_req=0,out_ready=1;
    reg [23:0] extension=24'h424d50;
    wire md,me,fv,sdone,busy,rdone,rerr,valid,sdreq;
    wire [5:0] findex;wire [6:0] count;wire [31:0] size,cluster,lba;wire [7:0] data;
    reg sd_done=0,sd_err=0,sd_valid=0;reg [7:0] sd_data=0,sector[0:511];
    reg inject_error=0,bad_bpb=0;
    integer seen=0,files=0,i,byte_number,cycles=0;reg [31:0] captured_lba;
    fat32_reader dut(.clk(clk),.rst_n(rst),.mount_req(mount_req),.mount_done(md),.mount_err(me),
        .scan_req(scan_req),.scan_ext(extension),.file_valid(fv),.file_index(findex),.file_size(size),.file_cluster(cluster),.scan_done(sdone),.file_count(count),
        .read_req(read_req),.read_cluster(FIRST_CLUSTER),.read_len(32'd700),.read_busy(busy),.read_done(rdone),.read_err(rerr),
        .out_ready(out_ready),.out_valid(valid),.out_data(data),.sd_rd_req(sdreq),.sd_rd_lba(lba),.sd_rd_done(sd_done),.sd_rd_err(sd_err),.sd_byte_valid(sd_valid),.sd_byte_data(sd_data));
    task le32(input integer offset,input [31:0] value);
        integer k;begin for(k=0;k<4;k=k+1)sector[offset+k]=value[8*k+:8];end
    endtask
    task make_sector(input [31:0] address);
        begin
            for(i=0;i<512;i=i+1)sector[i]=0;
            case(address)
                0:begin sector[450]=8'h0c;le32(454,1);sector[510]=8'h55;sector[511]=8'haa;end
                1:begin sector[11]=0;sector[12]=bad_bpb ? 1 : 2;sector[13]=1;sector[14]=1;sector[16]=1;
                    le32(36,1024);le32(44,2);sector[510]=8'h55;sector[511]=8'haa;end
                2:le32(8,6);
                514:le32(4*(FIRST_CLUSTER&127),SECOND_CLUSTER);
                1026:for(i=0;i<16;i=i+1)sector[i*32]=8'he5;
                1030:begin
                    sector[0]="G";sector[8]="B";sector[9]="M";sector[10]="P";sector[11]=8'h20;
                    sector[20]=FIRST_CLUSTER[23:16];sector[21]=FIRST_CLUSTER[31:24];
                    sector[26]=FIRST_CLUSTER[7:0];sector[27]=FIRST_CLUSTER[15:8];le32(28,700);
                    sector[32]="C";sector[40]="P";sector[41]="C";sector[42]="M";sector[43]=8'h20;sector[58]=4;le32(60,4);
                end
                DATA_FIRST:for(i=0;i<512;i=i+1)sector[i]=i[7:0]^8'ha5;
                DATA_SECOND:for(i=0;i<512;i=i+1)sector[i]=i[7:0]^8'h5a;
                default:$fatal(1,"ERROR unexpected filesystem LBA=%0d",address);
            endcase
        end
    endtask
    always begin
        @(posedge clk);
        if(sdreq)begin
            captured_lba=lba;@(negedge clk);
            if(inject_error && captured_lba==DATA_SECOND)begin sd_err=1;@(negedge clk);sd_err=0;end
            else begin
                make_sector(captured_lba);
                for(byte_number=0;byte_number<512;byte_number=byte_number+1)begin
                    sd_valid=1;sd_data=sector[byte_number];
`ifdef FAT_BOUNDARY
                    sd_done=byte_number==511;
`endif
                    @(negedge clk);
                end
`ifdef FAT_BOUNDARY
                sd_valid=0;sd_done=0;@(negedge clk);
`else
                sd_valid=0;sd_done=1;@(negedge clk);sd_done=0;
`endif
            end
        end
    end
    always @(posedge clk)if(rst)begin
        cycles=cycles+1;
        if(fv)begin
            files=files+1;
            if(cluster!==FIRST_CLUSTER || size!==700 || findex!==0)$fatal(1,"ERROR directory fields");
        end
        if(valid && out_ready)begin
            if(data !== (seen<512 ? (8'(seen)^8'ha5) : (8'(seen-512)^8'h5a)))$fatal(1,"ERROR fragmented file byte=%0d got=%h",seen,data);
            seen=seen+1;
        end
    end
    always @(negedge clk)out_ready=cycles%5!=0;
    initial begin
        repeat(4)@(negedge clk);rst=1;mount_req=1;@(negedge clk);mount_req=0;wait(md);
        @(negedge clk);scan_req=1;@(negedge clk);scan_req=0;wait(sdone);#1;
        if(files!=1 || count!==1)$fatal(1,"ERROR root directory chain");
        @(negedge clk);read_req=1;@(negedge clk);read_req=0;wait(rdone);@(negedge clk);
        if(seen!=700 || busy)$fatal(1,"ERROR exact file length %0d",seen);
        inject_error=1;seen=0;
        @(negedge clk);read_req=1;@(negedge clk);read_req=0;wait(rerr);@(negedge clk);
        if(seen!=512 || busy || rdone)$fatal(1,"ERROR SD error propagation");
        bad_bpb=1;@(negedge clk);mount_req=1;@(negedge clk);mount_req=0;wait(me);
        $display("PASS FAT32: chained root, 28-bit cluster indices, fragmented file, 700 exact bytes, backpressure, SD error, invalid BPB");$finish;
    end
    initial begin #1000000;$fatal(1,"TIMEOUT FAT32");end
endmodule

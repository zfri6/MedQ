`timescale 1ns/1ps
module tb_named_bmp;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,mount=0,scan=0;wire md,me,fv,sdone,rerr,sdreq;
 wire [5:0] id;wire [6:0] count;wire [31:0] size,cluster,lba;
 reg sd_done=0,sd_valid=0;reg [7:0] sd_data=0,disk[0:65535];
 integer i,k,n=0,errors=0,checks=0,address;reg [2:0] seen=0;
 fat32_reader #(.NAMED_PCM(1),.NAMED_BMP(1)) dut(.clk(clk),.rst_n(rst),.mount_req(mount),.mount_done(md),.mount_err(me),
 .scan_req(scan),.scan_ext(24'h424d50),.file_valid(fv),.file_index(id),.file_size(size),.file_cluster(cluster),.scan_done(sdone),.file_count(count),
 .read_req(1'b0),.read_cluster(32'd0),.read_len(32'd0),.read_busy(),.read_done(),.read_err(rerr),.out_ready(1'b1),.out_valid(),.out_data(),
 .sd_rd_req(sdreq),.sd_rd_lba(lba),.sd_rd_done(sd_done),.sd_rd_err(1'b0),.sd_byte_valid(sd_valid),.sd_byte_data(sd_data));
 always begin
  @(posedge clk);
  if(sdreq)begin
   address=lba*512;
   for(k=0;k<512;k=k+1)begin @(negedge clk);sd_valid=1;sd_data=disk[address+k];end
   @(negedge clk);sd_valid=0;sd_done=1;@(negedge clk);sd_done=0;
  end
 end
 always @(posedge clk)if(rst)begin
  if(rerr)errors=errors+1;
  if(fv)begin
   if(id>2 || seen[id] || size!=921654 || cluster!=22+id*10)$fatal(1,"ERROR BMP name/metadata id=%0d size=%0d cluster=%0d",id,size,cluster);
   seen[id]=1;n=n+1;checks=checks+1;
  end
 end
 task entry(input integer ix,input [87:0] filename,input integer location);
  integer j,offset;
  begin
   offset=1536+ix*32;
   for(j=0;j<32;j=j+1)disk[offset+j]=0;
   for(j=0;j<11;j=j+1)disk[offset+j]=filename[87-j*8-:8];
   disk[offset+11]=8'h20;disk[offset+26]=location;
   disk[offset+28]=8'h36;disk[offset+29]=8'h10;disk[offset+30]=8'h0e;
  end
 endtask
 task scan_files;begin
  @(negedge clk);seen=0;n=0;errors=0;scan=1;@(negedge clk);scan=0;wait(sdone);repeat(3)@(negedge clk);
 end endtask
 initial begin
  $readmemh("medq_sd_image.hex",disk);
  for(i=0;i<512;i=i+1)disk[1536+i]=0;
  entry(0,"DOC02   BMP",42);entry(1,"UNUSED  BMP",52);entry(2,"COVER   BMP",22);entry(3,"DOC01   BMP",32);
  repeat(8)@(negedge clk);rst=1;mount=1;@(negedge clk);mount=0;wait(md);@(negedge clk);
  scan_files;if(n!=3 || count!=3 || errors || seen!=7)$fatal(1,"ERROR named BMP complete scan");
  entry(4,"DOC02   BMP",42);scan_files;if(n!=3 || errors!=1)$fatal(1,"ERROR duplicate BMP accepted");
  disk[1536+4*32]=0;disk[1536+3*32]=8'he5;
  scan_files;if(n!=2 || count!=2 || errors || seen!=5)$fatal(1,"ERROR missing doctor shifted IDs");
  $display("PASS named BMP: shuffled COVER/DOC01/DOC02, unrelated BMP ignored, duplicate rejected, missing doctor preserves IDs; checked=%0d",checks);$finish;
 end
 initial begin #1000000;$fatal(1,"TIMEOUT named BMP");end
endmodule

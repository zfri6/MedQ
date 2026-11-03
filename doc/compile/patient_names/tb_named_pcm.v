`timescale 1ns/1ps
module tb_named_pcm;
 reg clk=0;always #10 clk=~clk;
 reg rst=0,mount=0,scan=0;wire md,me,fv,sdone,rerr,sdreq;
 wire [5:0] id;wire [6:0] count;wire [31:0] size,cluster,lba;
 reg sd_done=0,sd_valid=0;reg [7:0] sd_data=0,disk[0:65535];
 integer i,k,n=0,mode=0,errors=0,checks=0;reg [63:0] seen=0;
 fat32_reader #(.NAMED_PCM(1)) dut(.clk(clk),.rst_n(rst),.mount_req(mount),.mount_done(md),.mount_err(me),
 .scan_req(scan),.scan_ext(24'h50434d),.file_valid(fv),.file_index(id),.file_size(size),.file_cluster(cluster),.scan_done(sdone),.file_count(count),
 .read_req(1'b0),.read_cluster(32'd0),.read_len(32'd0),.read_busy(),.read_done(),.read_err(rerr),.out_ready(1'b1),.out_valid(),.out_data(),
 .sd_rd_req(sdreq),.sd_rd_lba(lba),.sd_rd_done(sd_done),.sd_rd_err(1'b0),.sd_byte_valid(sd_valid),.sd_byte_data(sd_data));
 function integer entry(input integer ix);
 begin entry=ix<32 ? 1536+ix*32 : 119*512+(ix-32)*32;end
 endfunction
 integer address;
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
   if(id>53 || seen[id] || size!=6 || cluster!=id+4)$fatal(1,"ERROR filename ID/content mismatch id=%0d size=%0d cluster=%0d",id,size,cluster);
   if(mode!=3 && id!=53-n)$fatal(1,"ERROR reverse directory order lost");
   seen[id]=1;n=n+1;checks=checks+1;
  end
 end
 task scan_files;
 begin
  @(negedge clk);seen=0;n=0;errors=0;scan=1;@(negedge clk);scan=0;
  wait(sdone);repeat(2)@(negedge clk);
 end endtask
 initial begin
  $readmemh("medq_sd_image.hex",disk);repeat(8)@(negedge clk);rst=1;mount=1;
  @(negedge clk);mount=0;wait(md);@(negedge clk);
  scan_files;if(n!=54 || count!=54 || errors!=0 || seen!=64'h003fffffffffffff)$fatal(1,"ERROR complete named scan");
  // An unrelated PCM and reserved ID54 are ignored, not assigned a speech ID.
  mode=1;for(i=0;i<32;i=i+1)disk[entry(55)+i]=disk[entry(1)+i];
  disk[entry(55)]="X";
  for(i=0;i<32;i=i+1)disk[entry(56)+i]=disk[entry(1)+i];disk[entry(56)+4]="5";disk[entry(56)+5]="4";
  scan_files;if(n!=54 || count!=54 || errors!=0)$fatal(1,"ERROR unknown PCM was enumerated");
  // A repeated valid short filename must fail, never overwrite the earlier ID.
  mode=2;for(i=0;i<32;i=i+1)disk[entry(55)+i]=disk[entry(1)+i];
  scan_files;if(errors!=1 || n!=54)$fatal(1,"ERROR duplicate named asset was accepted");
  // Sparse ID map preserves IDs, including when the final required clip is absent.
  mode=3;disk[entry(55)]=0;disk[entry(1)]=8'he5;
  scan_files;if(n!=53 || count!=53 || errors!=0 || seen[53] || !seen[52] || !seen[0])$fatal(1,"ERROR missing ID shifted names/digits");
  $display("PASS named FAT32: 54 reverse-ordered filenames across nonadjacent root clusters; unknown/reserved PCM ignored; duplicate rejected; missing clip never shifts IDs; checked=%0d",checks);$finish;
 end
 initial begin #10000000;$fatal(1,"TIMEOUT named FAT32");end
endmodule

`timescale 1ns/1ps
// Actual supplied BMP files -> board SPI -> FAT chains -> native decoder ->
// asynchronous write FIFO -> throttled memory beats. Every image word checked.
module tb_media_assets;
 reg clk=0,mclk=0,rst=0;always #10 clk=~clk;always #13 mclk=~mclk;
 wire sclk,mosi,miso,cs,req,we,wvalid,rdready,done,busy,error,ok;
 wire [21:0] addr,base,samples;wire [8:0] len;wire [31:0] data;
 wire [5:0] images;wire [6:0] clips;wire [2:0] valid;wire [3:0] progress;
 reg [5:0] clip=0;reg accepted=0;reg [21:0] cursor;reg [8:0] left;
 reg [4:0] pause=0;wire ready=!accepted && pause[1:0]!=0;wire wready=accepted && pause[2:0]!=0;
 asset_loader #(.SD_INIT_DIV(0),.SD_DATA_DIV(0),.SD_RESPONSE_LIMIT(8),.MEDIA_PROFILE(1)) dut(
  .clk_sys(clk),.rst_n_sys(rst),.clk_mem(mclk),.rst_n_mem(rst),.load_req(1'b0),.img_sel(5'd0),.fb_sel(2'd0),
  .load_busy(busy),.load_done(done),.load_err(error),.img_count(images),.pcm_count(clips),.assets_ok(ok),.media_valid(valid),.progress(progress),
  .clip_sel(clip),.clip_base(base),.clip_samples(samples),.sd_spi_sclk(sclk),.sd_spi_mosi(mosi),.sd_spi_miso(miso),.sd_spi_cs_n(cs),
  .wr_req_valid(req),.wr_req_ready(ready),.wr_req_addr(addr),.wr_req_we(we),.wr_req_len(len),
  .wr_wr_valid(wvalid),.wr_wr_ready(wready),.wr_wr_data(data),.wr_rd_valid(1'b0),.wr_rd_ready(rdready),.wr_rd_data(32'd0));
 sd_card_model #(.IMAGE_FILE("medq_media_sd.hex"),.DISK_SECTORS(6144)) card(.sclk(sclk),.mosi(mosi),.miso(miso),.cs_n(cs));
 reg [23:0] reference[0:921599];
 integer words=0,audio_words=0,bursts=0,k,idx;reg [2:0] previous_valid=0;
 initial begin
  $readmemh("medq_media_rgb0.hex",reference,0,307199);
  $readmemh("medq_media_rgb1.hex",reference,307200,614399);
  $readmemh("medq_media_rgb2.hex",reference,614400,921599);
  repeat(8)@(negedge clk);rst=1;
  wait(done || error);repeat(100)@(negedge clk);
  if(error || !ok || valid!=7 || images!=3 || clips!=54 || words!=921600 || audio_words!=108)$fatal(1,"ERROR media load counts error=%b valid=%b words=%0d PCM=%0d",error,valid,words,audio_words);
  for(k=0;k<54;k=k+1)begin
   clip=k;repeat(3)@(negedge clk);
   if(samples!=3 || base!=22'h0e1000+k*2)$fatal(1,"ERROR PCM metadata changed by media");
  end
  $display("PASS actual SD media: three shuffled named native BMPs, 921600 exact RGB words, cross-clock/backpressure/row boundaries, cover-first readiness, 54 unchanged PCM IDs/108 words, FAT multi-sector/multi-cluster files; bursts=%0d sectors=%0d",bursts,card.read_count);$finish;
 end
 always @(posedge mclk)if(rst)begin
  pause<=pause+1'b1;
  if(req && ready)begin
   if(!we || len==0 || len>64 || addr>=22'h18f000)$fatal(1,"ERROR media write descriptor");
   if(addr<921600 && (addr%640)+len>640)$fatal(1,"ERROR image burst crossed row");
   accepted<=1;cursor<=addr;left<=len;bursts=bursts+1;
  end
  if(wvalid && wready)begin
   if(cursor<921600)begin
    if(data!=={8'd0,reference[cursor]})$fatal(1,"ERROR native pixel addr=%h got=%h expected=%h",cursor,data,reference[cursor]);
    if(cursor!==words)$fatal(1,"ERROR missing/duplicate image word");
    words=words+1;
   end else begin
    if(cursor!=22'h0e1000+audio_words)$fatal(1,"ERROR PCM pool location");
    idx=audio_words/2;
    if(data!==(audio_words%2==0 ? {16'(-10000-idx),16'(12000+idx)} : {16'd0,16'(8000+idx)}))$fatal(1,"ERROR PCM payload changed");
    audio_words=audio_words+1;
   end
   cursor<=cursor+1'b1;left<=left-1'b1;if(left==1)accepted<=0;
  end
 end
 always @(posedge clk)if(rst)begin
  if(error)$fatal(1,"ERROR media loader rejected runtime assets state=%0d",dut.state);
  if(valid!=previous_valid)begin
   if(valid!=1 && valid!=3 && valid!=7)$fatal(1,"ERROR image readiness order");
   $display("CHECK media committed mask=%b image_words=%0d at %0t",valid,words,$time);
   previous_valid=valid;
  end
 end
 initial begin #1800000000;$fatal(1,"TIMEOUT media assets state=%0d words=%0d sectors=%0d",dut.state,words,card.read_count);end
endmodule

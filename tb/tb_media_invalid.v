`timescale 1ns/1ps
module tb_media_invalid;
 reg clk=0,rst=0;always #10 clk=~clk;
 wire error,ok,busy,sclk,mosi,miso,cs;wire [2:0] valid;wire wvalid;
 asset_loader #(.SD_INIT_DIV(0),.SD_DATA_DIV(0),.SD_RESPONSE_LIMIT(8),.MEDIA_PROFILE(1)) dut(
  .clk_sys(clk),.rst_n_sys(rst),.clk_mem(clk),.rst_n_mem(rst),.load_req(1'b0),.img_sel(5'd0),.fb_sel(2'd0),
  .load_busy(busy),.load_done(),.load_err(error),.img_count(),.pcm_count(),.assets_ok(ok),.media_valid(valid),.progress(),
  .clip_sel(6'd0),.clip_base(),.clip_samples(),.sd_spi_sclk(sclk),.sd_spi_mosi(mosi),.sd_spi_miso(miso),.sd_spi_cs_n(cs),
  .wr_req_valid(),.wr_req_ready(1'b1),.wr_req_addr(),.wr_req_we(),.wr_req_len(),
  .wr_wr_valid(wvalid),.wr_wr_ready(1'b1),.wr_wr_data(),.wr_rd_valid(1'b0),.wr_rd_ready(),.wr_rd_data(32'd0));
 sd_card_model card(.sclk(sclk),.mosi(mosi),.miso(miso),.cs_n(cs));
 initial begin
  #1;
  // Give the 2x2 legacy fixture the required cover name. It must now be
  // rejected as an invalid native-size asset, rather than silently stretched.
  card.disk[1536+0]="C";card.disk[1536+1]="O";card.disk[1536+2]="V";card.disk[1536+3]="E";card.disk[1536+4]="R";
  card.disk[1536+5]=" ";card.disk[1536+6]=" ";card.disk[1536+7]=" ";
  repeat(8)@(negedge clk);rst=1;wait(error);repeat(10)@(negedge clk);
  if(ok || busy || valid!=0 || wvalid)$fatal(1,"ERROR malformed media exposed partial data");
  $display("PASS invalid named native BMP: wrong dimensions rejected, no valid portrait/cover published, finite storage fallback");$finish;
 end
 initial begin #10000000;$fatal(1,"TIMEOUT invalid native image");end
endmodule

`timescale 1ns / 1ps
module tb_storage_errors;
    reg sys=0,mem=0,rst=0;always #10 sys=~sys;always #5 mem=~mem;
    wire error,ok,busy,sclk,cs_n;
    asset_loader #(.SD_INIT_DIV(0),.SD_DATA_DIV(0),.SD_RESPONSE_LIMIT(4)) dut(
        .clk_sys(sys),.rst_n_sys(rst),.clk_mem(mem),.rst_n_mem(rst),.load_req(1'b0),.img_sel(5'd0),.fb_sel(2'd0),
        .load_busy(busy),.load_done(),.load_err(error),.img_count(),.pcm_count(),.assets_ok(ok),.progress(),
        .clip_sel(5'd0),.clip_base(),.clip_samples(),.sd_spi_sclk(sclk),.sd_spi_mosi(),.sd_spi_miso(1'b1),.sd_spi_cs_n(cs_n),
        .wr_req_valid(),.wr_req_ready(1'b0),.wr_req_addr(),.wr_req_we(),.wr_req_len(),.wr_wr_valid(),.wr_wr_ready(1'b0),.wr_wr_data(),
        .wr_rd_valid(1'b0),.wr_rd_ready(),.wr_rd_data(32'd0));
    initial begin
        repeat(4)@(negedge sys);rst=1;wait(error);#1;
        if(ok || busy || !dut.u_sd_card_ctrl.init_fail || cs_n!==1)$fatal(1,"ERROR missing-card failure state");
        $display("PASS missing SD: finite initialization timeout, filesystem failure propagation, assets_ok=0");$finish;
    end
    initial begin #1000000;$fatal(1,"TIMEOUT missing SD");end
endmodule

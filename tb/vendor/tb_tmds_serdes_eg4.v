`timescale 1ns / 1ps
// Requires the unmodified EG4 eg_logic_io.v + eg_phy_glbl.v in ModelSim.
// Compile WITHOUT SIMULATION. No forcing of DUT state or vendor signals.
module serdes_vendor_case #(parameter integer PHASE=0)(output reg done=0);
    reg pix=0,ser=0,rst=0;
    always #20 pix=~pix;
    initial begin #(PHASE); forever #4 ser=~ser; end
    reg [9:0] d0=0,d1=0,d2=0;
    wire [3:0] q;
    tmds_serdes lane0(pix,ser,rst,d0,q[0]);
    tmds_serdes lane1(pix,ser,rst,d1,q[1]);
    tmds_serdes lane2(pix,ser,rst,d2,q[2]);
    tmds_serdes lane3(pix,ser,rst,10'b1111100000,q[3]);
    reg [29:0] words[0:2047];
    time word_time[0:2047];
    integer written=0,read_word=0,pair_index=0,checked=0;
    reg checking=0;
    reg [3:0] expected_even,expected_odd;
    reg [9:0] w0,w1,w2;
    integer epoch;

    always @(negedge pix) if(rst) begin
        d0<=d0+1'b1;
        d1<={d1[8:0],d1[9]^d1[6]^1'b1};
        d2<=~(d0*10'd139);
    end
    always @(posedge pix) if(rst) begin
        words[written]={d2,d1,d0};
        word_time[written]=$time;
        written=written+1;
    end
    always @(negedge rst) begin
        written=0;read_word=0;pair_index=0;checking=0;
        #1;
        if(q!==0) $fatal(1,"ERROR vendor async reset phase=%0d q=%b",PHASE,q);
    end
    // An independent queue contains words captured on pixel clock edges.
    // A word can start on the first serial posedge strictly AFTER capture.
    always @(posedge ser) begin
        if(rst) begin
            if(!checking && written>0 && $time>word_time[0]) checking=1;
            if(checking) begin
                if(read_word>=written) $fatal(1,"ERROR vendor serializer lost word");
                {w2,w1,w0}=words[read_word];
                expected_even={1'b0,w2[2*pair_index],w1[2*pair_index],w0[2*pair_index]};
                expected_odd={1'b0,w2[2*pair_index+1],w1[2*pair_index+1],w0[2*pair_index+1]};
                expected_even[3]=(2*pair_index>=5);
                expected_odd[3]=(2*pair_index+1>=5);
                #1;
                if(q!==expected_even) $fatal(1,"ERROR vendor even phase=%0d word=%0d pair=%0d exp=%b got=%b",PHASE,read_word,pair_index,expected_even,q);
            end
        end
    end
    always @(negedge ser) if(rst && checking) begin
        #1;
        if(q!==expected_odd) $fatal(1,"ERROR vendor odd phase=%0d word=%0d pair=%0d exp=%b got=%b",PHASE,read_word,pair_index,expected_odd,q);
        if(pair_index==4) begin
            pair_index=0;read_word=read_word+1;checked=checked+1;
        end else pair_index=pair_index+1;
    end
    initial begin
        // Reset away from clock edges, then interrupt an active word and retry.
        #83;rst=1;
        wait(checked>=1100);
        #2;rst=0;
        #33;rst=1;
        wait(checked>=1200);
        done=1;
    end
endmodule

module tb_tmds_serdes_eg4;
    wire done0,done4;
    serdes_vendor_case #(.PHASE(0)) aligned(done0);
    serdes_vendor_case #(.PHASE(4)) half_cycle(done4);
    initial begin
        wait(done0 && done4);
        $display("PASS EG4 ODDR: four lanes, 1200 words per phase, all 1024 input codes, both DDR edges, reset/restart");
        $finish;
    end
    initial begin #100000;$fatal(1,"TIMEOUT EG4 ODDR");end
endmodule

`timescale 1ns / 1ps
// SPI-mode SDHC fixture at the board pins. Parses actual 48-bit commands.
module sd_card_model #(parameter IMAGE_FILE="medq_sd_image.hex",DISK_SECTORS=128)(input wire sclk,mosi,cs_n,output reg miso);
    reg [7:0] disk[0:DISK_SECTORS*512-1];
    reg [7:0] command[0:5];
    reg [7:0] reply[0:1023];
    reg [7:0] rx,tx;
    integer bits,command_bytes,head,tail,i,lba,acmd_tries,idle_edges;
    integer read_count,command_count;
    initial begin
        $readmemh(IMAGE_FILE,disk);
        rx=0;tx=255;bits=0;command_bytes=0;head=0;tail=0;
        acmd_tries=0; idle_edges=0; read_count=0;command_count=0;miso=1;
    end
    always @(posedge cs_n) begin
        bits=0; command_bytes=0; head=0; tail=0; tx=255; miso=1;
    end
    always @(posedge sclk) begin
        if(cs_n) idle_edges=idle_edges+1;
        else begin
            rx={rx[6:0],mosi};
            if(bits==7) begin
                bits=0;
                if(command_bytes!=0 || rx[7:6]==2'b01) begin
                    command[command_bytes]=rx;
                    command_bytes=command_bytes+1;
                    if(command_bytes==6) begin
                        command_bytes=0; head=0;tail=0;command_count=command_count+1;
                        case(command[0][5:0])
                            0: begin
                                if(command[5]!==8'h95 || idle_edges<74) $fatal(1,"ERROR [sd_cmd0] CRC or idle clocks");
                                reply[tail]=1; tail=tail+1;
                            end
                            8: begin
                                if(command[5]!==8'h87) $fatal(1,"ERROR [sd_cmd8] CRC");
                                reply[0]=1;reply[1]=0;reply[2]=0;reply[3]=1;reply[4]=8'haa;tail=5;
                            end
                            55: begin reply[0]=1;tail=1;end
                            41: begin acmd_tries=acmd_tries+1;reply[0]=acmd_tries<3 ? 1 : 0;tail=1;end
                            58: begin reply[0]=0;reply[1]=8'h40;reply[2]=8'hff;reply[3]=8'h80;reply[4]=0;tail=5;end
                            17: begin
                                lba={command[1],command[2],command[3],command[4]};
                                if(lba>=DISK_SECTORS) $fatal(1,"ERROR [sd_address] LBA %0d",lba);
                                reply[0]=0;reply[1]=255;reply[2]=8'hfe;
                                for(i=0;i<512;i=i+1) reply[i+3]=disk[lba*512+i];
                                reply[515]=255;reply[516]=255;tail=517;read_count=read_count+1;
                            end
                            default: $fatal(1,"ERROR [sd_command] unsupported command %0d",command[0][5:0]);
                        endcase
                    end
                end
                if(head<tail) begin tx=reply[head];head=head+1;end
                else tx=255;
            end else bits=bits+1;
        end
    end
    always @(negedge sclk) if(!cs_n) miso=tx[7-bits];
endmodule

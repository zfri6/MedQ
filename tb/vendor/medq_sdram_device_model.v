`timescale 1ns/1ps
// Independent SDR SDRAM command/data model, 4 banks x 2048 rows x 256 x 32.
// Tests BL4/CL3, DQM, command order and refresh activity. Not a vendor timing model.
module medq_sdram_device_model #(parameter real T_AC=4.5,T_IS=1.5,T_IH=1.0,
 T_RCD=18.0,T_RP=15.0,T_RAS=35.0,T_RFC=55.0,T_REFI_MAX=31250.0) (
 input wire clk,rst_n,initialized,ras_n,cas_n,we_n,
 input wire [10:0] addr,input wire [1:0] ba,input wire [3:0] dm,
 inout wire [31:0] dq,output integer refresh_count,output integer errors
);
 reg [31:0] mem[0:2097151];
 reg [10:0] row[0:3];
 reg [3:0] opened;
 reg [31:0] drive_data;
 reg drive;
 reg [2:0] pipe_valid;
 integer pipe_addr[0:2];
 integer i,k,idx,burst_left,burst_col,burst_row,burst_bank;
 reg burst_write,auto_close;
 integer cycle,last_refresh,mode_count,write_count,read_count;
 realtime last_edge=0,last_control=0,last_ref_time=0;
 realtime guarded_ref_time=0;
 reg refresh_guard=0;
 realtime activated_at[0:3],precharged_at[0:3];
 assign dq=drive ? drive_data : 32'bz;
 task bad;
  input [255:0] reason;
  begin errors=errors+1;if(errors<=5)$display("FAIL device cycle=%0d %0s",cycle,reason);end
 endtask
 task write_word;
  input integer location;
  integer b;
  begin
   for(b=0;b<4;b=b+1)if(!dm[b])begin
    if(^dq[b*8+:8]===1'bx)bad("unknown write DQ");
    mem[location][b*8+:8]=dq[b*8+:8];
   end
  end
 endtask
 initial begin
  refresh_count=0;errors=0;write_count=0;read_count=0;
  for(i=0;i<2097152;i=i+1)mem[i]=0;
 end
 // These are independent pin-level AC checks, separate from FPGA routed STA.
 always @(ras_n or cas_n or we_n or addr or ba or dm)begin
  if(rst_n && last_edge>0 && $realtime-last_edge<T_IH)bad("command hold < tIH");
  last_control=$realtime;
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   opened=0;drive<=0;pipe_valid=0;burst_left=0;cycle=0;
   last_refresh=0;mode_count=0;auto_close=0;
   last_ref_time=0;
   guarded_ref_time=0;refresh_guard=0;
   for(k=0;k<4;k=k+1)begin activated_at[k]=-1000000;precharged_at[k]=-1000000;end
  end else begin
   if($realtime-last_control<T_IS)bad("command setup < tIS");
   // Power-up contents are undefined. Begin the retention deadline when the
   // controller releases initialization, before any application data is stored.
   if(initialized && !refresh_guard)begin refresh_guard=1;guarded_ref_time=$realtime;end
   if(refresh_guard && $realtime-guarded_ref_time>T_REFI_MAX)bad("refresh interval exceeded");
   if(last_ref_time>0 && {ras_n,cas_n,we_n}!=3'b111 && $realtime-last_ref_time<T_RFC)bad("command before tRFC");
   last_edge=$realtime;
   cycle=cycle+1;
   drive<=#(T_AC) pipe_valid[2];
   if(pipe_valid[2])drive_data<=#(T_AC) mem[pipe_addr[2]];
   pipe_valid={pipe_valid[1:0],1'b0};
   pipe_addr[2]=pipe_addr[1];pipe_addr[1]=pipe_addr[0];
   if(burst_left>0)begin
    idx=(burst_row*4+burst_bank)*256+burst_col;
    if(burst_write)write_word(idx);
    else begin pipe_valid[0]=1;pipe_addr[0]=idx;end
    burst_col=(burst_col&252)|((burst_col+1)&3);
    burst_left=burst_left-1;
    if(burst_left==0 && auto_close)opened[burst_bank]=0;
   end
   case({ras_n,cas_n,we_n})
    3'b011:begin // ACTIVE
     if(opened[ba])bad("ACT on open bank");
     if($realtime-precharged_at[ba]<T_RP)bad("ACT before tRP");
     activated_at[ba]=$realtime;
     opened[ba]=1;row[ba]=addr;
    end
    3'b100,3'b101:begin
     if(!opened[ba])bad("column command without ACT");
     if($realtime-activated_at[ba]<T_RCD)bad("column command before tRCD");
     if(burst_left!=0)bad("overlapping physical burst");
     if(mode_count==0)bad("column command before MRS");
     burst_write=!we_n;burst_row=row[ba];burst_bank=ba;
     burst_col=addr[7:0];auto_close=addr[10];
     idx=(burst_row*4+burst_bank)*256+burst_col;
     if(burst_write)begin write_word(idx);write_count=write_count+1;end
     else begin pipe_valid[0]=1;pipe_addr[0]=idx;read_count=read_count+1;end
     burst_col=(burst_col&252)|((burst_col+1)&3);burst_left=3;
    end
    3'b010:begin
     for(k=0;k<4;k=k+1)if(addr[10] || ba==k)begin
      if(opened[k] && $realtime-activated_at[k]<T_RAS)bad("PRE before tRAS");
      precharged_at[k]=$realtime;opened[k]=0;
     end
    end
    3'b001:begin
     if(opened!=0 || burst_left!=0)bad("refresh with active bank/burst");
     refresh_count=refresh_count+1;last_refresh=cycle;
     last_ref_time=$realtime;
     guarded_ref_time=$realtime;
    end
    3'b000:begin
     if(addr!==11'h032)bad("MRS differs from BL4/CL3");
     mode_count=mode_count+1;
    end
    default:begin end
   endcase
  end
 end
endmodule

`timescale 1ns/1ps
// Independent event-driven reference: no DUT memory/state used for expected values.
module tb_dual_service;
 reg clk=0;always #20 clk=~clk;
 reg rst=0;reg [1:0] run=3;reg [3:0] enq=0;reg [1:0] doc=0,allow=0;
 wire [1:0] req,pr;wire [1:0] grant=req&allow;wire [15:0] ticket;wire [127:0] q;
 medq_dual_service #(.AW(4),.MAX_TICKET(99),.INTERVAL_CYCLES(17)) dut(
 .clk(clk),.rst_n(rst),.running(run),.inputs_ready(1'b1),.enqueue(enq),.doctor_event(doc),
 .grant(grant),.request(req),.request_ticket(ticket),.request_return(pr),.qstate(q));
 integer nq[0:1][0:4095],rq[0:1][0:4095];
 integer nh[0:1],nt[0:1],rh[0:1],rt[0:1],st[0:1],cur[0:1],cc[0:1],tm[0:1],nxn[0:1],nxr[0:1],ok[0:1],done[0:1],miss[0:1];
 integer reject[0:1],retflag[0:1];
 integer i,n,r,first,pn,pp,an,ar,want,chosen,kind;
 integer exhausted=0,full_refusals=0;
 integer checked=0,grants=0,timeouts=0,visits=0,rejections=0,simultaneous=0,paused=0,priority_grants=0;
 reg [31:0] got;reg [31:0] random_state=32'h98129abc;
 function integer bcd(input integer v);begin bcd=(v/10)*16+v%10;end endfunction
 always @(posedge clk)begin
  if(!rst)begin
   for(i=0;i<2;i=i+1)begin nh[i]=0;nt[i]=0;rh[i]=0;rt[i]=0;st[i]=0;cur[i]=0;cc[i]=0;tm[i]=0;nxn[i]=1;nxr[i]=1;ok[i]=0;done[i]=0;miss[i]=0;reject[i]=0;retflag[i]=0;end
  end else begin
   for(i=0;i<2;i=i+1)begin
    n=nt[i]-nh[i];r=rt[i]-rh[i];
    want=run[i] && !doc[i] && ((st[i]==0 && (r!=0 || (n!=0 && !enq[i+2]))) || (st[i]==1 && cc[i]<3 && tm[i]==16));
    if(req[i]!==want[0])$fatal(1,"ERROR reference request clinic=%0d cycle=%0d state=%0d timer=%0d req=%b",i,checked,st[i],tm[i],req);
    if(want)begin
     chosen=st[i]==0 ? (r!=0 ? rq[i][rh[i]] : nq[i][nh[i]]) : cur[i];
     if(ticket[i*8+:8]!==bcd(chosen))$fatal(1,"ERROR FIFO order clinic=%0d expected=%0d got=%h",i,chosen,ticket[i*8+:8]);
    end
    begin
     first=grant[i] && st[i]==0;pp=first && r!=0;pn=first && r==0;
     ar=enq[i+2] && nxr[i]<=99 && (r<16 || pp);
     an=enq[i] && nxn[i]<=99 && (n<16 || pn);
     if(first)begin
      cur[i]=r!=0 ? rq[i][rh[i]] : nq[i][nh[i]];retflag[i]=r!=0;
      if(r!=0)begin rh[i]=rh[i]+1;priority_grants=priority_grants+1;end else nh[i]=nh[i]+1;
     end
     if(ar)begin rq[i][rt[i]]=nxr[i];rt[i]=rt[i]+1;nxr[i]=nxr[i]+1;ok[i]=ok[i]+1;end
     if(an)begin nq[i][nt[i]]=nxn[i];nt[i]=nt[i]+1;nxn[i]=nxn[i]+1;ok[i]=ok[i]+1;end
     if(ar || an)reject[i]=0;
     if((enq[i+2] && !ar)||(enq[i] && !an))begin reject[i]=1;rejections=rejections+1;end
     if(ar && an)simultaneous=simultaneous+1;
     if(nxn[i]==100 || nxr[i]==100)exhausted=exhausted+1;
     if((enq[i] && n==16 && !pn)||(enq[i+2] && r==16 && !pp))full_refusals=full_refusals+1;
     if(doc[i] && st[i]==1)begin st[i]=2;visits=visits+1;end
     else if(doc[i] && st[i]==2)begin st[i]=0;cur[i]=0;cc[i]=0;tm[i]=0;retflag[i]=0;done[i]=done[i]+1;end
     else if(run[i] && st[i]==1 && cc[i]==3 && tm[i]==16)begin st[i]=0;cur[i]=0;cc[i]=0;tm[i]=0;retflag[i]=0;miss[i]=miss[i]+1;timeouts=timeouts+1;end
     else if(run[i] && grant[i])begin if(st[i]==0)begin st[i]=1;cc[i]=1;end else cc[i]=cc[i]+1;tm[i]=0;grants=grants+1;end
     else if(run[i] && st[i]==1 && tm[i]!=16)tm[i]=tm[i]+1;
    end
    if(!run[i])paused=paused+1;
   end
   #1;
   for(i=0;i<2;i=i+1)begin
    got=q[i*32+:32];
    if(got[7:0]!==bcd(cur[i]) || got[12:8]!==nt[i]-nh[i] || got[17:13]!==rt[i]-rh[i] ||
       got[19:18]!==st[i] || got[21:20]!==cc[i] || got[22]!==retflag[i][0] || got[23]!==reject[i][0])
     $fatal(1,"ERROR first mismatch clinic=%0d cycle=%0d q=%h expected ticket=%0d n=%0d r=%0d state=%0d calls=%0d",i,checked,got,cur[i],nt[i]-nh[i],rt[i]-rh[i],st[i],cc[i]);
    if(ok[i]!=(nt[i]-nh[i])+(rt[i]-rh[i])+(st[i]!=0)+done[i]+miss[i])$fatal(1,"ERROR reference conservation");
   end
   if(q[67:66]!==run || q[64]!==(|run) || !q[65])$fatal(1,"ERROR independent QSTATE enables");
   if(dut.accepted_a!==ok[0] || dut.accepted_b!==ok[1] || dut.completed_a!==done[0] || dut.completed_b!==done[1] || dut.missed_a!==miss[0] || dut.missed_b!==miss[1])$fatal(1,"ERROR DUT conservation/totals");
   checked=checked+1;
  end
 end
 task step(input [3:0] e,input [1:0] d,input [1:0] a,input [1:0] go);begin @(negedge clk);enq=e;doc=d;allow=a;run=go;end endtask
 initial begin
  repeat(5)@(negedge clk);rst=1;
  step(1,0,0,3);step(4,0,0,3);step(0,0,1,3);step(15,0,0,3);
  step(0,1,3,3);step(5,1,3,3);step(0,0,3,3);
  repeat(80)step(0,0,3,3);
  for(integer epoch=0;epoch<6;epoch=epoch+1)begin
   @(negedge clk);rst=0;repeat(3)@(negedge clk);rst=1;
   for(integer k=0;k<12000;k=k+1)begin
    random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
    step({random_state[2:1]==0,random_state[4:3]==0,random_state[6:5]==0,random_state[8:7]==0},
     {random_state[13:9]==0,random_state[18:14]==0},random_state[20:19],{random_state[24:23]!=0,random_state[22:21]!=0});
   end
  end
  step(0,0,0,3);repeat(3)@(negedge clk);
  if(exhausted==0 || full_refusals==0 || checked<72000 || grants<100 || timeouts==0 || visits==0 || rejections==0 || simultaneous==0 || paused==0 || priority_grants==0)$fatal(1,"ERROR coverage");
  $display("PASS dual-room independent scoreboard: cycles=%0d grants=%0d missed=%0d visits=%0d refusals=%0d dual-enqueue=%0d call-disabled=%0d return-grants=%0d",checked,grants,timeouts,visits,rejections,simultaneous,paused,priority_grants);$finish;
 end
 initial begin #5000000;$fatal(1,"TIMEOUT independent scoreboard");end
endmodule

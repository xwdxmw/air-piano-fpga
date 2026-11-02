`timescale 1ns/1ps
module queue_scoreboard;
reg clk=0,rst=0,pop=0;always #10 clk=~clk;
reg[7:0] push=0;reg[151:0] data=0;
wire[18:0] head;wire empty,full,overflow;
event_queue_multi d(.clk(clk),.rst_n(rst),.push(push),.data(data),.pop(pop),.head(head),.empty(empty),.full(full),.overflow(overflow));
reg[18:0] gold[0:16383];integer wr=0,rd=0,cnt=0,serial=0,i,k;reg ov=0;
always @(posedge clk) if(!rst)begin wr=0;rd=0;cnt=0;ov=0;end
else begin
 if(pop&&cnt>0)begin if(head!==gold[rd])$fatal(1,"order mismatch index %0d",rd);rd=rd+1;cnt=cnt-1;end
 for(integer a=0;a<8;a=a+1)if(push[a])begin
  if(cnt<64)begin gold[wr]=data[a*19+:19];wr=wr+1;cnt=cnt+1;end
  else ov=1;
 end
 #1;
 if(d.count!==cnt || overflow!==ov)$fatal(1,"count/overflow mismatch got %0d expected %0d",d.count,cnt);
end
task cycle(input [7:0] mask,input rdreq);begin
 @(negedge clk);push=mask;pop=rdreq;
 for(integer a=0;a<8;a=a+1)begin data[a*19+:19]=serial;serial=serial+1;end
end endtask
initial begin
 #100;rst=1;
 repeat(8)cycle(8'hff,0);cycle(1,1);cycle(0,0);
 #1;if(!full || overflow)$fatal(1,"full simultaneous read/write");
 // Once full, excess writes must be visible, never silently overwrite old entries.
 cycle(3,1);cycle(0,0);#1;if(!overflow)$fatal(1,"overflow not latched");
 repeat(70)cycle(0,1);
 for(i=0;i<600;i=i+1)cycle($random,$random);
 repeat(70)cycle(0,1);
 cycle(0,0);#1;if(!empty)$fatal(1,"drain failed");
 $display("PASS 8-lane queue: ordered scoreboard, simultaneous full pop/push, overflow and wraparound");$finish;
end
endmodule

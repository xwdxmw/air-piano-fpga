`timescale 1ns/1ps
module voice_status_check;
reg ca=0,cd=0,ra=0,rd=0,req=0;always #41 ca=~ca;always #10 cd=~cd;
reg[31:0]active=0;wire ready;wire[31:0]mask;wire[5:0]count;
voice_status_snapshot d(.clk_a(ca),.rst_a(ra),.active(active),.clk_d(cd),.rst_d(rd),.capture_req(req),.ready(ready),.mask(mask),.count(count));
integer i,k,expected;reg[31:0]saved;
always @(negedge cd)if(rd && d.state==3 && ready)$fatal(1,"ready precedes bundled-data settling cycle");
function integer pc;input[31:0]x;integer j;begin pc=0;for(j=0;j<32;j=j+1)pc=pc+x[j];end endfunction
task request;begin @(negedge cd);req=1;@(negedge cd);req=0;wait(!ready);wait(ready);#1;end endtask
initial begin #100;ra=1;rd=1;repeat(50)@(negedge cd);
 if(ready || mask!==0 || count!==0)$fatal(1,"unacknowledged initial data exposed");
 for(i=0;i<=32;i=i+1)begin
  active=i==32 ? 32'hffffffff : (32'd1<<i)-1;request();
  if(mask!==active || count!==i)$fatal(1,"count/bit mapping %d %h %d",i,mask,count);
  saved=mask;active=~active;repeat(40)@(negedge cd);
  if(mask!==saved || count!==i)$fatal(1,"visible snapshot changed without request");
 end
 for(k=0;k<100;k=k+1)begin
  active=$random;expected=pc(active);request();if(mask!==active || count!==expected)$fatal(1,"random mask/count");repeat(40)@(negedge cd);
 end
 // Audio-only reset while a request is crossing must retry without deadlock.
 active=32'h80402010;@(negedge cd);req=1;@(negedge cd);req=0;wait(d.req_sync);#1;ra=0;#250;ra=1;
 wait(ready);#1;if(mask!==active || count!==4)$fatal(1,"audio reset pending request recovery");
 repeat(40)@(negedge cd);
 // A short display-only reset must drain an old audio ACK before re-issuing.
 active=32'hffffffff;@(negedge cd);req=1;@(negedge cd);req=0;wait(d.ack);#1;rd=0;#50;rd=1;
 active=32'h00000001;request();if(mask!==1 || count!==1)$fatal(1,"display reset reused stale ACK");
 $display("PASS coherent32-bit snapshots/count0..32,100 random masks, immutable frames, audio-only/display-only resets and pending-handshake recovery");$finish;
end
initial begin #2000000;$fatal(1,"voice snapshot timeout");end
endmodule

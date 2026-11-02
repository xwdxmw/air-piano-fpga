`timescale 1ns/1ps
module scope_snapshot;
reg ca=0,cd=0,ra=0,rd=0,tick=0,req=0;always #17 ca=~ca;always #10 cd=~cd;
reg signed[15:0] pcm=0;reg[6:0] addr=0;wire ready;wire[7:0] wy,lx,ly;
scope_cap #(.DEC(3),.LAG(4)) d(.clk_a(ca),.rst_a(ra),.sample_tick(tick),.pcm(pcm),
.rst_d(rd),.clk_d(cd),.raddr(addr),.capture_req(req),.ready(ready),.wave_y(wy),.liss_x(lx),.liss_y(ly));
always @(negedge ca)tick=ra;
integer i;reg[23:0] saved[0:127];
task request;begin @(negedge cd);req=1;@(negedge cd);req=0;wait(!ready);wait(ready);end endtask
initial begin
 #100;ra=1;rd=1;repeat(5)@(negedge cd);
 if({wy,lx,ly}!=={8'd28,8'd25,8'd25})$fatal(1,"uninitialized data exposed");
 request;
 for(i=0;i<128;i=i+1)begin addr=i;repeat(3)@(negedge cd);saved[i]={wy,lx,ly};if(saved[i]!=={8'd28,8'd25,8'd25})$fatal(1,"zero capture");end
 pcm=32767;repeat(1000)@(negedge ca);
 for(i=0;i<128;i=i+1)begin addr=i;repeat(3)@(negedge cd);if({wy,lx,ly}!==saved[i])$fatal(1,"display changed without request");end
 request;
 for(i=0;i<128;i=i+1)begin addr=i;repeat(3)@(negedge cd);if(wy!==6 || lx!==47 || ly!==3)$fatal(1,"capture decimation/amplitude");end
 $display("PASS asynchronous snapshot handshake, DEC=3, no undefined startup data, immutable frame, next capture updates");$finish;
end
initial begin #2000000;$fatal(1,"scope timeout");end
endmodule

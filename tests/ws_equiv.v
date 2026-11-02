`timescale 1ns/1ps
module ws_equiv_cell #(parameter N=30)(output reg done=0);
reg clk=0,rst=0;always #10 clk=~clk;
reg[N*24-1:0]grb=0;wire a,b;
ws2812_tx #(.N_LED(N),.FRAME_US(400))d(.clk(clk),.rst_n(rst),.grb(grb),.dout(a));
ap03_ws2812_tx #(.N_LED(N),.FRAME_US(400))refd(.clk(clk),.rst_n(rst),.grb(grb),.dout(b));
integer n,k,compares=0,starts=0;reg[31:0]rng=32'h5fa31c87;reg prev=0;
always @(posedge clk)begin
 #1;if(rst)begin
  if(a!==b)$fatal(1,"WS waveform mismatch N%0d cycle%0d",N,n);
  compares=compares+1;
  if(d.sending && !prev)starts=starts+1;
 end
 prev=d.sending;
end
initial begin
 #100;rst=1;
 for(n=0;n<300000;n=n+1)begin
  @(negedge clk);
  rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
  if(n%17==0)for(k=0;k<N;k=k+1)grb[k*24+:24]=(rng^(k*777+n));
  if(n==100003)begin rst=0;repeat(10)@(negedge clk);rst=1;end
 end
 if(starts<4)$fatal(1,"insufficient frames N%0d starts%0d",N,starts);
 $display("PASS AP03 WS waveform cycle-exact N%0d,%0d cycles,%0d frame starts, changing input snapshots and midframe reset",N,compares,starts);done=1;
end
endmodule
module ws_equiv;
wire a,b,c;
ws_equiv_cell d0(a);
ws_equiv_cell #(.N(8))d1(b);
ws_equiv_cell #(.N(1))d2(c);
initial begin wait(a&&b&&c);$finish;end
endmodule

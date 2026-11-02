`timescale 1ns/1ps
module old_warm_evidence;
reg clk=0,rst=0,tick=0;always #10 clk=~clk;wire signed[15:0]dout;
delay_fx #(.DEPTH(16),.AW(4),.DLY(4)) d(.clk(clk),.rst_n(rst),.sample_tick(tick),.din(16'sd0),.dout(dout));
initial begin #1;for(integer i=0;i<16;i=i+1)d.mem[i]=10000;
 #99;rst=1;@(negedge clk);tick=1;@(negedge clk);tick=0;repeat(3)@(negedge clk);
 if(dout!==0)$fatal(1,"R5G_REPRO: reset zero input produced %0d from retained RAM",dout);
 $finish;end
endmodule

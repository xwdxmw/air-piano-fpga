`timescale 1ns/1ps
`include "tests/force_map_reference.v"
module force_equiv_check;
reg clk=0,rst=0;always #5 clk=~clk;reg[11:0]raw=0,dead=0,maximum=4095;
wire[6:0]newv,oldv;integer n;reg[31:0]seed=32'h6291973;
force_map d(.clk(clk),.rst_n(rst),.raw(raw),.dead(dead),.raw_max(maximum),.velocity(newv));
force_map_reference old(.clk(clk),.rst_n(rst),.raw(raw),.dead(dead),.raw_max(maximum),.velocity(oldv));
always @(negedge clk)if(rst && newv!==oldv)$fatal(1,"force map mismatch new%0d old%0d raw%0d dead%0d max%0d",newv,oldv,raw,dead,maximum);
initial begin #30;rst=1;
for(n=0;n<30000;n=n+1)begin @(negedge clk);seed=seed*32'd1664525+32'd1013904223;
raw=seed[11:0];dead=seed[23:12];maximum=seed[31:20];
case(n%13)0:begin dead=0;maximum=4095;end 1:maximum=dead;2:maximum=0;3:raw=0;4:raw=4095;endcase
end
repeat(8)@(negedge clk);$display("PASS 30000 changing/random/boundary force inputs, exact value AND pipeline latency match original multiplier reference");$finish;end
endmodule

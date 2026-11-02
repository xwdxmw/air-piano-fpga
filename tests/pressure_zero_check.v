`timescale 1ns/1ps
module pressure_zero_check;
reg clk=0,rst=0,clear=0,valid=0;reg[2:0]idx=0;reg[11:0]data=0;always #10 clk=~clk;
wire[95:0] corrected;wire[7:0]ready,stale;
pressure_zero #(.CLK_FREQ_HZ(1000000),.KEY_MASK(8'h07)) d(.clk(clk),.rst_n(rst),.clear(clear),.valid(valid),.idx(idx),.data(data),.corrected(corrected),.ready(ready),.stale(stale));
task sample;input[2:0]ch;input[11:0]v;begin @(negedge clk);idx=ch;data=v;valid=1;@(negedge clk);valid=0;end endtask
initial begin
 #100;rst=1;
 repeat(96)sample(0,600);repeat(64)sample(1,600);
 if(d.base[0]!=600 || d.base[1]!=600 || d.count[0]!=64)$fatal(1,"uneven scan changed baseline");
 if(ready!=8'h03 || corrected!==0)$fatal(1,"missing channel blocked healthy channels");
 sample(0,900);#1;if(corrected[11:0]!=300)$fatal(1,"corrected pressure missing");
 repeat(20002)@(negedge clk);if(ready!=0 || corrected!==0)$fatal(1,"stale reading retained");
 sample(0,800);#1;if(!ready[0] || corrected[11:0]!=200)$fatal(1,"recovery latched out");
 clear=1;@(negedge clk);clear=0;#1;if(ready!=0 || d.count[0]!=0)$fatal(1,"clear baseline");
 $display("PASS independent 64-sample zero, fast channel frozen, missing lane isolated, stale release and recovery");$finish;
end
endmodule

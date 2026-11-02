`timescale 1ns/1ps
// Negative control, run only against untouched r5g sources. Failure is expected.
module old_zero_evidence;
reg clk=0,rst=0,v=0;reg[2:0]idx=0;always #10 clk=~clk;
c_interact_top d(.clk(clk),.rst_n(rst),.sensor_gpio(8'hff),.adc_p(96'd0),.adc_valid(1'b0),
 .adc_ch_valid(v),.adc_ch_idx(idx),.adc_ch_data(12'd600),.adc_o(96'd0),.touch_raw(1'b0),
 .calib_run_p(1'b0),.calib_run_o(1'b0),.calib_clear(1'b0));
task sample;input[2:0]ch;begin @(negedge clk);idx=ch;v=1;@(negedge clk);v=0;end endtask
initial begin #100;rst=1;repeat(96)sample(0);
 for(integer j=1;j<8;j=j+1)repeat(64)sample(j);
 repeat(5)@(negedge clk);
 if(d.az_base[0]!=600)$fatal(1,"R5G_REPRO: fast baseline=%0d expected600, slow=%0d",d.az_base[0],d.az_base[1]);
 $finish;end
endmodule

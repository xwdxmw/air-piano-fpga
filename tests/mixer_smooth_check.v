`timescale 1ns/1ps
module mixer_smooth_check;
reg clk=0,rst=0;always #5 clk=~clk;reg[3:0]sh=0;reg[31:0]pcm={16'd0,16'd16384};wire[15:0]out;
mixer #(.N(2),.GAIN_SHIFT(0),.SMOOTH_GAIN(1)) d(.clk(clk),.rst_n(rst),.sample_tick(1'b1),.pcm_in_v(pcm),.gain_shift(sh),.pcm_mix(out));
integer previous,current,i;
initial begin #30;rst=1;repeat(4)@(negedge clk);if(out!=16384)$fatal(1,"unity output");
 sh=1;previous=out;
 for(i=0;i<500;i=i+1)begin @(negedge clk);current=$signed(out);if(current>previous || previous-current>256)$fatal(1,"gain step is not smooth");previous=current;end
 if(out<8192 || out>8200)$fatal(1,"gain did not converge");
 sh=0;repeat(700)@(negedge clk);if(out<16380)$fatal(1,"gain return");
 pcm={16'h7fff,16'h7fff};repeat(3)@(negedge clk);if(out!=16'h7fff)$fatal(1,"positive overflow must saturate");
 pcm={16'h8000,16'h8000};repeat(3)@(negedge clk);if(out!=16'h8000)$fatal(1,"negative overflow must saturate");
 $display("PASS smooth gain convergence/return, bounded per-sample gain transition and signed saturation");$finish;end
endmodule

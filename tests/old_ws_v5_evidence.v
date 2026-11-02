`timescale 1ns/1ps
module old_ws_v5_evidence;
reg clk=0,rst=0;always #10 clk=~clk;wire dout;time fall_at=0;integer falls=0;
ws2812_tx #(.FRAME_US(300)) d(.clk(clk),.rst_n(rst),.grb({192{1'b1}}),.dout(dout));
always @(negedge dout)if(rst)begin fall_at=$time;falls=falls+1;end
always @(posedge dout)if(rst && falls>0)begin
 $display("Measured T1L = %0d ns; referenced V5 minimum = 580 ns",$time-fall_at);
 if($time-fall_at<580 || $time-fall_at>1000)$fatal(1,"published V5 T1L bounds violated");
 $display("PASS referenced V5 low bound");$finish;
end
initial begin #100;rst=1;end
initial begin #1000000;$fatal(1,"evidence timeout");end
endmodule

`timescale 1ns/1ps
module guide_disable;
reg clk=0,rst=0,en=0;always #10 clk=~clk;
wire on,off;wire[6:0] num,offnum;
guide_seq #(.CLK_FREQ_HZ(1000)) d(.clk(clk),.rst_n(rst),.enable(en),.key_on(8'd0),.note_on(on),.note_off(off),.note_num(num),.note_off_num(offnum));
initial begin
 #100;rst=1;en=1;wait(on);@(negedge clk);en=0;@(negedge clk);
 if(!off || offnum!=num)$fatal(1,"guide disable leaked note");
 @(negedge clk);if(off)$fatal(1,"duplicate release");
 $display("PASS guide releases current note when readiness/enable is lost");$finish;
end
endmodule

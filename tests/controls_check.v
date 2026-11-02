`timescale 1ns/1ps
module controls_check;
reg clk=0,rst=0,en=0,bn=1,tn=1;always #5 clk=~clk;
wire timbre;wire[6:0]bend;
performance_controls #(.CLK_HZ(1000),.DB_MS(2),.STEP_MS(2),.ARM_MS(5)) d(.clk(clk),.rst_n(rst),.enable(en),.bend_n(bn),.timbre_n(tn),.keyboard_flute(timbre),.bend(bend));
task waitn(input integer n);begin repeat(n)@(negedge clk);end endtask
initial begin #30;rst=1;tn=0;en=1;waitn(30);if(timbre || bend!=64)$fatal(1,"boot held control triggered");
tn=1;waitn(20);tn=0;waitn(20);if(!timbre)$fatal(1,"timbre selection absent");waitn(30);if(!timbre)$fatal(1,"long hold retrigger");
tn=1;waitn(15);bn=0;waitn(200);if(bend!=127 || !timbre)$fatal(1,"independent bend upper bound");
bn=1;waitn(200);if(bend!=64 || !timbre)$fatal(1,"bend does not return independently");
tn=0;waitn(15);tn=1;waitn(15);if(timbre)$fatal(1,"second timbre selection");
en=0;bn=0;tn=0;waitn(100);en=1;waitn(100);if(timbre || bend!=64)$fatal(1,"test lock or boot hold bypass");
$display("PASS independent timbre, smooth bend/return, debounce, no hold retrigger, boot release arm and test lock");$finish;end
endmodule

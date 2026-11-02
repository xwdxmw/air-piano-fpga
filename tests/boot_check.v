`timescale 1ns/1ps
module boot_check;
reg clk=0,rst=0,t=0;always #10 clk=~clk;wire done,test_mode,guide_mode;
boot_select #(.CLK_HZ(1000),.FIRST_MS(5)) d(.clk(clk),.rst_n(rst),.touch(t),.done(done),.test_mode(test_mode),.guide_mode(guide_mode));
task run;input a,b;input expected_test,expected_guide;begin
 rst=0;t=a;repeat(3)@(negedge clk);rst=1;repeat(8)@(negedge clk);
 if(done || test_mode || guide_mode)$fatal(1,"intermediate mode leaked");t=b;
 repeat(25)@(negedge clk);if(!done || test_mode!=expected_test || guide_mode!=expected_guide)$fatal(1,"mode selection");
end endtask
initial begin run(0,0,0,0);run(0,1,0,0);run(1,0,1,0);run(1,1,0,1);
 $display("PASS four boot combinations, no premature 32-note sequence");$finish;end
endmodule

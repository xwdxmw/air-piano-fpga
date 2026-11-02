`timescale 1ns/1ps
module harp_pending_check;
reg clk=0,rst=0; always #10 clk=~clk;

reg[7:0] blocked=0;wire ev;wire[6:0] num;integer n=0;reg[127:0] notes=0;
optical_harp d(.clk(clk),.rst_n(rst),.string_blocked(blocked),.event_valid(ev),.event_num(num));
always @(posedge clk)if(ev)begin n=n+1;notes[num]=1;$display("HARP %0d",num);end
initial begin #100;rst=1;@(negedge clk);blocked=8'h03;
@(negedge clk);blocked=8'h07;
repeat(20)@(negedge clk);
if(n!=3 || !notes[64])$fatal(1,"unexpected result");
$display("PASS: all 3 string rises survive simultaneous pending pop/push");$finish;end

endmodule

`timescale 1ns/1ps
module transpose_check;
reg clk=0,rst=0,on=0,harp=0,off=0,vu=0;reg signed[2:0]oct=0;reg[6:0]num=60,offnum=60,vunum=60;
always #10 clk=~clk;wire[6:0]p,q,r;
note_transpose d(.clk(clk),.rst_n(rst),.octave(oct),.on(on),.harp(harp),.num(num),.off(off),.off_num(offnum),.vu(vu),.vu_num(vunum),.on_pitch(p),.off_pitch(q),.vu_pitch(r));
initial begin #100;rst=1;@(negedge clk);on=1;@(negedge clk);on=0;oct=1;off=1;vu=1;#1;
 if(q!=60 || r!=60 || p!=72)$fatal(1,"old OFF/VU retuned");
 @(negedge clk);on=1;off=0;@(negedge clk);on=0;oct=-2;#1;
 if(q!=72 || r!=72 || p!=36)$fatal(1,"new pitch was not latched");
 harp=1;on=1;@(negedge clk);on=0;#1;if(q!=72)$fatal(1,"harp overwrote piano held pitch");
 $display("PASS octave changes new notes only; OFF and VU use held piano pitch, harp independent");$finish;
end
endmodule

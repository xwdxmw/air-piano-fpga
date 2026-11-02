`timescale 1ns/1ps
module ttp_check;
reg clk=0,rst=0,en=0,touch=0;always #10 clk=~clk;
wire vibrato,changed;wire signed[2:0]octave;integer changes=0;
ttp_gestures #(.CLK_HZ(1000)) d(.clk(clk),.rst_n(rst),.enable(en),.touch(touch),.play_enable(1'b1),.vibrato(vibrato),.changed(changed),.octave(octave));
always @(posedge clk)if(changed)changes=changes+1;
task waitn;input integer n;begin repeat(n)@(negedge clk);end endtask
task tap;begin touch=1;waitn(40);touch=0;waitn(2);end endtask
initial begin
 #100;rst=1;touch=1;en=1;waitn(900);if(octave!=0 || vibrato)$fatal(1,"boot hold became gesture");
 touch=0;waitn(25);tap();waitn(305);if(!vibrato || changes!=1)$fatal(1,"single click");
 tap();waitn(50);tap();waitn(310);if(octave!=1 || !vibrato || changes!=1)$fatal(1,"double also toggled vibrato");
 touch=1;waitn(1600);touch=0;waitn(310);if(octave!=0 || changes!=1)$fatal(1,"long hold repeated or toggled");
 repeat(4)begin touch=1;waitn(710);touch=0;waitn(5);end
 if(octave!=-2)$fatal(1,"octave lower bound");
 repeat(6)begin tap();waitn(5);tap();waitn(5);end
 if(octave!=2 || changes!=1)$fatal(1,"octave upper bound");
 // Mimic a late pre-boot touch arriving after the top's 10ms debounce.
 en=0;touch=0;waitn(5);en=1;waitn(8);touch=1;waitn(900);touch=0;waitn(25);
 if(octave!=2 || changes!=1)$fatal(1,"late boot touch armed during debounce lag");
 $display("PASS TTP boot release arm, delayed single, exclusive double/long, one-shot long and +/-2 bounds");$finish;
end
endmodule

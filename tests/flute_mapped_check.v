`timescale 1ns/1ps
`include "tests/flute_bank_logic_reference.v"
module flute_mapped_check;
reg clk=0,rst=0,tick=0,start=0,clear=0,run=1;reg[6:0]note=60;reg[31:0]freq=23409859;
always #5 clk=~clk;
wire signed[15:0]pcm,reference;
flute_bank d(.clk(clk),.rst_n(rst),.sample_tick(tick),.start(start),.clear(clear),.run(run),.seed_note(note),.freq_ctrl(freq),.wave(pcm));
flute_bank_logic_reference old(.clk(clk),.rst_n(rst),.sample_tick(tick),.start(start),.clear(clear),.run(run),.seed_note(note),.freq_ctrl(freq),.wave(reference));
integer n,seed=32'h13579bdf;reg[31:0]random_word;
initial begin #30;rst=1;
 for(n=0;n<50000;n=n+1)begin
  @(negedge clk);#1;
  if(pcm!==reference)$fatal(1,"block ROM changed PCM at cycle%d got%d ref%d",n,pcm,reference);
  random_word=$random(seed);freq=random_word & 32'h7fffffff;
  tick=(n%7)!=0;start=(n%997)==0;clear=(n%811)==0;run=(n%409)<390;note=n%128;
  if(n==25000)rst=0;else if(n==25001)rst=1;
 end
 $display("PASS50000 cycle-exact GOWIN pROM-NETLIST-vs-logic flute PCM incl frequency/band changes immediately before sample, every-cycle enables, gaps, reset,start,clear and noise sequence");$finish;
end
endmodule

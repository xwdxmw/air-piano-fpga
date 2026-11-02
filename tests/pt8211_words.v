`timescale 1ns/1ps
module pt8211_words;
reg clk=0,rst=0;always #40 clk=~clk;
reg [15:0] l=0,r=0;wire b,w,d,t;
pt8211_tx u(.clk(clk),.rst_n(rst),.left_data(l),.right_data(r),.bclk(b),.ws(w),.dacdat(d),.sample_tick(t));
reg checking=0;reg[15:0] el,er,word=0;integer bits=0,words=0;
always @(negedge w)if(rst)begin
 if(checking && bits!=16)$fatal(1,"bad high WS length");
 checking=1;bits=0;el=l;er=r;
end
always @(posedge w)if(checking && rst)begin
 if(bits!=16)$fatal(1,"bad low WS length");bits=0;
end
always @(posedge b)if(checking && rst)begin
 word={word[14:0],d};bits=bits+1;
 if(bits==16)begin
  if(word !== (w?er:el))$fatal(1,"serial mismatch got=%h expected=%h ws=%b",word,w?er:el,w);
  words=words+1;
 end
end
task pattern;input[15:0] a,b;begin @(negedge clk);l=a;r=b;repeat(4)@(negedge w);end endtask
initial begin #200;rst=1;
pattern(16'h0000,16'h0000);pattern(16'h7fff,16'h8000);pattern(16'hffff,16'h0001);
pattern(16'h1234,16'h5678);pattern(16'haaaa,16'h5555);pattern(16'h0000,16'h0000);
if(words<40)$fatal(1,"insufficient words");
$display("PASS actual pt8211_tx: %0d decoded words incl zero, signed extrema and alternating bits; 16 bits/WS half",words);$finish;end
endmodule

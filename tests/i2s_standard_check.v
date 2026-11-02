`timescale 1ns/1ps
module i2s_standard_check;
reg clk=0,rst=0;always #10 clk=~clk;
reg[15:0]l=0,r=0;wire b,w,data,tick;
standard_i2s_tx d(.clk(clk),.rst_n(rst),.left_data(l),.right_data(r),.bclk(b),.ws(w),.dacdat(data),.sample_tick(tick));
wire bb,bw,bd;
top_board #(.STANDARD_I2S(1),.USE_ENGINE(0)) board(.clk_50m(clk),.rst_n(rst),.event_req(1'b0),.event_payload(19'd0),.mode(1'b0),.bend(7'd64),.bclk(bb),.ws(bw),.dacdat(bd));
reg board_lastw=0,board_started=0;reg[15:0]board_saved=0,board_expected=0,board_word=0;
integer board_bits=0,board_words=0,board_nonzero=0;
always @(posedge board.clk_12m288)if(rst && board.sample_tick)board_saved=board.pcm_fx;
always @(posedge bb)if(rst)begin
 if(board_started)begin
  board_word={board_word[14:0],bd};board_bits=board_bits+1;
  if(board_bits==16)begin
   if(board_word!==board_expected)$fatal(1,"top_board STANDARD_I2S data mismatch");
   board_words=board_words+1;if(board_word!=0)board_nonzero=board_nonzero+1;
  end
 end
 if(bw!=board_lastw)begin
  if(board_started && board_bits!=16)$fatal(1,"top_board STANDARD_I2S WS lead mismatch");
  board_started=1;board_bits=0;board_expected=board_saved;
 end
 board_lastw=bw;
end
reg lastw=0,started=0,chan=0;reg[15:0]word=0,el=0,er=0,expected_word=0;integer bits=0,words=0,clocks=0;
always @(posedge clk)if(rst && tick)begin el=l;er=r;end
always @(posedge b)if(rst)begin
 if(started)begin
  word={word[14:0],data};bits=bits+1;
  if(bits==16)begin if(word !== expected_word)$fatal(1,"I2S word %h expected %h channel%b",word,expected_word,chan);words=words+1;end
 end
 if(w!=lastw)begin
  if(started && bits!=16)$fatal(1,"WS must precede MSB by one BCLK: old word bits=%0d",bits);
  bits=0;started=1;chan=w;
  expected_word=w?er:el;
 end
 lastw=w;
end
task pattern(input[15:0]a,input[15:0]c);begin @(negedge clk);l=a;r=c;repeat(4)@(negedge w);end endtask
initial begin #100;rst=1;
pattern(16'h0000,16'h0000);pattern(16'h8000,16'h7fff);pattern(16'h1234,16'h5678);pattern(16'haaaa,16'h5555);pattern(16'hffff,16'h0001);
if(words<30)$fatal(1,"insufficient I2S words");
wait(board_words>=36);if(board_nonzero==0)$fatal(1,"top_board I2S branch is silent");
$display("PASS standard I2S independent serial decoder: %0d signed stereo words, one-bit WS lead,16bit/channel; actual top_board STANDARD_I2S branch %0d decoded nonzero words",words,board_nonzero);$finish;end
initial begin #2000000;$fatal(1,"I2S timeout");end
endmodule

`timescale 1ns/1ps
module reset_release_check;
reg clk=0,rst=0;always #10 clk=~clk;
wire audio_rst;wire[15:0]pcm;
top_board d(.clk_50m(clk),.rst_n(rst),.event_req(1'b0),.event_payload(19'd0),
 .mode(1'b0),.bend(7'd64),.audio_rst_o(audio_rst),.pcm_mon_o(pcm));
integer n;
initial begin
 force d.pll_locked=0;#100;rst=1;
 for(n=0;n<20;n=n+1)begin
  #(3+n);force d.pll_locked=0;#1;
  if(audio_rst!==0 || d.audio_rst_sync!==0)$fatal(1,"PLL loss failed async reset");
  repeat(3)@(negedge d.clk_12m288);
  #(1+n);force d.pll_locked=1;
  @(posedge d.clk_12m288);#1;if(audio_rst!==0 || d.audio_rst_sync!==1)$fatal(1,"reset escaped on first audio edge");
  @(posedge d.clk_12m288);#1;if(audio_rst!==1 || d.audio_rst_sync!==3)$fatal(1,"reset did not release on second edge");
  repeat(300)@(posedge d.clk_12m288);#1;if(pcm!==0)$fatal(1,"reset cycle made idle noise");
 end
 #7;rst=0;#1;if(audio_rst!==0)$fatal(1,"external reset not asynchronous");
 #13;rst=1;@(posedge d.clk_12m288);#1;if(audio_rst!==0)$fatal(1,"external reset release too early");
 @(posedge d.clk_12m288);#1;if(audio_rst!==1)$fatal(1,"external reset release not synchronized");
 $display("PASS actual top_board20 varied-phase PLL loss/relock cycles: asynchronous assert,two-audio-edge release, idle PCM zero; external reset same; metastability not modeled");$finish;
end
endmodule

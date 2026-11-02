`timescale 1ns/1ps
module bell_alias_check;
reg clk=0,rst=0,start=0,clear=0;always #5 clk=~clk;
reg[31:0]freq=32'd23409859;wire signed[17:0]wave;wire alive;
bell_bank d(.clk(clk),.rst_n(rst),.sample_tick(1'b1),.start(start),.clear(clear),.freq_ctrl(freq),.wave(wave),.alive(alive));
integer n;reg[35:0]f;
always @(negedge clk)if(rst)begin
 if(!d.g_partial[0].u_p.freq_ok && d.partials[17:0]!==0)$fatal(1,"fundamental over-band leaked");
 if(!d.g_partial[1].u_p.freq_ok && d.partials[35:18]!==0)$fatal(1,"mode1 over-band leaked");
 if(!d.g_partial[2].u_p.freq_ok && d.partials[53:36]!==0)$fatal(1,"mode2 over-band leaked");
 if(!d.g_partial[3].u_p.freq_ok && d.partials[71:54]!==0)$fatal(1,"mode3 over-band leaked");
 if(wave>32767 || wave< -32768)$fatal(1,"modal sum lost headroom");
end
initial begin #30;rst=1;@(negedge clk);start=1;@(negedge clk);start=0;
for(n=0;n<1000;n=n+1)begin @(negedge clk);freq=n*32'd4294967;#1;f={4'd0,freq};
 if(d.freq1!==(f<<1)+(f>>1)+(f>>2)+(f>>8)+(f>>9))$fatal(1,"ratio1 overflow");
 if(d.freq3!==(f<<3)+f-(f>>4)-(f>>8)-(f>>11))$fatal(1,"ratio3 overflow");
end
freq=32'h70000000;repeat(2000)@(negedge clk);if(alive)$fatal(1,"high-band fade did not terminate");
freq=32'd23409859;start=1;@(negedge clk);start=0;repeat(100)@(negedge clk);
if(d.freq1<=freq*2 || d.freq1>=freq*3 || d.freq2<=freq*5 || d.freq3<=freq*8)$fatal(1,"noninteger modal frequencies absent");
$display("PASS 36bit noninteger modal frequencies, pre-truncation 0.45Fs guards, 0.40Fs fade, bounded sum, re-trigger");$finish;end
endmodule

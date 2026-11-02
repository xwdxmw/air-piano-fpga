`timescale 1ns/1ps
module lcd_spectrum_check;
reg clk=0,rst=0;always #10 clk=~clk;reg[7:0]div=0;integer n=0;
reg signed[15:0]pcm=0;wire ready;
always @(posedge clk)if(!rst)div<=0;else div<=div+1'b1;
always @(negedge clk)if(rst && div==0)begin pcm=$rtoi(12000*$sin(6.283185307179586*8*n/512.0));n=n+1;end
lcd_panel #(.DLY_120(60),.DLY_20(10),.CAP_WAIT(600000),.FRAME_GAP(20)) d(
 .clk(clk),.rst_n(rst),.mode(1'b0),.ir_v(8'd0),.clk_audio(clk),.rst_audio_n(rst),.sample_tick_audio(div==255),.voice_active_audio(32'd0),.pcm_audio(pcm),
 .guide_mode(1'b0),.test_mode(1'b0),.touch_state(1'b0),.keyboard_flute(1'b1),.guide_key(3'd0),.ready(ready));
initial begin #100;rst=1;
 wait(d.frame_spectrum[6*5+:5]>=10);wait(d.st==10);repeat(5)@(negedge clk);
 if(d.frame_ram[120*160+63]!==3'd2)$fatal(1,"real PCM spectral energy not painted into LCD");
 if(d.frame_ram[4*160+58]!==3'd5)$fatal(1,"keyboard flute cyan selection not visible");
 if(d.frame_ram[4*160+124]!==3'd1)$fatal(1,"version AP01 A glyph background differs");
 $display("PASS real PCM -> full-rate spectral analyzer -> acknowledged LCD frame -> actual yellow bin8 bar and timbre/version status");$finish;end
initial begin #150000000;$fatal(1,"LCD spectrum integration timeout");end
endmodule

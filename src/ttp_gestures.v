`timescale 1ns/1ps
// Debounced touch. Boot hold is ignored until stable release.
// 0.7..3s hold: octave down on release. >=3s: mode toggle, no octave change.
module ttp_gestures #(
 parameter integer CLK_HZ=50000000,DOUBLE_MS=300,LONG_MS=700,ARM_RELEASE_MS=20,MODE_MS=3000
)(input wire clk,rst_n,enable,touch,input wire play_enable,
 output reg vibrato,output reg changed,output reg signed[2:0] octave,output reg guide_toggle);
 localparam integer DBL=(CLK_HZ/1000)*DOUBLE_MS,LONG=(CLK_HZ/1000)*LONG_MS,ARM=(CLK_HZ/1000)*ARM_RELEASE_MS,MODE=(CLK_HZ/1000)*MODE_MS;
 reg armed,prev,pressed,mode_done,pending;reg[31:0]held,window_count;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin vibrato<=0;changed<=0;octave<=0;guide_toggle<=0;armed<=0;prev<=0;pressed<=0;mode_done<=0;pending<=0;held<=0;window_count<=0;end
  else begin
   changed<=0;guide_toggle<=0;prev<=touch;
   if(!enable)begin armed<=0;pressed<=0;mode_done<=0;pending<=0;held<=0;window_count<=0;end
   else if(!armed)begin
    if(touch)held<=0;else if(held>=ARM-1)begin armed<=1;prev<=0;held<=0;end else held<=held+1'b1;
   end else begin
    if(!play_enable)begin pending<=0;window_count<=0;end
    if(pending && !pressed && !touch && play_enable)begin
     if(window_count>=DBL-1)begin pending<=0;vibrato<=~vibrato;changed<=1;end else window_count<=window_count+1'b1;
    end
    if(touch && !prev)begin pressed<=1;held<=0;mode_done<=0;end
    else if(pressed && touch && !mode_done)begin
     if(held>=LONG-1)begin pending<=0;window_count<=0;end
     if(held>=MODE-1)begin mode_done<=1;pending<=0;guide_toggle<=1;end else held<=held+1'b1;
    end
    if(!touch && prev && pressed)begin
     pressed<=0;
     if(mode_done)pending<=0;
     else if(held>=LONG-1)begin pending<=0;if(play_enable && octave> -3'sd2)octave<=octave-1'b1;end
     else if(play_enable)begin
      if(pending)begin pending<=0;if(octave<3'sd2)octave<=octave+1'b1;end else begin pending<=1;window_count<=0;end
     end
     mode_done<=0;
    end
   end
  end
 end
endmodule

`timescale 1ns/1ps
// Latch the actually emitted pitch per physical key. OFF and VU must use it.
module note_transpose #(parameter integer FIXED_SEMITONES=0)(
 input wire clk,rst_n,input wire signed[2:0] octave,
 input wire on,harp,input wire[6:0] num,input wire off,input wire[6:0] off_num,
 input wire vu,input wire[6:0] vu_num,
 output wire[6:0] on_pitch,off_pitch,vu_pitch);
 reg[6:0] held_pitch[0:7];integer i;
 function [2:0] key_idx;input[6:0] n;begin
 case(n)60:key_idx=0;62:key_idx=1;64:key_idx=2;65:key_idx=3;67:key_idx=4;69:key_idx=5;71:key_idx=6;72:key_idx=7;default:key_idx=0;endcase
 end endfunction
 function[6:0] shift;input[6:0] n;input signed[2:0] oct;reg signed[31:0] s;begin
 s=$signed({1'b0,n})+$signed(oct)*12+FIXED_SEMITONES;
 if(s<0)shift=0;else if(s>127)shift=127;else shift=s[6:0];
 end endfunction
 assign on_pitch=shift(num,octave);
 assign off_pitch=held_pitch[key_idx(off_num)];
 assign vu_pitch=(on && !harp && num==vu_num)?on_pitch:held_pitch[key_idx(vu_num)];
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin for(i=0;i<8;i=i+1)held_pitch[i]<=60;held_pitch[1]<=62;held_pitch[2]<=64;held_pitch[3]<=65;held_pitch[4]<=67;held_pitch[5]<=69;held_pitch[6]<=71;held_pitch[7]<=72;end
  else if(on && !harp)held_pitch[key_idx(num)]<=on_pitch;
 end
endmodule

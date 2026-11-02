`timescale 1ns/1ps
// Philips I2S, 16 bits/channel, WS changes ONE BCLK before the next MSB.
// Audio frame = clk/256 (same engine sample rate as installed PT8211).
// This module is NOT compatible with the board PT8211 serial format.
module standard_i2s_tx(
 input wire clk,rst_n,input wire[15:0]left_data,right_data,
 output wire bclk,ws,output reg dacdat,output wire sample_tick);
 reg[7:0]phase;reg[15:0]left_hold,right_hold;
 // WS edge accompanies previous channel's LSB. New MSB is on next falling edge.
 assign bclk=phase[2];
 assign ws=(phase>=8'h78 && phase<8'hf8);
 assign sample_tick=phase==8'hf7;
 wire[3:0]bit_index=phase[6:3];
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin phase<=0;left_hold<=0;right_hold<=0;dacdat<=0;end
  else begin
   phase<=phase+1'b1;
   if(phase==8'hf7)begin left_hold<=left_data;right_hold<=right_data;end
   if(phase[2:0]==3'b111)begin
    if(phase==8'hff)dacdat<=left_hold[15];
    else if(phase==8'h7f)dacdat<=right_hold[15];
    else if(phase[7])dacdat<=right_hold[14-bit_index];
    else dacdat<=left_hold[14-bit_index];
   end
  end
 end
endmodule

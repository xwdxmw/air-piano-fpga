`timescale 1ns/1ps
module guide_led_map(input wire guide_mode,gate,hit,input wire[2:0]target,input wire[7:0]keys,output wire[191:0]grb);
 genvar i;generate for(i=0;i<8;i=i+1)begin:leds
 assign grb[i*24+:24]=(guide_mode && target==i)?(gate?(hit?24'h300000:24'h000018):24'd0):keys[i]?24'h080008:24'd0;
 end endgenerate
endmodule

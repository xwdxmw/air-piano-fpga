`timescale 1ns/1ps
// N-mode feedback: independent FSR / IR colors, bounded release hold for visibility.
// Uses already detected/debounced states; does not gate or delay audio events.
module live_led_follow #(
 parameter integer CLK_HZ=50000000,HOLD_MS=80
)(input wire clk,rst_n,enable,input wire[7:0] keys,strings,output wire[191:0] grb);
 localparam integer MS_CLKS=(CLK_HZ/1000>0)?CLK_HZ/1000:1;
 localparam integer MW=(MS_CLKS>1)?$clog2(MS_CLKS):1;
 localparam integer HW=(HOLD_MS>0)?$clog2(HOLD_MS+1):1;
 reg[MW-1:0] ms_div;
 wire ms_tick=(ms_div==MS_CLKS-1);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)ms_div<=0;
  else if(!enable || ms_tick)ms_div<=0;
  else ms_div<=ms_div+1'b1;
 end
 genvar i;generate for(i=0;i<8;i=i+1)begin:pixel
  reg[HW-1:0] key_hold,ir_hold;
  always @(posedge clk or negedge rst_n)begin
   if(!rst_n)begin key_hold<=0;ir_hold<=0;end
   else if(!enable)begin key_hold<=0;ir_hold<=0;end
   else begin
    if(keys[i])key_hold<=HOLD_MS;
    else if(ms_tick && key_hold!=0)key_hold<=key_hold-1'b1;
    if(strings[i])ir_hold<=HOLD_MS;
    else if(ms_tick && ir_hold!=0)ir_hold<=ir_hold-1'b1;
   end
  end
  wire k=rst_n && enable && (keys[i] || key_hold!=0);
  wire h=rst_n && enable && (strings[i] || ir_hold!=0);
  // GRB: FSR purple, IR cyan, both white. Components limited to16/255.
  assign grb[i*24+:24]=k?(h?24'h101010:24'h100010):(h?24'h101000:24'd0);
 end endgenerate
endmodule

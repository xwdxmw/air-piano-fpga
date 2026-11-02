`timescale 1ns/1ps
module boot_select #(parameter integer CLK_HZ=50000000,FIRST_MS=500)(
 input wire clk,rst_n,touch,output reg done,test_mode,guide_mode);
 localparam integer FIRST=(CLK_HZ/1000)*FIRST_MS,FINAL=FIRST*6;
 reg[31:0] count;reg first_touch;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin count<=0;done<=0;test_mode<=0;guide_mode<=0;first_touch<=0;end
  else if(!done)begin
   if(count==FIRST-1)first_touch<=touch;
   if(count>=FINAL-1)begin
    done<=1;test_mode<=first_touch && !touch;guide_mode<=first_touch && touch;
   end else count<=count+1'b1;
  end
 end
endmodule

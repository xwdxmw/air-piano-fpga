`timescale 1ns/1ps
// Behavioral clock only. Does not validate Gowin PLL or timing closure.
module pll_12m288(input clk_50m,output reg clk_12m288=0,output locked);
always #40.77 clk_12m288=~clk_12m288;
assign locked=1'b1;
endmodule

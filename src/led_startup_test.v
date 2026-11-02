`timescale 1ns/1ps
// One sweep at reset: 8 white pixels, all red/green/blue, then dark.
module led_startup_test #(parameter integer CLK_HZ=50000000,STEP_MS=200)(input wire clk,rst_n,output wire active,output reg[191:0]grb);
 localparam integer STEP=(CLK_HZ/1000)*STEP_MS;
 reg[31:0]count;reg[3:0]stage;integer i;
 assign active=stage<12;
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin count<=0;stage<=0;end
 else if(active)begin if(count>=STEP-1)begin count<=0;stage<=stage+1'b1;end else count<=count+1'b1;end
 end
 always @(*)begin
 grb=0;
 for(i=0;i<8;i=i+1)begin
 if(stage<8 && stage==i)grb[i*24+:24]=24'h080808;
 else if(stage==8)grb[i*24+:24]=24'h000800;
 else if(stage==9)grb[i*24+:24]=24'h080000;
 else if(stage==10)grb[i*24+:24]=24'h000008;
 end end
endmodule

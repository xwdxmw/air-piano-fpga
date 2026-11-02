`timescale 1ns/1ps
// GRB snapshot, LED0 first, MSB first. All counts derive from CLK_HZ.
module ap03_ws2812_tx #(
 parameter integer N_LED=8, CLK_HZ=50_000_000,
 parameter integer FRAME_US=5000, RESET_US=300,
 parameter integer T0H_NS=320,T0L_NS=900,T1H_NS=800,T1L_NS=600
)(input wire clk,rst_n,input wire[N_LED*24-1:0] grb,output reg dout);
 localparam integer T0H=(CLK_HZ/1000000)*T0H_NS/1000;
 localparam integer T1H=(CLK_HZ/1000000)*T1H_NS/1000;
 localparam integer T0L=(CLK_HZ/1000000)*T0L_NS/1000,T1L=(CLK_HZ/1000000)*T1L_NS/1000;
 localparam integer RESET_CLKS=(CLK_HZ/1000000)*RESET_US;
 localparam integer FRAME_CLKS=(CLK_HZ/1000000)*FRAME_US;
 localparam integer GAP_CLKS=(FRAME_CLKS>RESET_CLKS)?FRAME_CLKS:RESET_CLKS;
 localparam integer CW=$clog2(GAP_CLKS+1), LW=(N_LED>1)?$clog2(N_LED):1;
 reg [N_LED*24-1:0] frame;
 reg [CW-1:0] cnt;
 reg [LW-1:0] led_i;
 reg [4:0] bit_i;
 reg sending;
 wire val=frame[led_i*24+23-bit_i];
 wire [CW-1:0] high_clks=val?T1H:T0H;
 wire [CW-1:0] bit_clks=val?(T1H+T1L):(T0H+T0L);
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n)begin frame<=0;cnt<=0;led_i<=0;bit_i<=0;sending<=0;dout<=0;end
  else if(!sending)begin
   dout<=0;
   if(cnt==GAP_CLKS-1)begin frame<=grb;cnt<=0;led_i<=0;bit_i<=0;sending<=1;end
   else cnt<=cnt+1'b1;
  end else begin
   dout<=(cnt<high_clks);
   if(cnt==bit_clks-1)begin
    cnt<=0;
    if(bit_i==23)begin
     bit_i<=0;
     if(led_i==N_LED-1)sending<=0;
     else led_i<=led_i+1'b1;
    end else bit_i<=bit_i+1'b1;
   end else cnt<=cnt+1'b1;
  end
 end
endmodule


`timescale 1ns/1ps
// Independent controls on the Dock. key0/F15 bends; key1/G15 selects
// keyboard timbre. Old notes retain their own timbre. No sensor faults mute audio.
module performance_controls #(
 parameter integer CLK_HZ=50000000,DB_MS=10,STEP_MS=2,ARM_MS=20
)(input wire clk,rst_n,enable,bend_n,timbre_n,
 output reg keyboard_flute,output reg[6:0]bend);
 wire bend_pressed,timbre_pressed;
 c_sync_debounce #(.DB_CNT((CLK_HZ/1000)*DB_MS)) db0(.clk(clk),.rst_n(rst_n),.din(~bend_n),.dout(bend_pressed),.rise(),.fall());
 c_sync_debounce #(.DB_CNT((CLK_HZ/1000)*DB_MS)) db1(.clk(clk),.rst_n(rst_n),.din(~timbre_n),.dout(timbre_pressed),.rise(),.fall());
 // Include synchronizer/debounce settling before accepting the boot release.
 localparam integer ARM=(CLK_HZ/1000)*(ARM_MS+DB_MS)+4,STEP=(CLK_HZ/1000)*STEP_MS;
 reg armed,prev_timbre;reg[31:0]arm_count,step_count;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin keyboard_flute<=0;bend<=64;armed<=0;prev_timbre<=0;arm_count<=0;step_count<=0;end
  else begin
   prev_timbre<=timbre_pressed;
   if(!enable)begin bend<=64;armed<=0;arm_count<=0;step_count<=0;end
   else if(!armed)begin
    bend<=64;
    if(bend_pressed || timbre_pressed)arm_count<=0;
    else if(arm_count>=ARM-1)begin armed<=1;arm_count<=0;end
    else arm_count<=arm_count+1'b1;
   end else begin
    if(timbre_pressed && !prev_timbre)keyboard_flute<=~keyboard_flute;
    if(step_count>=STEP-1)begin
     step_count<=0;
     if(bend_pressed)begin if(bend<127)bend<=bend+1'b1;end
     else if(bend>64)bend<=bend-1'b1;
    end else step_count<=step_count+1'b1;
   end
  end
 end
endmodule

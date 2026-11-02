`timescale 1ns/1ps
// Per-channel, recoverable baseline. No all-channel mute and no fault latch.
module pressure_zero #(
 parameter integer WIDTH=8,ADC_W=12,CLK_FREQ_HZ=50000000,SAMPLES=64,STALE_MS=20,
 parameter [WIDTH-1:0] KEY_MASK={WIDTH{1'b1}}
)(input wire clk,rst_n,clear,input wire valid,input wire[2:0] idx,input wire[ADC_W-1:0] data,
 output wire[WIDTH*ADC_W-1:0] corrected,output wire[WIDTH-1:0] ready,stale);
 localparam integer LIMIT=(CLK_FREQ_HZ/1000)*STALE_MS;
 localparam integer AGE_W=$clog2(LIMIT+1),CNT_W=$clog2(SAMPLES+1),SUM_W=ADC_W+$clog2(SAMPLES);
 reg[ADC_W-1:0] raw[0:WIDTH-1],base[0:WIDTH-1];
 reg[SUM_W-1:0] sum[0:WIDTH-1];reg[CNT_W-1:0] count[0:WIDTH-1];
 reg[AGE_W-1:0] age[0:WIDTH-1];reg[WIDTH-1:0] done;
 integer i;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   done<=0;for(i=0;i<WIDTH;i=i+1)begin raw[i]<=0;base[i]<=0;sum[i]<=0;count[i]<=0;age[i]<=LIMIT;end
  end else if(clear)begin
   done<=0;for(i=0;i<WIDTH;i=i+1)begin raw[i]<=0;base[i]<=0;sum[i]<=0;count[i]<=0;age[i]<=LIMIT;end
  end else begin
   for(i=0;i<WIDTH;i=i+1)if(age[i]<LIMIT)age[i]<=age[i]+1'b1;
   if(valid && idx<WIDTH && KEY_MASK[idx])begin
    raw[idx]<=data;age[idx]<=0;
    if(!done[idx])begin
     sum[idx]<=sum[idx]+data;
     if(count[idx]==SAMPLES-1)begin
      base[idx]<=(sum[idx]+{{(SUM_W-ADC_W){1'b0}},data})>>$clog2(SAMPLES);
      done[idx]<=1;count[idx]<=SAMPLES;
     end else count[idx]<=count[idx]+1'b1;
    end
   end
  end
 end
 genvar g;generate for(g=0;g<WIDTH;g=g+1)begin: channels
  assign ready[g]=KEY_MASK[g] && done[g] && age[g]<LIMIT;
  assign stale[g]=KEY_MASK[g] && age[g]>=LIMIT;
  assign corrected[g*ADC_W+:ADC_W]=ready[g] && raw[g]>base[g]?raw[g]-base[g]:0;
 end endgenerate
endmodule

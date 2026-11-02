`timescale 1ns/1ps
// One 128-point snapshot per display request. RAM writes stop before ack crosses
// to the display clock. LCD renders only acknowledged snapshots, never live RAM.
module scope_cap #(
 parameter integer DEC=4,LAG=45,TRIGGER_ENABLE=0,TRIGGER_SAMPLES=960
)(input wire clk_a,rst_a,sample_tick,input wire signed[15:0] pcm,
 input wire rst_d,clk_d,input wire[6:0] raddr,input wire capture_req,
 output reg ready,output reg[7:0] wave_y,liss_x,liss_y);
 localparam integer DW=(DEC>1)?$clog2(DEC):1;
 reg req_toggle,ack_meta,ack_sync,busy;
 reg req_meta,req_sync,ack_toggle,capturing;
 reg[6:0] wp;reg waiting_trigger;reg[15:0]trigger_count;reg signed[15:0]previous;
 reg[DW-1:0] dec;
 reg[23:0] points[0:127];
 reg signed[15:0] hist[0:63];
 reg[5:0] hp;
 reg[6:0] hist_count;
 reg signed[15:0] hq;
 wire[5:0] hrd=hp-LAG;
 wire signed[16:0] xe={pcm[15],pcm};
 wire signed[16:0] ye=(hist_count>=LAG)?{hq[15],hq}:17'sd0;
 wire signed[16:0] ax=(xe>>>11)+(xe>>>12), ay=(ye>>>11)+(ye>>>12);
 function[7:0] clamp;
 input signed[16:0] value;input[7:0] upper;
 begin if(value<0)clamp=0;else if(value>$signed({1'b0,upper}))clamp=upper;else clamp=value[7:0];end
 endfunction
 wire[23:0] point={clamp(17'sd28-ax,56),clamp(17'sd25+ax,50),clamp(17'sd25-ay,50)};
 // Keep RAM outside asynchronous reset blocks for block-RAM inference.
 always @(posedge clk_a)begin
  if(rst_a && sample_tick)hist[hp]<=pcm;
  hq<=hist[hrd];
  if(rst_a && capturing && !waiting_trigger && sample_tick && dec==DEC-1)points[wp]<=point;
 end
 always @(posedge clk_a or negedge rst_a)begin
  if(!rst_a)begin req_meta<=0;req_sync<=0;ack_toggle<=0;capturing<=0;wp<=0;dec<=0;hp<=0;hist_count<=0;waiting_trigger<=0;trigger_count<=0;previous<=0;end
  else begin
   req_meta<=req_toggle;req_sync<=req_meta;
   if(sample_tick)begin previous<=pcm;hp<=hp+1'b1;if(hist_count<64)hist_count<=hist_count+1'b1;end
   if(!capturing && req_sync!=ack_toggle)begin capturing<=1;waiting_trigger<=TRIGGER_ENABLE;trigger_count<=0;wp<=0;dec<=0;end
   else if(capturing && sample_tick)begin
    if(waiting_trigger)begin
      if((previous<=0 && pcm>0) || trigger_count>=TRIGGER_SAMPLES-1)begin waiting_trigger<=0;dec<=0;end
      else trigger_count<=trigger_count+1'b1;
    end else if(dec==DEC-1)begin
     dec<=0;
     if(wp==127)begin capturing<=0;ack_toggle<=req_sync;end
     else wp<=wp+1'b1;
    end else dec<=dec+1'b1;
   end
  end
 end
 always @(posedge clk_d or negedge rst_d)begin
  if(!rst_d)begin req_toggle<=0;ack_meta<=0;ack_sync<=0;busy<=0;ready<=0;end
  else begin
   ack_meta<=ack_toggle;ack_sync<=ack_meta;
   if(capture_req && !busy)begin req_toggle<=~req_toggle;busy<=1;ready<=0;end
   else if(busy && ack_sync==req_toggle)begin ready<=1;busy<=0;end
  end
 end
 reg[23:0] read_q;
 always @(posedge clk_d)read_q<=points[raddr];
 always @(*)begin
  if(ready)begin wave_y=read_q[23:16];liss_x=read_q[15:8];liss_y=read_q[7:0];end
  else begin wave_y=28;liss_x=25;liss_y=25;end
 end
endmodule

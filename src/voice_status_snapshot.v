`timescale 1ns/1ps
// Coherent held-data, four-phase snapshot. No fake note counter.
module voice_status_snapshot #(
 parameter integer DRAIN_CLKS=32
)(input wire clk_a,rst_a,input wire[31:0]active,
 input wire clk_d,rst_d,capture_req,
 output reg ready,output reg[31:0]mask,output reg[5:0]count);
 reg req,req_meta,req_sync,ack,alive;reg[1:0]settle;
 reg[31:0]held;
 // Hold payload across an audio-only reset. It must not tear a snapshot already
 // acknowledged to the display; alive clears readiness and forces request drain.
 always @(posedge clk_a)if(rst_a && alive && req_sync && !ack)held<=active;
 always @(posedge clk_a or negedge rst_a)begin
  if(!rst_a)begin req_meta<=0;req_sync<=0;ack<=0;alive<=0;settle<=0;end
  else begin
   req_meta<=req;req_sync<=req_meta;
   if(!alive)begin
    ack<=0;
    if(settle!=3)settle<=settle+1'b1;
    else if(!req_sync)alive<=1;
   end else if(!req_sync)ack<=0;
   else if(!ack)ack<=1;
  end
 end
 reg ack_meta,ack_sync,alive_meta,alive_sync;
 reg[31:0]data_meta,data_sync;reg pending;reg[1:0]state;reg[5:0]drain;
 wire[31:0]p=data_sync;
 wire[31:0]pairs;wire[23:0]quads;wire[15:0]octs;wire[9:0]halves;
 genvar i;generate
 for(i=0;i<16;i=i+1)begin:g2 assign pairs[i*2+:2]={1'b0,p[i*2]}+{1'b0,p[i*2+1]};end
 for(i=0;i<8;i=i+1)begin:g4 assign quads[i*3+:3]={1'b0,pairs[i*4+:2]}+{1'b0,pairs[i*4+2+:2]};end
 for(i=0;i<4;i=i+1)begin:g8 assign octs[i*4+:4]={1'b0,quads[i*6+:3]}+{1'b0,quads[i*6+3+:3]};end
 for(i=0;i<2;i=i+1)begin:g16 assign halves[i*5+:5]={1'b0,octs[i*8+:4]}+{1'b0,octs[i*8+4+:4]};end
 endgenerate
 wire[5:0]popcount={1'b0,halves[4:0]}+{1'b0,halves[9:5]};
 always @(posedge clk_d or negedge rst_d)begin
  if(!rst_d)begin
   ack_meta<=0;ack_sync<=0;alive_meta<=0;alive_sync<=0;data_meta<=0;data_sync<=0;
   req<=0;pending<=0;state<=0;drain<=0;ready<=0;mask<=0;count<=0;
  end else begin
   ack_meta<=ack;ack_sync<=ack_meta;alive_meta<=alive;alive_sync<=alive_meta;
   data_meta<=held;data_sync<=data_meta;
   if(capture_req)begin pending<=1;ready<=0;end
   if(!alive_sync)begin req<=0;state<=0;drain<=0;ready<=0;mask<=0;count<=0;end
   else if(drain<DRAIN_CLKS)begin req<=0;drain<=drain+1'b1;end
   else case(state)
    0:if(pending && !ack_sync)begin req<=1;state<=1;ready<=0;end
    // Extra display clock after ACK lets every held 2FF data bit settle.
    1:if(ack_sync)state<=3;
    3:if(ack_sync)begin mask<=data_sync;count<=popcount;ready<=1;pending<=capture_req;req<=0;state<=2;end
    2:if(!ack_sync)state<=0;
    default:begin state<=0;req<=0;end
   endcase
  end
 end
endmodule

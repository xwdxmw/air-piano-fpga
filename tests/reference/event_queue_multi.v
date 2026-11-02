`timescale 1ns/1ps
// Eight simultaneous event lanes, packed into a chronological ring.
// Bank the ring by address modulo LANES: a contiguous group of <=LANES writes
// touches each bank at most once. This avoids a giant 8-write-port memory mux.
// LANES and DEPTH must be powers of two; DEPTH >= 2*LANES, AW=log2(DEPTH).
module ap03_event_queue_multi #(
 parameter integer LANES=8,DW=19,DEPTH=64,AW=6
)(input wire clk,rst_n,input wire[LANES-1:0] push,
 input wire[LANES*DW-1:0] data,input wire pop,
 output wire[DW-1:0] head,output wire empty,full,output reg overflow);
 localparam integer BW=$clog2(LANES),RW=AW-BW,ROWS=DEPTH/LANES;
 reg[AW-1:0] wr,rd,next_wr;
 reg[AW:0] count,used;
 reg[LANES-1:0] accepted;
 reg[LANES*AW-1:0] positions;
 reg excess;
 integer lane;
 assign empty=(count==0);
 assign full=(count==DEPTH);
 always @(*)begin
  used=count;next_wr=wr;accepted=0;positions=0;excess=0;
  if(pop && !empty)used=used-1'b1;
  for(lane=0;lane<LANES;lane=lane+1)begin
   positions[lane*AW+:AW]=next_wr;
   if(push[lane])begin
    if(used<DEPTH)begin
     accepted[lane]=1;next_wr=next_wr+1'b1;used=used+1'b1;
    end else excess=1;
   end
  end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin wr<=0;rd<=0;count<=0;overflow<=0;end
  else begin
   wr<=next_wr;count<=used;
   if(pop && !empty)rd<=rd+1'b1;
   if(excess)overflow<=1;
  end
 end
 wire[LANES*DW-1:0] bank_head;
 genvar b;
 generate for(b=0;b<LANES;b=b+1)begin: bank
  reg[DW-1:0] mem[0:ROWS-1];
  reg wen;reg[RW-1:0] wa;reg[DW-1:0] wd;
  integer k;
  always @(*)begin
   wen=0;wa=0;wd=0;
   for(k=0;k<LANES;k=k+1)begin
    if(accepted[k] && positions[k*AW+:BW]==b)begin
     wen=1;wa=positions[k*AW+BW+:RW];wd=data[k*DW+:DW];
    end
   end
  end
  always @(posedge clk)if(rst_n && wen)mem[wa]<=wd;
  assign bank_head[b*DW+:DW]=mem[rd[AW-1:BW]];
 end endgenerate
 assign head=bank_head[rd[BW-1:0]*DW+:DW];
endmodule


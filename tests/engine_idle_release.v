`timescale 1ns/1ps
module engine_idle_release;
reg clk=0,rst=0; always #10 clk=~clk;

reg[3:0] div=0;always @(posedge clk)div<=div+1'b1;wire tick=(div==15);
reg ev=0;reg[1:0] typ=0;reg[6:0] note=60,vel=100;reg timbre=0;
wire[511:0] pcm;wire[31:0] active;
top_synth d(.clk(clk),.rst_n(rst),.sample_tick(tick),.event_valid(ev),.event_type(typ),.event_num(note),.event_vel(vel),.event_source(2'd0),.event_timbre(timbre),.mode(1'b0),.bend(7'd64),.vib_off(23'd0),.pcm_out_v(pcm),.active_debug(active));
task event_send;input[1:0] ty;input[6:0] nt;begin @(negedge clk);typ=ty;note=nt;ev=1;@(negedge clk);ev=0;repeat(2)@(negedge clk);end endtask
initial begin #100;rst=1;repeat(100)@(negedge clk);
if(pcm!==512'd0 || active!==0)$fatal(1,"idle not silent");
$display("PASS 32-voice engine idle is exact zero with known controls");
for(integer j=0;j<32;j=j+1)event_send(0,36+j);
repeat(6000)@(negedge clk);
if(active!==32'hffffffff)$fatal(1,"32 voices not allocated");
for(integer j=0;j<32;j=j+1)event_send(1,36+j);
repeat(180000)@(negedge clk);
if(active!==0 || pcm!==512'd0)$fatal(1,"release leak active=%h",active);
$display("PASS 32 NOTE_ON followed by 32 NOTE_OFF recovers all slots and silence");$finish;end

endmodule

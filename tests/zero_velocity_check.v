`timescale 1ns/1ps
module zero_velocity_check;
reg clk=0,rst=0,ev=0;always #5 clk=~clk;reg[6:0]vel=0;reg[1:0]div=0;always @(posedge clk)div<=div+1'b1;
wire[31:0]pcm;wire[1:0]active;
top_synth #(.N(2)) d(.clk(clk),.rst_n(rst),.sample_tick(div==3),.event_valid(ev),.event_type(2'd0),.event_num(7'd60),.event_vel(vel),.event_source(2'd2),.event_timbre(1'b0),.mode(1'b0),.bend(7'd64),.vib_off(23'd0),.pcm_out_v(pcm),.active_debug(active));
task send(input[6:0]v);begin @(negedge clk);vel=v;ev=1;@(negedge clk);ev=0;repeat(20)@(negedge clk);end endtask
initial begin #30;rst=1;send(0);if(active!==0)$fatal(1,"zero velocity allocated a silent slot");
send(100);repeat(25000)@(negedge clk);if(active!==1)$fatal(1,"test voice not sustaining");
send(0);repeat(48000)@(negedge clk);if(active!==0 || pcm!==0)$fatal(1,"zero-velocity ON did not release matching source/note");
$display("PASS zero-velocity NOTE_ON cannot leak silent slots and releases existing matching note");$finish;end
endmodule

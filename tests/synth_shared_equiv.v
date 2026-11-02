`timescale 1ns/1ps
module synth_shared_equiv;
reg clk=0,rst=0;always #5 clk=~clk;
reg[2:0]div=0;always @(posedge clk)div<=div+1'b1;wire tick=div==7;
reg valid=0,timbre=0;reg[1:0]typ=0,owner=0;reg[6:0]num=0,vel=90,bend=64;reg[22:0]vib=0;
wire[511:0]a,b;wire[31:0]aa,bb;
top_synth d(.clk(clk),.rst_n(rst),.sample_tick(tick),.event_valid(valid),.event_type(typ),.event_num(num),.event_vel(vel),.event_timbre(timbre),.event_source(owner),.mode(1'b0),.bend(bend),.vib_off(vib),.pcm_out_v(a),.active_debug(aa));
ap03_top_synth refd(.clk(clk),.rst_n(rst),.sample_tick(tick),.event_valid(valid),.event_type(typ),.event_num(num),.event_vel(vel),.event_timbre(timbre),.event_source(owner),.mode(1'b0),.bend(bend),.vib_off(vib),.pcm_out_v(b),.active_debug(bb));
integer comparisons=0,k,batch,samples=0;reg checking=0;
always @(negedge clk)if(rst && checking)begin
 if(a!==b || aa!==bb)$fatal(1,"AP03 audio/state mismatch sample%0d active%h/%h",samples,aa,bb);
 if(d.u_mgr.note_num_v!==refd.u_mgr.note_num_v || d.u_arr.ad_state_v!==refd.u_arr.ad_state_v)$fatal(1,"slot allocation/envelope changed");
 comparisons=comparisons+1;if(tick)samples=samples+1;
end
task samp;begin @(negedge clk);while(!tick)@(negedge clk);@(negedge clk);end endtask
task event_send;input[1:0]t,o;input[6:0]n,v;input ti;begin
 @(negedge clk);typ=t;owner=o;num=n;vel=v;timbre=ti;valid=1;
 @(negedge clk);valid=0;repeat(3)@(negedge clk);
end endtask
initial begin
 #30;rst=1;checking=1;
 for(batch=0;batch<4;batch=batch+1)begin
  @(negedge clk);checking=0;rst=0;valid=0;bend=64;vib=0;repeat(3)@(negedge clk);rst=1;checking=1;
  for(k=0;k<32;k=k+1)begin
   event_send(0,batch==0?2:k%4,batch*32+k,40+k,k%2);
   if(k%4==0)samp;
  end
  repeat(300)samp;
  event_send(0,batch==0?2:0,batch*32,0,0);
  for(k=0;k<128;k=k+1)begin
   bend=k;vib=(k%3==0)?23'd65536:(k%3==1)?-23'sd65536:23'd0;
   repeat(4)samp;
  end
  bend=64;vib=0;
  for(k=0;k<32;k=k+1)event_send(3,batch==0?2:k%4,batch*32+k,100-k,k%2);
  repeat(800)samp;
  for(k=0;k<16;k=k+1)event_send(1,batch==0?2:k%4,batch*32+k,0,0);
  event_send(2,0,0,0,0);repeat(4500)samp;
 end
 if(comparisons<10000)$fatal(1,"insufficient comparison");
 $display("PASS AP03 bit-exact32-slot PCM/masks/envelopes, all128 MIDI notes, owner/timbre variants, velocity updates, zero-velocity, all128 bend values, signed vibrato, release/ALL_OFF (%0d comparisons/%0d samples)",comparisons,samples);$finish;
end
initial begin #10000000;$fatal(1,"shared ROM equivalence timeout");end
endmodule

`timescale 1ns/1ps
module harp_bend;
reg clk=0,rst=0,ev=0,timbre=0;always #10 clk=~clk;
reg[1:0] source=0;reg[6:0] bend=64;reg[22:0] vib=0;
reg[3:0] div=0;always @(posedge clk)div<=div+1'b1;
top_synth #(.N(2)) d(.clk(clk),.rst_n(rst),.sample_tick(div==15),.event_valid(ev),
.event_type(2'd0),.event_num(7'd60),.event_vel(7'd100),.event_timbre(timbre),.event_source(source),
.mode(1'b0),.bend(bend),.vib_off(vib));
reg[31:0] p,h;
initial begin
 #100;rst=1;@(negedge clk);ev=1;@(negedge clk);ev=0;
 @(negedge clk);source=1;timbre=1;ev=1;@(negedge clk);ev=0;
 repeat(50)@(negedge clk);
 p=d.u_arr.g_voice[0].u_voice.freq_with_bend;h=d.u_arr.g_voice[1].u_voice.freq_with_bend;
 bend=127;#1;
 if(d.u_arr.g_voice[0].u_voice.freq_with_bend<=p || d.u_arr.g_voice[1].u_voice.freq_with_bend!==h)$fatal(1,"pressure bend reached harp");
 p=d.u_arr.g_voice[0].u_voice.freq_with_bend;vib=1234;#1;
 if(d.u_arr.g_voice[0].u_voice.freq_with_bend!==p+1234 || d.u_arr.g_voice[1].u_voice.freq_with_bend!==h+1234)$fatal(1,"vibrato missing a voice");
 $display("PASS pressure bends piano only; global vibrato reaches both timbres");$finish;
end
endmodule

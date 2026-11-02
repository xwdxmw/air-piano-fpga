`timescale 1ns/1ps
module flute_source_check;
reg clk=0,rst=0,ev=0,timbre=1;reg[1:0]typ=0,owner=0;
reg[1:0]div=0;always #5 clk=~clk;always @(posedge clk)div<=div+1'b1;wire tick=div==3;
wire[63:0]pcm;wire[3:0]active;
top_synth #(.N(4)) d(.clk(clk),.rst_n(rst),.sample_tick(tick),.event_valid(ev),.event_type(typ),
 .event_num(7'd60),.event_vel(7'd90),.event_source(owner),.event_timbre(timbre),.mode(1'b0),
 .bend(7'd64),.vib_off(23'd0),.pcm_out_v(pcm),.active_debug(active));
task send(input[1:0]t,input[1:0]s);begin @(negedge clk);owner=s;typ=t;ev=1;@(negedge clk);ev=0;repeat(12)@(negedge clk);end endtask
initial begin #30;rst=1;send(0,0);send(0,1);repeat(5000)@(negedge clk);
 if(active!==4'b0011 || d.flute_v!==4'b0001)$fatal(1,"keyboard flute and optical harp not separated");
 if(!d.u_arr.g_voice[0].u_voice.voice_flute || !d.u_arr.g_voice[1].u_voice.voice_harp)$fatal(1,"actual wave selector route wrong");
 send(1,1);repeat(140000)@(negedge clk);if(active!==4'b0001)$fatal(1,"IR OFF killed keyboard flute or harp leaked");
 send(1,0);repeat(24000)@(negedge clk);if(active!==0 || pcm!==0)$fatal(1,"flute owner OFF/slot recovery failed");
 // Source3 guide stays bell even if a malformed alternate flag is sent; actual guide sends0.
 timbre=0;send(0,3);repeat(500)@(negedge clk);if(d.flute_v!==0)$fatal(1,"guide became flute");
 send(2,0);repeat(50000)@(negedge clk);if(active!==0 || pcm!==0)$fatal(1,"mixed ALL_OFF failed");
 $display("PASS source0 flute/source1 unchanged harp, same-pitch owner-isolated OFF, guide bell and ALL_OFF recovery");$finish;
end
endmodule

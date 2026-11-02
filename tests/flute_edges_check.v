`timescale 1ns/1ps
module flute_edges_check;
reg clk=0,rst=0,on=0,off=0,vu=0,flute=1,timbre=1;
reg[6:0]vel=100,bend=64;reg[22:0]vib=0;
always #5 clk=~clk;reg[1:0]div=0;always @(posedge clk)div<=div+1'b1;wire tick=div==3;
wire[15:0]pcm;wire[2:0]state;integer n,heard,saved;
voice d(.clk(clk),.rst_n(rst),.sample_tick(tick),.note_on(on),.note_num(7'd60),.velocity(vel),
 .note_release(off),.vel_update(vu),.timbre_sel(timbre),.flute_sel(flute),.diagnostic(1'b0),
 .freq_update(1'b0),.new_freq(32'd0),.bend(bend),.vib_off(vib),.pcm_out(pcm),.ad_state(state));
task samp;begin @(negedge clk);while(!tick)@(negedge clk);@(negedge clk);end endtask
task start(input[6:0]v);begin vel=v;off=0;on=1;samp();on=0;end endtask
initial begin #30;rst=1;repeat(10)samp();if(pcm!==0 || state!=0)$fatal(1,"flute idle not silent");
 start(100);heard=0;
 for(n=0;n<80000;n=n+1)begin samp();if(^pcm===1'bx)$fatal(1,"undefined flute PCM");if(pcm!=0)heard=heard+1;end
 if(state!=3 || heard<70000)$fatal(1,"flute must sustain beyond 1.6s, state=%d heard=%d",state,heard);
 // Selector changes must never change a held note's latched instrument.
 flute=0;timbre=0;repeat(100)samp();if(!d.voice_flute || d.voice_harp)$fatal(1,"held flute changed with S1");
 bend=127;repeat(10)samp();if(d.freq_with_bend<=d.base_freq)$fatal(1,"S2 cannot bend flute");
 bend=64;vib=12345;repeat(10)samp();if(d.freq_with_bend!=d.base_freq+12345)$fatal(1,"flute vibrato missing");vib=0;
 // Velocity correction after sustain must converge in both directions.
 vel=24;vu=1;samp();vu=0;repeat(2000)samp();saved=d.env;
 if(saved<4900 || saved>5000)$fatal(1,"quiet sustain target not reached %d",saved);
 vel=115;vu=1;samp();vu=0;repeat(2000)samp();if(d.env<23700 || d.env>23800)$fatal(1,"loud sustain target not reached %d",d.env);
 off=1;repeat(6000)samp();if(state!=0 || pcm!==0)$fatal(1,"flute release did not reclaim");
 flute=1;timbre=1;start(1);repeat(1000)samp();if(state!=3)$fatal(1,"minimum velocity cannot sustain");
 off=1;repeat(1000)samp();if(state!=0 || pcm!==0)$fatal(1,"minimum velocity release stuck");
 start(127);repeat(1000)samp();off=1;repeat(40)samp();start(70);repeat(1000)samp();if(state!=3)$fatal(1,"retrigger during release lost");
 rst=0;#20;rst=1;repeat(20)samp();if(state!=0 || pcm!==0 || d.u_flute.wave!==0)$fatal(1,"warm reset leaked breath noise");
 $display("PASS flute long sustain, per-note selector latch, S2/vibrato, bidirectional velocity correction, min velocity, release/retrigger/reset silence");$finish;
end
endmodule

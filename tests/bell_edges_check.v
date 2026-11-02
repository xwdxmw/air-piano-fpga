`timescale 1ns/1ps
module bell_edges_check;
reg clk=0,rst=0,on=0,off=0,vu=0,timbre=0,diag=0;reg[6:0]vel=90;always #5 clk=~clk;
reg[1:0]div=0;always @(posedge clk)div<=div+1'b1;wire tick=div==3;
wire[15:0]pcm;wire[2:0]state;
reg heard=0;
always @(negedge clk)if(rst)begin if(^pcm===1'bx)$fatal(1,"undefined PCM");if(pcm!=0)heard=1;end
voice d(.flute_sel(1'b0),.clk(clk),.rst_n(rst),.sample_tick(tick),.note_on(on),.note_num(7'd60),.velocity(vel),.note_release(off),.vel_update(vu),.timbre_sel(timbre),.diagnostic(diag),.freq_update(1'b0),.new_freq(32'd0),.bend(7'd64),.vib_off(23'd0),.pcm_out(pcm),.ad_state(state));
task samp;begin @(negedge clk);while(!tick)@(negedge clk);@(negedge clk);end endtask
task start(input[6:0]v);begin vel=v;on=1;samp();on=0;end endtask
initial begin #30;rst=1;repeat(10)samp();if(pcm!==0 || state!=0)$fatal(1,"cold bell is not silent");
start(127);repeat(200)samp();if(!heard || !d.u_bell.alive || state==0)$fatal(1,"bell onset absent");
timbre=1;diag=1;repeat(200)samp();if(d.voice_timbre || d.voice_diagnostic)$fatal(1,"note timbre/diagnostic not latched");
timbre=0;diag=0;off=1;repeat(12000)samp();if(pcm!==0 || state!=0)$fatal(1,"bell release stuck");
off=0;start(1);repeat(20)samp();off=1;repeat(12000)samp();if(pcm!==0 || state!=0)$fatal(1,"quiet bell release stuck");
off=0;start(90);repeat(300000)samp();if(state!=0 || pcm!==0 || d.u_bell.alive)$fatal(1,"natural decay never reclaimed");
start(0);repeat(20)samp();if(pcm!==0 || state!=0)$fatal(1,"zero-velocity bell not silent");
start(100);repeat(20)samp();off=1;repeat(10)samp();off=0;start(60);repeat(100)samp();if(state==0)$fatal(1,"retrigger lost during release");
rst=0;#20;rst=1;repeat(10)samp();if(pcm!==0 || state!=0)$fatal(1,"warm reset bell residue");
$display("PASS bell cold/warm silence, onset, per-note timbre/diagnostic latch, release, low/zero velocity, natural auto-finish and retrigger");$finish;end
endmodule

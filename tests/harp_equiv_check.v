`timescale 1ns/1ps
`include "tests/voice_reference.v"
module harp_equiv_check;
reg clk=0,rst=0,on=0,off=0,vu=0,timbre=1;reg[6:0]note=60,vel=90,bend=64;reg[22:0]vib=0;
always #5 clk=~clk;reg[1:0]div=0;always @(posedge clk)div<=div+1'b1;wire tick=div==3;
wire[15:0]pcm,oldpcm;wire[2:0]state,oldstate;integer n;
voice d(.flute_sel(1'b0),.clk(clk),.rst_n(rst),.sample_tick(tick),.note_on(on),.note_num(note),.velocity(vel),.note_release(off),.vel_update(vu),.timbre_sel(timbre),.diagnostic(1'b0),.freq_update(1'b0),.new_freq(32'd0),.bend(bend),.vib_off(vib),.pcm_out(pcm),.ad_state(state));
voice_reference old(.clk(clk),.rst_n(rst),.sample_tick(tick),.note_on(on),.note_num(note),.velocity(vel),.note_release(off),.vel_update(vu),.timbre_sel(timbre),.freq_update(1'b0),.new_freq(32'd0),.bend(bend),.vib_off(vib),.pcm_out(oldpcm),.ad_state(oldstate));
always @(negedge clk)if(rst && (pcm!==oldpcm || state!==oldstate))$fatal(1,"harp differs from r5l PCM/state");
task samp;begin @(negedge clk);while(!tick)@(negedge clk);@(negedge clk);end endtask
initial begin #30;rst=1;on=1;samp();on=0;
for(n=0;n<60000;n=n+1)begin
 case(n)
 100:begin vu=1;vel=24;end 101:vu=0;
 500:begin bend=127;vib=1234;end
 1000:off=1;
 3000:begin off=0;on=1;note=72;vel=127;end 3001:on=0;
 12000:begin on=1;note=36;vel=1;end 12001:on=0;
 22000:begin on=1;note=96;vel=100;end 22001:on=0;
 endcase
 samp();
end
if(pcm!==0 || oldpcm!==0)$fatal(1,"harp final silence");
$display("PASS 60000 samples harp is bit-for-bit identical to r5l across notes,velocity update,bend immunity,vibrato,retrigger and natural release");$finish;end
endmodule

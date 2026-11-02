`timescale 1ns/1ps
module voice_edges;
reg clk=0,rst=0,on=0,off=0,vu=0,timbre=0;reg[6:0]vel=1;always #10 clk=~clk;
reg[2:0]div=0;always @(posedge clk)div<=div+1'b1;wire tick=(div==7);
wire[15:0]pcm;wire[2:0]state;
voice d(.flute_sel(1'b0),.diagnostic(1'b1),.clk(clk),.rst_n(rst),.sample_tick(tick),.note_on(on),.note_num(7'd60),.velocity(vel),.note_release(off),.vel_update(vu),.timbre_sel(timbre),.freq_update(1'b0),.new_freq(32'd0),.bend(7'd64),.vib_off(23'd0),.pcm_out(pcm),.ad_state(state));
task samp;begin @(negedge clk);while(!tick)@(negedge clk);@(negedge clk);end endtask
task start;input tb;input[6:0]v;begin timbre=tb;vel=v;on=1;samp();on=0;end endtask
initial begin
 #100;rst=1;start(1,1);timbre=0;
 repeat(20000)samp();if(state!=0 || d.env!=0)$fatal(1,"low-velocity harp or timbre latch stuck");
 start(0,127);repeat(200)samp();vel=24;vu=1;samp();vu=0;
 repeat(5000)samp();if(d.env>d.peak || state!=3)$fatal(1,"velocity reduction underflow/overflow");
 off=1;repeat(6000)samp();if(state!=0 || pcm!==0)$fatal(1,"piano release not zero");
 off=0;start(0,100);repeat(40)samp();off=1;repeat(10)samp();off=0;start(1,90);repeat(20000)samp();
 if(state!=0)$fatal(1,"retrigger lost during old release");
 $display("PASS low velocity >=1 step, latched timbre, velocity decrease, clean release and retrigger priority");$finish;
end
endmodule

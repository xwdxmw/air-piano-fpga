`timescale 1ns/1ps
module pitch_ratio_check;
reg clk=0,rst=0;always #5 clk=~clk;reg[6:0]bend=64;reg[22:0]vib=0;wire[15:0]pcm;
voice d(.flute_sel(1'b0),.diagnostic(1'b1),.clk(clk),.rst_n(rst),.sample_tick(1'b1),.note_on(1'b0),.note_num(7'd60),.velocity(7'd100),.note_release(1'b0),.vel_update(1'b0),.timbre_sel(1'b0),.freq_update(1'b0),.new_freq(32'd0),.bend(bend),.vib_off(vib),.pcm_out(pcm),.ad_state());
reg[31:0]low,high;integer i;
initial begin #30;rst=1;@(negedge clk);force d.base_freq=32'd20000000;
 bend=127;#1;low=d.freq_with_bend;force d.base_freq=32'd40000000;#1;high=d.freq_with_bend;
 if(high<2*low-2 || high>2*low+2)$fatal(1,"bend cents vary by octave");
 force d.base_freq=32'd1;bend=0;vib=-23'sd240000;#1;if(d.freq_with_bend!=1)$fatal(1,"negative frequency wrapped");
 force d.base_freq=32'hffffffff;bend=127;vib=0;#1;if(d.freq_with_bend!=32'h73333333)$fatal(1,"upper frequency wrapped");
 $display("PASS proportional pitch bend, octave-invariant ratio and low/high clamps");$finish;end
endmodule

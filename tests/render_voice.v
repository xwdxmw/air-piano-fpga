`timescale 1ns/1ps
// Isolated HDL voice audition, accelerated master clock / sample cadence.
// WAV conversion uses the real hardware sample rate, not simulation wall time.
module render_voice;
reg clk=0,rst=0,on=0,off=0,timbre=0;always #10 clk=~clk;
reg[1:0]div=0;always @(posedge clk)div<=div+1'b1;wire tick=div==3;
wire[15:0]pcm;
voice d(.flute_sel(1'b0),.diagnostic(1'b1),.clk(clk),.rst_n(rst),.sample_tick(tick),.note_on(on),.note_num(7'd60),.velocity(7'd90),
 .note_release(off),.vel_update(1'b0),.timbre_sel(timbre),.freq_update(1'b0),.new_freq(32'd0),
 .bend(7'd64),.vib_off(23'd0),.pcm_out(pcm),.ad_state());
integer f,i;
initial begin
 f=$fopen("tests/results/render_voice.txt","w");#100;rst=1;
 for(i=0;i<210791;i=i+1)begin
  @(negedge clk);while(!tick)@(negedge clk);
  on=(i==7186 || i==105395);if(i==35930)off=1;
  if(i==105395)begin timbre=1;off=0;end
  @(posedge clk);#1;
  if(^pcm===1'bx)$fatal(1,"undefined PCM in audition");
  $fwrite(f,"%0d\n",$signed(pcm));
 end
 $fclose(f);$display("PASS rendered isolated HDL C4 piano then harp, no echo/mixer");$finish;
end
endmodule

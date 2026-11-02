`timescale 1ns/1ps
// Accelerated sample enables; WAV is encoded at the actual FPGA sample rate.
// No recorded audio is an RTL input. Output is generated sample-by-sample.
module bell_render;
reg clk=0,rst=0,on=0,off=0,timbre=0;reg[6:0]note=60;always #5 clk=~clk;
reg[1:0]div=0;always @(posedge clk)div<=div+1'b1;wire tick=div==3;
wire[15:0]pcm;
voice d(.flute_sel(1'b0),.clk(clk),.rst_n(rst),.sample_tick(tick),.note_on(on),.note_num(note),.velocity(7'd90),.note_release(off),.vel_update(1'b0),.timbre_sel(timbre),.diagnostic(1'b0),.freq_update(1'b0),.new_freq(32'd0),.bend(7'd64),.vib_off(23'd0),.pcm_out(pcm),.ad_state());
integer out,n,c;reg nonzero;
task samp;begin @(negedge clk);while(!tick)@(negedge clk);@(negedge clk);end endtask
initial begin
out=$fopen("tests/results/bell_render.csv","w");$fwrite(out,"clip,sample,pcm\n");
#30;rst=1;
for(c=0;c<4;c=c+1)begin
 rst=0;#20;rst=1;timbre=c%2;note=c<2?60:72;off=0;on=1;samp();on=0;nonzero=0;
 for(n=0;n<67070;n=n+1)begin
  if(n==38325)off=1;
  samp();$fwrite(out,"%0d,%0d,%0d\n",c,n,$signed(pcm));if(pcm!=0)nonzero=1;
  if(^pcm===1'bx)$fatal(1,"undefined PCM in clip%0d sample%0d",c,n);
 end
 if(!nonzero)$fatal(1,"silent tone clip %0d",c);
end
$fclose(out);$display("PASS generated actual RTL C4/C5 bell-versus-harp dry PCM clips, velocity90; 0.8s gate/0.6s release");$finish;end
endmodule

`timescale 1ns/1ps
module flute_render;
reg clk=0,rst=0,on=0,off=0,timbre=0,flute=0;reg[6:0]note=60;always #5 clk=~clk;
reg[1:0]div=0;always @(posedge clk)div<=div+1'b1;wire tick=div==3;
wire[15:0]pcm;integer out,n,c;reg heard;
voice d(.clk(clk),.rst_n(rst),.sample_tick(tick),.note_on(on),.note_num(note),.velocity(7'd90),
 .note_release(off),.vel_update(1'b0),.timbre_sel(timbre),.flute_sel(flute),.diagnostic(1'b0),
 .freq_update(1'b0),.new_freq(32'd0),.bend(7'd64),.vib_off(23'd0),.pcm_out(pcm),.ad_state());
task samp;begin @(negedge clk);while(!tick)@(negedge clk);@(negedge clk);end endtask
initial begin out=$fopen("tests/results/flute_render.csv","w");$fwrite(out,"clip,sample,pcm\n");#30;rst=1;
 for(c=0;c<6;c=c+1)begin
  rst=0;#20;rst=1;note=c<3?60:72;timbre=(c%3)!=0;flute=(c%3)==1;off=0;on=1;samp();on=0;heard=0;
  for(n=0;n<67070;n=n+1)begin
   if(n==38325)off=1;
   samp();$fwrite(out,"%0d,%0d,%0d\n",c,n,$signed(pcm));if(pcm!=0)heard=1;
   if(^pcm===1'bx)$fatal(1,"undefined rendered PCM");
  end
  if(!heard)$fatal(1,"silent rendered clip%d",c);
 end
 $fclose(out);$display("PASS actual RTL bell/flute/harp C4+C5, velocity90 0.8s gate/0.6s release");$finish;
end
endmodule

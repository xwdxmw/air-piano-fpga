`timescale 1ns/1ps
module spectrum_check;
reg ca=0,cd=0,ra=0,rd=0,tick=0,req=0;always #5 ca=~ca;always #7 cd=~cd;
reg signed[15:0]pcm=0;wire[79:0]bars;wire ready;
spectrum16 d(.clk_a(ca),.rst_a(ra),.sample_tick(tick),.pcm(pcm),.clk_d(cd),.rst_d(rd),.capture_req(req),.bars(bars),.ready(ready));
integer n,i,peak,peakvalue;reg[79:0]frozen;real s;
task sample(input integer v);begin
 @(negedge ca);if(d.state!=0)$fatal(1,"analyzer exceeded 256clk sample budget");pcm=v;tick=1;
 @(negedge ca);tick=0;repeat(254)@(negedge ca);
end endtask
task snap;begin @(negedge cd);req=1;@(negedge cd);req=0;wait(!ready);wait(ready);@(negedge cd);end endtask
initial begin
 #30;ra=1;rd=1;
 repeat(512)sample(0);snap();if(bars!==0)$fatal(1,"spectrum nonzero after silent frame");
 for(n=0;n<512;n=n+1)begin s=12000*$sin(6.283185307179586*8*n/512.0);sample($rtoi(s));end
 snap();peak=0;peakvalue=0;
 for(i=0;i<16;i=i+1)if(bars[i*5+:5]>peakvalue)begin peakvalue=bars[i*5+:5];peak=i;end
 if(peak!=6 || peakvalue<10)$fatal(1,"wrong strongest bin for bin8 tone: index%0d value%0d",peak,peakvalue);
 frozen=bars;
 repeat(512)sample(0);repeat(20)@(negedge cd);
 if(bars!==frozen)$fatal(1,"snapshot changed without acknowledged request");
 snap();if(bars!==0)$fatal(1,"silence frame not replacing old spectrum");
 for(n=0;n<512;n=n+1)begin s=6000*$sin(6.283185307179586*8*n/512.0)+6000*$sin(6.283185307179586*48*n/512.0);sample($rtoi(s));end
 snap();if(bars[6*5+:5]<10 || bars[12*5+:5]<10)$fatal(1,"missing two independent spectral components");
 $display("PASS actual PCM spectrum: silence/single/two tones, correct frequency bins, full-rate budget, asynchronous immutable snapshot");$finish;
end
initial begin #12000000;$fatal(1,"spectrum timeout");end
endmodule

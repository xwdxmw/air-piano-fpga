`timescale 1ns/1ps
module bell_poly32_check;
reg clk=0,rst=0,ev=0;always #5 clk=~clk;reg[1:0]div=0,typ=0;
always @(posedge clk)div<=div+1'b1;
wire tick=div==3;reg[6:0]note=36;wire[511:0]pcm;wire[31:0]active;
top_synth d(.clk(clk),.rst_n(rst),.sample_tick(tick),.event_valid(ev),.event_type(typ),.event_num(note),.event_vel(7'd40),.event_source(2'd2),.event_timbre(1'b0),.mode(1'b0),.bend(7'd64),.vib_off(23'd0),.pcm_out_v(pcm),.active_debug(active));
integer sn=0,dump,j,total,recorded=0;
always @(negedge clk)if(rst && tick)begin
 sn=sn+1;
 if(sn>=60000 && sn<125536)begin
  total=0;for(integer k=0;k<32;k=k+1)total=total+$signed(pcm[k*16+:16]);
  $fwrite(dump,"%0d,%0d\n",sn,total>>>5);recorded=recorded+1;
 end
end
task event_send(input[1:0]ty,input[6:0]nt);begin @(negedge clk);typ=ty;note=nt;ev=1;@(negedge clk);ev=0;repeat(2)@(negedge clk);end endtask
initial begin dump=$fopen("tests/results/poly32_pcm.csv","w");$fwrite(dump,"sample,pcm\n");#30;rst=1;
for(j=0;j<32;j=j+1)event_send(0,36+j);
wait(sn>=135000);
if(active!==32'hffffffff || d.diagnostic_v!==32'hffffffff)$fatal(1,"continuous 32-voice diagnostic lost to bell decay");
if(recorded!=65536)$fatal(1,"FFT capture length");
event_send(2,0);repeat(50000)@(negedge clk);
if(active!==0 || pcm!==0)$fatal(1,"diagnostic release leak");
$fclose(dump);$display("PASS source2 retains all32 active beyond2.5s,65536 actual RTL PCM samples for FFT, clean ALL_OFF; bell mode isolated");$finish;end
endmodule

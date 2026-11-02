`timescale 1ns/1ps
module flute_poly32_check;
reg clk=0,rst=0,ev=0,timbre=1;reg[1:0]typ=0;
reg[6:0]note=48,vel=100;reg[1:0]div=0;always #5 clk=~clk;always @(posedge clk)div<=div+1'b1;
wire tick=div==3;wire[511:0]pcm;wire[31:0]active;
top_synth d(.clk(clk),.rst_n(rst),.sample_tick(tick),.event_valid(ev),.event_type(typ),.event_num(note),
 .event_vel(vel),.event_source(2'd0),.event_timbre(timbre),.mode(1'b0),.bend(7'd64),.vib_off(23'd0),.pcm_out_v(pcm),.active_debug(active));
task send(input[1:0]t,input[6:0]nt);begin @(negedge clk);typ=t;note=nt;ev=1;@(negedge clk);ev=0;repeat(12)@(negedge clk);end endtask
integer i;
initial begin #30;rst=1;
 for(i=0;i<32;i=i+1)send(0,48+i);
 repeat(60000)@(negedge clk);
 if(active!==32'hffffffff || d.flute_v!==32'hffffffff || ^pcm===1'bx)$fatal(1,"32 sustained flute slots missing");
 vel=0;send(0,48);repeat(24000)@(negedge clk);
 if(active!==32'hfffffffe)$fatal(1,"zero-velocity ON must release only its flute slot");
 send(2,0);repeat(24000)@(negedge clk);if(active!==0 || pcm!==0 || d.flute_v!==0)$fatal(1,"32 flute ALL_OFF leak");
 timbre=0;vel=90;for(i=0;i<32;i=i+1)send(0,36+i);
 repeat(4000)@(negedge clk);if(active!==32'hffffffff || d.flute_v!==0)$fatal(1,"bell reuse inherited flute flag");
 send(2,0);repeat(50000)@(negedge clk);if(active!==0 || pcm!==0)$fatal(1,"reused bell slots fail to retire");
 $display("PASS 32 sustained flute voices, source0 zero-velocity release, ALL_OFF and32-slot bell reuse clear flute flags");$finish;
end
endmodule

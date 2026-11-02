`timescale 1ns/1ps
module guide_sync;
reg clk=0,rst=0;always #10 clk=~clk;
top_system d(.key_bend_n(1'b1),.key_timbre_n(1'b1),.clk_50m(clk),.rst_n(rst),.touch_raw(1'b0),.sensor_gpio(8'hff),.ads_miso(1'b0),.ads_drdy(1'b1),.calib_run_p(1'b0),.calib_run_o(1'b0),.calib_clear(1'b0));
// Scale only the musical timebase. Keep CDC, synth, and LED mapping real.
defparam d.u_guide.CLK_FREQ_HZ=50000;
reg[6:0]song[0:13];reg[2:0]keys[0:13];integer ons=0,offs=0,aons=0,aoffs=0,ticks=0,last_on=0,last_off=0;reg req_old=0;reg heard=0;
always @(posedge clk)ticks=ticks+1;
always @(negedge clk)if(rst)begin
 if(d.g_on)begin
  if(ons>=14 || d.g_num!==song[ons] || d.g_key!==keys[ons])$fatal(1,"wrong song/key %0d",ons);
  if(!d.g_led || d.led_grb[d.g_key*24+:24]!==24'h000018)$fatal(1,"light missing at note-on");
  if(ons>0 && ticks-last_off<2500)$fatal(1,"missing shared 50ms gap");
  last_on=ticks;ons=ons+1;
 end
 if(d.g_off)begin
  if(d.g_offnum!==song[offs] || d.g_led || d.led_grb[d.g_key*24+:24]!==0)$fatal(1,"release/light mismatch");
  if(ticks-last_on<12500 || ticks-last_on>27510)$fatal(1,"note gate duration");
  last_off=ticks;offs=offs+1;
 end
 if(d.g_led !== d.g_guide)$fatal(1,"free-running light phase");
end
always @(posedge d.u_board.clk_12m288)if(rst)begin
 if(d.u_board.req2 && !req_old)begin
  if(d.u_board.ev_source!==3)$fatal(1,"guide owner");
  if(d.u_board.ev_type==0)begin if(d.u_board.ev_num!==song[aons])$fatal(1,"audio ON order");aons=aons+1;end
  if(d.u_board.ev_type==1)begin if(d.u_board.ev_num!==song[aoffs])$fatal(1,"audio OFF order");aoffs=aoffs+1;end
 end
 req_old=d.u_board.req2;
 if(d.u_board.pcm_mon_o!==16'd0 && (^d.u_board.pcm_mon_o)!==1'bx)heard=1;
end
initial begin
 song[0]=60;song[1]=60;song[2]=67;song[3]=67;song[4]=69;song[5]=69;song[6]=67;song[7]=65;song[8]=65;song[9]=64;song[10]=64;song[11]=62;song[12]=62;song[13]=60;
 keys[0]=0;keys[1]=0;keys[2]=4;keys[3]=4;keys[4]=5;keys[5]=5;keys[6]=4;keys[7]=3;keys[8]=3;keys[9]=2;keys[10]=2;keys[11]=1;keys[12]=1;keys[13]=0;
 #100;rst=1;force d.boot_done=1;force d.guide_latched=1;force d.test_latched=0;
 wait(d.g_on);repeat(10)@(negedge clk);force d.key_on_debug=8'h01;repeat(5)@(negedge clk);
 if(!d.g_hit || d.led_grb[23:0]!==24'h300000)$fatal(1,"correct key not green");
 release d.key_on_debug;
 wait(aoffs==14);repeat(20)@(negedge clk);
 if(ons!=14 || offs!=14 || aons!=14 || !heard || d.dropped)$fatal(1,"guide/audio lost %0d/%0d/%0d heard%0d",ons,offs,aons,heard);
 $display("PASS full 14-note Twinkle, matching key/light and audio CDC events, repeated-note gaps, green hit, nonzero PCM without ADC");$finish;
end
initial begin #9000000;$fatal(1,"guide sync timeout");end
endmodule

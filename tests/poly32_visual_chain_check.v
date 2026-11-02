`timescale 1ns/1ps
module poly32_visual_chain_check;
// Functional ordering test: fast display clock/sample enables reduce simulation
// time. Real50MHz serial timing is covered by lcd_poly32_check/lcd_protocol.
reg clk=0,rst=0;always #1 clk=~clk;
top_system #(.USE_POLY32(1),.BOOT_SEL_MS(1)) d(.clk_50m(clk),.rst_n(rst),.sensor_gpio(8'hff),.touch_raw(1'b0),
 .key_bend_n(1'b1),.key_timbre_n(1'b1),.ads_miso(1'b0),.ads_drdy(1'b1),.calib_run_p(1'b0),.calib_run_o(1'b0),.calib_clear(1'b0));
defparam d.u_boot.CLK_HZ=1000;
// Accelerate only musical timing and display throughput; no engine/active forces.
defparam d.u_poly32.WAIT_CLKS=10000,d.u_poly32.SLOT_CLKS=1000,d.u_poly32.HOLD_CLKS=1000000,d.u_poly32.GAP_CLKS=5000000;
defparam d.u_lcd.DLY_120=60,d.u_lcd.DLY_20=10,d.u_lcd.CAP_WAIT=600000,d.u_lcd.FRAME_GAP=20;
defparam d.u_lcd.SCLK_DIV=2,d.u_lcd.u_scope.DEC=1,d.u_lcd.u_scope.TRIGGER_SAMPLES=1;
reg seen32=0,seen0=0;integer captures=0;reg[31:0]taken;
reg[3:0]fast_div=0;always @(posedge d.audio_clk_w)fast_div<=fast_div+1'b1;
wire fast_tick=(fast_div==15);
always @(posedge d.audio_clk_w)if(d.audio_rst_w && d.u_lcd.u_voices.alive && d.u_lcd.u_voices.req_sync && !d.u_lcd.u_voices.ack)begin
 taken=d.u_board.active_debug;#1;
 if(d.u_lcd.u_voices.held!==taken)$fatal(1,"display sampled something other than actual engine activity");
 captures=captures+1;$display("INFO real engine snapshot mask=%h time=%t",taken,$time);$fflush();
end
always @(negedge clk)if(rst && d.u_lcd.st==5 && d.u_lcd.frame_voice_valid)begin
 if(d.u_lcd.frame_voice_count==32)begin
  if(d.u_lcd.frame_voices!==32'hffffffff)$fatal(1,"fake32 count");seen32=1;
 end
 if(seen32 && d.u_lcd.frame_voice_count==0 && d.u_lcd.frame_voices==0)seen0=1;
 if(seen32 && seen0)begin $display("PASS real poly32_seq -> event queue/CDC ->32 actual synthesis slots -> coherent LCD32/32 frame -> ALL_OFF -> LCD0/32; no forced active mask");$finish;end
end
// Minimum legal event velocity shortens release; not an audibility/latency test.
initial begin force d.u_board.sample_tick=fast_tick;force d.u_poly32.velocity=7'd1;#100;rst=1;end
initial begin #50000000;$fatal(1,"actual poly32/LCD chain timeout seen32%b seen0%b captures%d",seen32,seen0,captures);end
endmodule

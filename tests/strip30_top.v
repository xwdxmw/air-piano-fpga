`timescale 1ns/1ps
module strip30_top;
reg clk=0,rst=0;always #10 clk=~clk;wire dout;
top_system d(.key_bend_n(1'b1),.key_timbre_n(1'b1),.clk_50m(clk),.rst_n(rst),.touch_raw(1'b0),.sensor_gpio(8'hff),.ads_miso(1'b0),.ads_drdy(1'b1),.calib_run_p(1'b0),.calib_run_o(1'b0),.calib_clear(1'b0),.ws2812(dout));
// Audio algorithms have independent tests; keep the actual top-level LED path.
defparam d.u_board.USE_ENGINE=0,d.u_led_selftest.STEP_MS=1;
time rise_at=0;integer bits=0,frames=0;reg[719:0]data=0;reg seen_lit=0;
always @(posedge dout)if(rst)rise_at=$time;
always @(negedge dout)if(rst && rise_at!=0)begin
 if($time-rise_at!=320 && $time-rise_at!=800)$fatal(1,"invalid pulse");
 data[(bits/24)*24+23-bits%24]=($time-rise_at==800);bits=bits+1;
 if(bits==720)begin
  if(data[719:192]!==0)$fatal(1,"physical pixels 9..30 not black");
  if(data[191:0]!=0)seen_lit=1;
  frames=frames+1;bits=0;data=0;
  if(frames==2)begin if(!seen_lit)$fatal(1,"first eight missing selftest colors");$display("PASS actual top emits30-pixel720-bit frames,first8active,last22black across2frames");$finish;end
 end
end
initial begin #100;rst=1;end
initial begin #20000000;$fatal(1,"30-pixel top timeout bits%0d frames%0d",bits,frames);end
endmodule

`timescale 1ns/1ps
module normal_led_wire;
reg clk=0,rst=0;always #10 clk=~clk;
reg[7:0] fsr_mask=0,ir_mask=0;
reg cv=0;reg[2:0]ci=0;reg[11:0]cd=100;
wire dout;
top_system d(.clk_50m(clk),.rst_n(rst),.sensor_gpio(~ir_mask),.touch_raw(1'b0),
 .key_bend_n(1'b1),.key_timbre_n(1'b1),.ads_miso(1'b0),.ads_drdy(1'b1),
 .calib_run_p(1'b0),.calib_run_o(1'b0),.calib_clear(1'b0),.ws2812(dout));
// Keep pressure-zero, pressure-key, IR debounce, top mux and actual serializer.
// Inject valid ADC samples at its output boundary; this is not an ADS analog model.
defparam d.u_board.USE_ENGINE=0,d.u_interact.u_zero.SAMPLES=2;
defparam d.u_led_selftest.STEP_MS=1,d.u_ws.FRAME_US=300;
`ifdef NEW_LED_FOLLOW
defparam d.u_live_led.HOLD_MS=2;
localparam[23:0] FSR_COLOR=24'h100010,IR_COLOR=24'h101000,BOTH_COLOR=24'h101010;
`else
localparam[23:0] FSR_COLOR=24'h080008,IR_COLOR=24'h101000,BOTH_COLOR=24'h101010;
`endif
initial begin
 force d.ads_ch_valid=cv;force d.ads_ch_idx=ci;force d.ads_ch_data=cd;
 force d.boot_done=1;force d.test_latched=0;force d.guide_latched=0;
 forever begin
  @(negedge clk);cv=1;cd=fsr_mask[ci]?800:100;
  @(negedge clk);cv=0;ci=ci+1'b1;
  repeat(8)@(negedge clk);
 end
end
integer phase=0,frames=0,checked[0:7];time phase_at=0,rise_at=0;
integer bits=0,i;reg[719:0] decoded=0;reg[23:0] want;
always @(posedge dout)if(rst)rise_at=$time;
always @(negedge dout)if(rst && rise_at!=0)begin
 if($time-rise_at!=320 && $time-rise_at!=800)$fatal(1,"invalid WS pulse");
 decoded[(bits/24)*24+23-bits%24]=($time-rise_at==800);bits=bits+1;
 if(bits==720)begin
  if(decoded[719:192]!==0)$fatal(1,"pixels9..30 must remain black");
  if(phase>0 && $time-phase_at>4000000)begin
   for(i=0;i<8;i=i+1)begin
    want=0;
    if(phase!=7)begin
     if(fsr_mask[i] && ir_mask[i])want=BOTH_COLOR;
     else if(fsr_mask[i])want=FSR_COLOR;
     else if(ir_mask[i])want=IR_COLOR;
    end
    if(decoded[i*24+:24]!==want)$fatal(1,"phase%0d LED%0d got%h expected%h keys%h IR%h",phase,i+1,decoded[i*24+:24],want,d.key_on_debug,d.string_blocked);
   end
   checked[phase]=checked[phase]+1;
  end
  bits=0;decoded=0;frames=frames+1;
 end
end
task step;input integer p;input[7:0]f,b;
begin
 @(negedge clk);phase=p;phase_at=$time;fsr_mask=f;ir_mask=b;
 #6500000;
 if(checked[p]<1)$fatal(1,"phase%0d not checked",p);
 $display("PASS phase%0d actual30pixel WS wire FSR%h IR%h",p,f,b);
end endtask
initial begin
 for(i=0;i<8;i=i+1)checked[i]=0;
 #100;rst=1;
 #13000000;
 step(1,0,0);step(2,8'ha5,0);step(3,0,0);
 step(4,0,8'h3c);step(5,0,0);step(6,8'h81,8'h99);
 force d.test_latched=1;step(7,0,8'hff);
 $display("PASS normal following: ADC->FSR, raw IR->debounce, overlap, releases, T mute, 30pixel serialization (%0d frames)",frames);$finish;
end
initial begin #70000000;$fatal(1,"normal LED integration timeout");end
endmodule

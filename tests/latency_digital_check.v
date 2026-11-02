`timescale 1ns/1ps
// Digital boundary check only: DOES NOT include ADS analog conversion/scan or DAC analog response.
module latency_digital_check;
reg clk=0,rst=0;always #10 clk=~clk;reg[7:0]ir=8'hff;
reg cv=0;reg[11:0]cd=100;
top_system d(.clk_50m(clk),.rst_n(rst),.touch_raw(1'b0),.key_bend_n(1'b1),.key_timbre_n(1'b1),.sensor_gpio(ir),.ads_miso(1'b0),.ads_drdy(1'b1),.calib_run_p(1'b0),.calib_run_o(1'b0),.calib_clear(1'b0));
time start_at;integer i;
task inject(input[11:0]v);begin @(negedge clk);cd=v;cv=1;@(negedge clk);cv=0;repeat(3)@(negedge clk);end endtask
task reset;begin rst=0;repeat(8)@(negedge clk);rst=1;repeat(8)@(negedge clk);end endtask
initial begin
 #100;reset();force d.boot_done=1;
 force d.ads_ch_valid=cv;force d.ads_ch_idx=3'd0;force d.ads_ch_data=cd;
 repeat(64)inject(100);repeat(20)@(negedge clk);
 start_at=$time;inject(700);wait($signed(d.pcm_mon_w)!=0);
 if($time-start_at>1000000)$fatal(1,"pressure digital path exceeds 1ms");
 $display("INFO valid ADC sample -> first nonzero final PCM = %0d ns (excludes conversion/scan and analog DAC)",$time-start_at);
 reset();repeat(50)@(negedge clk);start_at=$time;ir=8'hfe;wait($signed(d.pcm_mon_w)!=0);
 if($time-start_at>1000000)$fatal(1,"IR digital path exceeds 1ms");
 $display("INFO IR DO edge -> first nonzero final PCM = %0d ns (excludes sensor and analog DAC)",$time-start_at);
 $display("PASS bounded digital paths only; board end-to-end latency and jitter still require measurement");$finish;
end
initial begin #3000000;$fatal(1,"digital latency timeout");end
endmodule

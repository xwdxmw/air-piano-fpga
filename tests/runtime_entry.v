`timescale 1ns/1ps
module runtime_entry;
reg clk=0,rst=0,touch=0;always #10 clk=~clk;
top_system d(.key_bend_n(1'b1),.key_timbre_n(1'b1),.clk_50m(clk),.rst_n(rst),.touch_raw(touch),.sensor_gpio(8'hff),.ads_miso(1'b0),.ads_drdy(1'b1),.calib_run_p(1'b0),.calib_run_o(1'b0),.calib_clear(1'b0));
defparam d.u_boot.CLK_HZ=1000,d.u_touch_db.DB_CNT=2,d.u_ttp.CLK_HZ=1000,d.u_guide.CLK_FREQ_HZ=1000,d.u_led_selftest.CLK_HZ=1000,d.u_led_selftest.STEP_MS=5;
integer toggles=0;always @(negedge clk)if(d.guide_toggle)toggles=toggles+1;
task waitn(input integer n);begin repeat(n)@(negedge clk);end endtask
initial begin
 #100;rst=1;wait(d.boot_done);waitn(30);
 if(d.test_mode || d.guide_mode)$fatal(1,"untouched cold startup");
 // TTP failed to report a press at boot sample: runtime retry must work.
 touch=1;waitn(720);if(d.octave!=0)$fatal(1,"octave changed before release/long-mode decision");touch=0;waitn(30);
 if(d.octave!=-1)$fatal(1,"short long press did not lower octave");
 touch=1;waitn(3300);touch=0;waitn(30);
 if(!d.guide_mode || d.test_mode || d.octave!=-1 || toggles!=1)$fatal(1,"runtime guide entry");
 wait(d.g_on);waitn(10);
 touch=1;waitn(8000);touch=0;waitn(350);
 if(d.guide_mode || d.octave!=-1 || toggles!=2)$fatal(1,"mode repeated or altered pitch");
 // Legacy warm reset into poly32; every TTP gesture must leave test locked.
 rst=0;touch=1;waitn(5);rst=1;waitn(700);touch=0;wait(d.boot_done);waitn(30);
 if(!d.test_mode || d.guide_mode)$fatal(1,"legacy test entry");
 touch=1;waitn(40);touch=0;waitn(350);if(d.vibrato || d.octave!=0)$fatal(1,"pitch gestures enabled in test mode");
 touch=1;waitn(3300);touch=0;waitn(30);
 if(d.guide_mode || !d.test_mode || d.octave!=0 || toggles!=2)$fatal(1,"32-note test must ignore long TTP hold");
 rst=0;touch=0;waitn(5);rst=1;wait(d.boot_done);waitn(30);
 if(d.guide_mode || d.test_mode)$fatal(1,"reset did not leave locked test");
 touch=1;waitn(3300);touch=0;waitn(30);if(!d.guide_mode || toggles!=3)$fatal(1,"normal-mode guide entry after reset");
 $display("PASS raw TTP -> debounce -> runtime entry/exit, delayed cold touch, release octave, 8s one-shot hold, poly32 stays locked until reset; no forced mode wires");$finish;
end
initial begin #1500000;$fatal(1,"runtime entry timeout");end
endmodule

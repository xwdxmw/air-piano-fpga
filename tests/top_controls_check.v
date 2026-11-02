`timescale 1ns/1ps
module top_controls_check;
reg clk=0,rst=0,tn=1,bn=1;always #10 clk=~clk;
top_system d(.clk_50m(clk),.rst_n(rst),.touch_raw(1'b0),.key_bend_n(bn),.key_timbre_n(tn),.sensor_gpio(8'hff),.ads_miso(1'b0),.ads_drdy(1'b1),.calib_run_p(1'b0),.calib_run_o(1'b0),.calib_clear(1'b0));
defparam d.u_boot.CLK_HZ=1000,d.u_controls.CLK_HZ=1000,d.u_controls.DB_MS=2,d.u_controls.ARM_MS=5;
task waitn(input integer n);begin repeat(n)@(negedge clk);end endtask
task note;begin force d.sw_on=1;@(negedge clk);force d.sw_on=0;waitn(10000);end endtask
initial begin #100;rst=1;wait(d.boot_done);waitn(40);
 force d.sw_num=60;force d.sw_vel=100;force d.sw_timbre=0;
 note();if(!d.u_board.g_engine.u_synth.u_mgr.active[0] || d.u_board.g_engine.u_synth.u_mgr.timbre_v[0])$fatal(1,"initial keyboard timbre");
 tn=0;waitn(30);tn=1;waitn(30);if(!d.keyboard_flute)$fatal(1,"onboard selector not routed");
 note();if(!d.u_board.g_engine.u_synth.u_mgr.timbre_v[1] || d.u_board.g_engine.u_synth.u_mgr.timbre_v[0])$fatal(1,"old timbre changed or new timbre absent");
 if(d.u_board.g_engine.u_synth.u_mgr.flute_v!==32'd2)$fatal(1,"S1 must select flute for new keyboard voice only");
 if(!d.u_board.g_engine.u_synth.u_arr.g_voice[1].u_voice.voice_flute)$fatal(1,"flute flag did not reach actual voice");
 if(d.u_board.g_engine.u_synth.u_mgr.slot_source[1]!=0)$fatal(1,"timbre switch changed owner, will lose NOTE_OFF");
 bn=0;waitn(200);if(d.bend_w!=127)$fatal(1,"manual bend route");
 waitn(10);if(d.u_board.bend_audio!=127)$fatal(1,"Gray CDC decode");
 bn=1;waitn(200);if(d.bend_w!=64)$fatal(1,"manual bend return");
 $display("PASS actual top keyboard timbre selector, per-note latch, owner preservation and independent Gray-coded bend CDC");$finish;end
initial begin #2000000;$fatal(1,"top controls timeout");end
endmodule

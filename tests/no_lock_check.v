`timescale 1ns/1ps
module no_lock_check;
reg clk=0,rst=0;always #10 clk=~clk;wire bclk,ws,dacdat;integer edges=0;
top_system d(.key_bend_n(1'b1),.key_timbre_n(1'b1),.clk_50m(clk),.rst_n(rst),.touch_raw(1'b0),.sensor_gpio(8'hff),.calib_run_p(1'b0),.calib_run_o(1'b0),.calib_clear(1'b0),.ads_miso(1'b0),.ads_drdy(1'b1),.bclk(bclk),.ws(ws),.dacdat(dacdat));
always @(posedge bclk)edges=edges+1;
integer before_edges;
initial begin
 #100;rst=1;@(negedge clk);force d.boot_done=1;
 force d.sw_num=60;force d.sw_vel=90;force d.sw_timbre=0;force d.note_on_c=1;
 @(negedge clk);force d.note_on_c=0;repeat(10000)@(negedge clk);
 if(d.u_board.active_debug==0)$fatal(1,"note did not reach audio engine");
 force d.dropped=1;force d.harp_overflow=1;before_edges=edges;
 repeat(20000)@(negedge clk);
 if(d.audio_rst_w!==1 || d.u_board.active_debug==0 || edges<=before_edges+10)$fatal(1,"diagnostic globally latched audio mute/reset");
 if(!d.diagnostic_warning)$fatal(1,"fault not visible");
 $display("PASS missing ADC and sticky event diagnostics do not reset/mute an active audio engine; DAC clocks continue");$finish;
end
endmodule

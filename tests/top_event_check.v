`timescale 1ns/1ps
module top_event_check;
reg clk=0,rst=0;always #10 clk=~clk;
top_system d(.key_bend_n(1'b1),.key_timbre_n(1'b1),.clk_50m(clk),.rst_n(rst),.touch_raw(1'b0),.sensor_gpio(8'hff),.calib_run_p(1'b0),.calib_run_o(1'b0),.calib_clear(1'b0),.ads_miso(1'b0),.ads_drdy(1'b1));
reg[18:0]gold[0:63];integer wr=0,rd=0;
always @(posedge clk)if(rst)begin
 if(d.pop)begin if(rd>=wr || d.q_out!==gold[rd])$fatal(1,"event order %0d",rd);rd=rd+1;end
 for(integer i=0;i<8;i=i+1)if(d.incoming[i])begin gold[wr]=d.incoming_data[i*19+:19];wr=wr+1;end
end
initial begin
 #100;rst=1;@(negedge clk);force d.boot_done=1;
 force d.sw_num=60;force d.sw_offnum=62;force d.sw_vel=100;force d.sw_timbre=0;
 force d.sw_vunum=64;force d.sw_vuvel=90;force d.g_num=72;force d.g_offnum=72;
 force d.note_on_c=1;force d.note_off_c=1;force d.velupd_c=1;force d.g_on=1;force d.g_off=1;
 repeat(3)@(negedge clk);
 force d.note_on_c=0;force d.note_off_c=0;force d.velupd_c=0;force d.g_on=0;force d.g_off=0;
 repeat(1500)@(negedge clk);
 if(wr!=15 || rd!=15 || d.dropped)$fatal(1,"event loss %0d/%0d",rd,wr);
 if(gold[0][18:17]!=0 || gold[3][18:17]!=3 || gold[4][18:17]!=3)$fatal(1,"owner tags");
 $display("PASS 3 cycles x 5 simultaneous live/guide events preserved with independent owners");$finish;
end
endmodule

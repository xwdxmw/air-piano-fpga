`timescale 1ns/1ps
module source_isolation;
reg clk=0,rst=0,on=0,off=0,vu=0;always #10 clk=~clk;
reg[1:0] source=0;wire[3:0] rel;wire[27:0] vel;
poly_mgr #(.N(4)) d(.clk(clk),.rst_n(rst),.sample_tick(1'b0),.note_on(on),.note_num(7'd60),
.velocity(7'd100),.source(source),.timbre(source==1),.vel_upd(vu),.vel_upd_num(7'd60),
.vel_upd_vel(7'd24),.note_off(off),.all_notes_off(1'b0),.ad_state_v({4{3'd3}}),.note_release_v(rel),.velocity_v(vel));
integer i;
initial begin
 #100;rst=1;
 for(i=0;i<4;i=i+1)begin @(negedge clk);source=i;on=1;@(negedge clk);on=0;@(negedge clk);end
 source=0;vu=1;@(negedge clk);vu=0;
 if(vel!=={7'd100,7'd100,7'd100,7'd24})$fatal(1,"velocity crossed source");
 @(negedge clk);source=2;off=1;@(negedge clk);off=0;
 if(rel!==4'b0100)$fatal(1,"beep release crossed source");
 @(negedge clk);source=0;off=1;@(negedge clk);off=0;
 if(rel!==4'b0101)$fatal(1,"piano release crossed source");
 $display("PASS same-pitch piano/harp/beep/guide own independent release and velocity");$finish;
end
endmodule

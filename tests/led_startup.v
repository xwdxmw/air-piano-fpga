`timescale 1ns/1ps
module led_startup;
reg clk=0,rst=0;always #10 clk=~clk;wire active;wire[191:0]grb;
led_startup_test #(.CLK_HZ(1000),.STEP_MS(10)) d(.clk(clk),.rst_n(rst),.active(active),.grb(grb));
reg[23:0]want;
initial begin
 #100;@(negedge clk);rst=1;#1;
 for(integer stage=0;stage<12;stage=stage+1)begin
  if(!active)$fatal(1,"selftest ended early");
  for(integer i=0;i<8;i=i+1)begin
   want=0;if(stage<8 && stage==i)want=24'h080808;else if(stage==8)want=24'h000800;else if(stage==9)want=24'h080000;else if(stage==10)want=24'h000008;
   if(grb[i*24+:24]!==want)$fatal(1,"startup stage %0d LED%0d",stage,i);
  end
  repeat(10)@(negedge clk);
 end
 if(active || grb!==0)$fatal(1,"selftest fails to hand over");
 repeat(100)@(negedge clk);if(active || grb!==0)$fatal(1,"selftest repeats");
 $display("PASS 8-pixel sweep,all RGB,dark,one-shot handover");$finish;
end
endmodule

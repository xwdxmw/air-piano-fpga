`timescale 1ns/1ps
module live_led_follow_check;
reg clk=0,rst=0,en=0;always #10 clk=~clk;
reg[7:0]keys=0,strings=0;wire[191:0]grb;
// 10 clocks/ms, 3ms hold for exhaustive bounded checks at all divider phases.
live_led_follow #(.CLK_HZ(10000),.HOLD_MS(3)) d(.clk(clk),.rst_n(rst),.enable(en),.keys(keys),.strings(strings),.grb(grb));
integer i,j,n;reg[191:0]want;
task tick;begin @(negedge clk);end endtask
task zero;begin if(grb!==0)$fatal(1,"expected black %h",grb);end endtask
task check;input integer k;input[23:0]color;begin
 want=0;want[k*24+:24]=color;
 if(grb!==want)$fatal(1,"pixel%0d expected%h got%h",k,want,grb);
end endtask
initial begin
 #2;rst=0;#30;rst=1;tick;en=1;tick;
 for(i=0;i<8;i=i+1)begin
  keys=1<<i;tick;check(i,24'h100010);
  strings=1<<i;tick;check(i,24'h101010);
  keys=0;repeat(31)tick;check(i,24'h101000);
  strings=0;repeat(31)tick;zero;
 end
 for(j=0;j<10;j=j+1)begin
  en=0;tick;en=1;repeat(j+1)tick;
  keys=8'h80;tick;keys=0;
  repeat(20)begin tick;check(7,24'h100010);end
  repeat(11)tick;zero;
 end
 keys=8'hff;strings=8'hff;tick;
 for(i=0;i<8;i=i+1)if(grb[i*24+:24]!==24'h101010)$fatal(1,"simultaneous8keys");
 en=0;#1;zero;tick;keys=0;strings=0;en=1;tick;zero;
 keys=1;tick;rst=0;#1;zero;rst=1;keys=0;tick;zero;
 $display("PASS all8 FSR/IR/overlap colors, hold expiration at10phases, enable clears immediately, reset clears pending feedback");$finish;
end
initial begin #100000;$fatal(1,"LED unit timeout");end
endmodule

`timescale 1ns/1ps
module ws2812_protocol;
reg clk=0,rst=0;always #10 clk=~clk;
reg[719:0] grb=192'hfedcba_123456_010203_80ff00_ffff00_000001_800000_a55ac3;
reg[719:0] original;
wire dout;
ws2812_tx #(.N_LED(30),.FRAME_US(350)) d(.clk(clk),.rst_n(rst),.grb(grb),.dout(dout));
time rise_at,last_rise=0,last_fall=0;
integer n=0;reg expected,prev_bit;
always @(posedge dout)if(rst)begin
 if(n>0 && n%720!=0)begin
 if($time-last_fall!=(prev_bit?600:900))$fatal(1,"low phase mismatch");
 if($time-last_fall<580 || $time-last_fall>1000)$fatal(1,"V5 low phase outside datasheet");
 end
 if(n==720 && $time-last_fall<300000)$fatal(1,"reset too short");
 rise_at=$time;last_rise=$time;
end
always @(negedge dout)if(rst && rise_at>0)begin
 expected=(n<720)?original[(n/24)*24+23-(n%24)]:1'b0;
 if($time-rise_at!=(expected?800:320))$fatal(1,"pulse/data mismatch bit%0d width%0t",n,$time-rise_at);
 prev_bit=expected;last_fall=$time;n=n+1;
 if(n==1440)begin $display("PASS WS2812 1440 decoded bits,30 pixels and black tail, GRB order,320/800ns high,900/600ns low,V5 low bounds,>=300us reset, frame snapshot");$finish;end
end
initial begin original=grb;#100;rst=1;wait(n==1);grb=0;end
initial begin #5000000;$fatal(1,"WS timeout");end
endmodule

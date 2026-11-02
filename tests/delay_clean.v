`timescale 1ns/1ps
module delay_clean;
reg clk=0,rst=0,tick=0;always #10 clk=~clk;
reg signed[15:0] din=0;wire signed[15:0] dout;integer i;
delay_fx #(.DEPTH(16),.AW(4),.DLY(8)) d(.clk(clk),.rst_n(rst),.sample_tick(tick),.din(din),.dout(dout));
task step(input integer v);begin
 @(negedge clk);din=v;tick=1;@(negedge clk);tick=0;repeat(3)@(negedge clk);
end endtask
initial begin
 #100;rst=1;
 repeat(40)begin step(0);if(dout!==0)$fatal(1,"uninitialized history leaked");end
 step(10000);if(dout!==10000)$fatal(1,"dry impulse lost");
 for(i=1;i<=16;i=i+1)begin
  step(0);
  if(i==8 && dout!==5000)$fatal(1,"first echo");
  if(i==16 && dout!==2500)$fatal(1,"second echo");
  if(i!=8 && i!=16 && dout!==0)$fatal(1,"unexpected echo timing");
 end
 @(negedge clk);rst=0;din=0;#100;
 for(i=0;i<16;i=i+1)d.mem[i]=10000;
 rst=1;repeat(40)begin step(0);if(dout!==0)$fatal(1,"warm reset history leaked");end
 $display("PASS cold/warm silence, dry impulse, delay length and 0.5 feedback");$finish;
end
endmodule

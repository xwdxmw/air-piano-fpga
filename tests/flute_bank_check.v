`timescale 1ns/1ps
module flute_bank_check;
reg clk=0,rst=0,start=0,clear=0,run=1;reg[31:0]freq=23409859;always #5 clk=~clk;
wire signed[15:0]wave;
flute_bank d(.clk(clk),.rst_n(rst),.sample_tick(1'b1),.start(start),.clear(clear),.run(run),.seed_note(7'd60),.freq_ctrl(freq),.wave(wave));
integer i,b,got;
initial begin #30;rst=1;@(negedge clk);start=1;@(negedge clk);start=0;
 // Verify every analytic table entry bounds and antisymmetry (zero DC).
 for(b=0;b<3;b=b+1)for(i=0;i<256;i=i+1)begin
  got=$signed(d.lookup(b*256+i));if(got>30000 || got< -30000)$fatal(1,"flute table clips");
  if(got!= -$signed(d.lookup(b*256+((256-i)%256))))$fatal(1,"flute table DC/asymmetry");
 end
 freq=644245094;#1;if(d.band!=0)$fatal(1,"third harmonic boundary");
 freq=644245095;#1;if(d.band!=1)$fatal(1,"third harmonic must be omitted above0.45Fs");
 freq=966367641;#1;if(d.band!=1)$fatal(1,"second harmonic boundary");
 freq=966367642;#1;if(d.band!=2)$fatal(1,"second harmonic must be omitted above0.45Fs");
 for(i=0;i<10000;i=i+1)begin @(negedge clk);freq=i*32'd193273;if(^wave===1'bx || wave>30100 || wave< -30100)$fatal(1,"flute bounds/undefined");end
 clear=1;@(negedge clk);if(wave!==0)$fatal(1,"clear not silent");clear=0;run=0;repeat(100)@(negedge clk);if(wave!==0)$fatal(1,"idle breath leak");
 $display("PASS all768 flute table entries bounded/antisymmetric; harmonic omission thresholds, frequency sweep, clear and idle-noise gate");$finish;
end
endmodule

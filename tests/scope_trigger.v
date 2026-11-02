`timescale 1ns/1ps
module scope_trigger;
reg clk=0,rst=0,req=0,silent=0;always #10 clk=~clk;
reg[4:0]phase=0;always @(posedge clk)phase<=phase+1'b1;
wire signed[15:0]pcm=silent?16'sd0:(phase<16?-16'sd12000:16'sd12000);
reg[6:0]addr=0;wire ready;wire[7:0]wy,lx,ly;reg[7:0]saved[0:127];
scope_cap #(.DEC(1),.LAG(4),.TRIGGER_ENABLE(1),.TRIGGER_SAMPLES(64)) d(
.clk_a(clk),.rst_a(rst),.sample_tick(1'b1),.pcm(pcm),.clk_d(clk),.rst_d(rst),.raddr(addr),.capture_req(req),.ready(ready),.wave_y(wy),.liss_x(lx),.liss_y(ly));
task capture;begin @(negedge clk);req=1;@(negedge clk);req=0;wait(!ready);wait(ready);end endtask
initial begin
#100;rst=1;repeat(100)@(negedge clk);capture;
for(integer i=0;i<128;i=i+1)begin addr=i;repeat(3)@(negedge clk);saved[i]=wy;end
repeat(11)@(negedge clk);capture;
for(integer i=0;i<128;i=i+1)begin addr=i;repeat(3)@(negedge clk);if(wy!==saved[i])$fatal(1,"trigger phase mismatch %0d",i);end
silent=1;capture;addr=0;repeat(3)@(negedge clk);if(wy!==28)$fatal(1,"silence timeout fallback");
$display("PASS scope rising-zero-cross phase lock and silent trigger timeout");$finish;
end
initial begin #200000;$fatal(1,"scope trigger timeout");end
endmodule

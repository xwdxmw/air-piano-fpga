`timescale 1ns/1ps
module pressure_path_check;
reg clk=0,rst=0,valid=0;always #10 clk=~clk;
reg[2:0] idx=0;reg[11:0] val=0;wire[7:0] keys;wire on,off;wire[6:0] offnum;
integer offs=0;
c_interact_top d(.clk(clk),.rst_n(rst),.sensor_gpio(8'hff),.adc_p(96'd0),.adc_valid(1'b0),
.adc_ch_valid(valid),.adc_ch_idx(idx),.adc_ch_data(val),.adc_o(96'd0),.touch_raw(1'b0),
.calib_run_p(1'b0),.calib_run_o(1'b0),.calib_clear(1'b0),.key_on(keys),.note_on(on),.note_off(off),.note_off_num(offnum));
defparam d.u_zero.CLK_FREQ_HZ=1000;
defparam d.u_zero.STALE_MS=2000;
always @(posedge clk)if(rst && off)begin if(offnum!=60)$fatal(1,"wrong off");offs=offs+1;end
task sample(input integer c,input integer x);begin @(negedge clk);idx=c;val=x;valid=1;@(negedge clk);valid=0;end endtask
integer i,j;
initial begin
 #100;rst=1;
 for(i=0;i<64;i=i+1)for(j=0;j<7;j=j+1)sample(j,600);
 sample(0,2400);repeat(20)@(negedge clk);if(keys!=1)$fatal(1,"missing channel prevented press");
 repeat(2100)@(negedge clk);
 if(keys!=0 || offs!=1)$fatal(1,"stale key failed to release: keys%h OFF%0d",keys,offs);
 sample(0,600);repeat(20)@(negedge clk);if(keys!=0 || on)$fatal(1,"idle recovery ghost");
 $display("PASS seven-channel operation, stale pressed key generates exactly one NOTE_OFF, quiet recovery");$finish;
end
endmodule

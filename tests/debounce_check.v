`timescale 1ns/1ps
module debounce_check;
reg clk=0,rst=0,din=0;always #10 clk=~clk;wire dout;
c_sync_debounce #(.DB_CNT(70000)) d(.clk(clk),.rst_n(rst),.din(din),.dout(dout));
initial begin #100;rst=1;@(negedge clk);din=1;repeat(66000)@(negedge clk);
 if(dout)$fatal(1,"debounce counter truncated to 16 bits");
 repeat(4010)@(negedge clk);if(!dout)$fatal(1,"debounce did not accept stable input");
 $display("PASS debounce parameter beyond 65535 cycles is honored");$finish;end
endmodule

`timescale 1ns/1ps
`include "tests/rom_references.v"
module rom_truth_check;
reg[7:0]addr=1;wire[31:0]n,nref,constant_note;wire[15:0]s,sref,constant_sine;integer i;
note_freq_rom d(.addr(addr[6:0]),.dout(n));note_freq_rom_reference nr(.addr(addr[6:0]),.dout(nref));
sine_rom sr(.addr(addr),.dout(s));sine_rom_reference rs(.addr(addr),.dout(sref));
note_freq_rom cn(.addr(7'd60),.dout(constant_note));sine_rom cs(.addr(8'd0),.dout(constant_sine));
initial begin #10;if(^constant_note===1'bx || constant_sine!==0)$fatal(1,"constant address ROM failed to initialize");
for(i=0;i<256;i=i+1)begin addr=i;#10;if(n!==nref || s!==sref)$fatal(1,"ROM truth table mismatch addr%0d",i);end
$display("PASS all128 note words/all256 sine words identical; constant-address outputs are known at startup");$finish;end
endmodule

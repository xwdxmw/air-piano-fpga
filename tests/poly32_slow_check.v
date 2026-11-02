`timescale 1ns/1ps
module poly32_slow_check;
reg clk=0,rst=0;always #10 clk=~clk;
wire on,off,ano;wire[6:0]num,vel;
// Keep default millisecond settings; only scale the timebase parameter.
poly32_seq #(.CLK_FREQ_HZ(1000)) d(.clk(clk),.rst_n(rst),.note_on(on),.note_num(num),.velocity(vel),.note_off(off),.all_notes_off(ano));
poly32_seq real_defaults(.clk(1'b0),.rst_n(1'b0));
integer cycle=0,ons=0,anos=0,index,last_on=-1,last_ano=-1,first_on=-1;
always @(negedge clk)if(rst)begin
 cycle=cycle+1;
 if(on)begin
  index=ons%32;
  if(num!==36+index || vel!==40 || off || ano)$fatal(1,"wrong note/pulse/velocity");
  if(index>0 && cycle-last_on!=200)$fatal(1,"not 200ms per accumulating note");
  if(index==0)begin
   if(last_ano>=0 && cycle-last_ano!=3001)$fatal(1,"not 3s release gap");
   first_on=cycle;
  end
  if(index==31 && cycle-first_on!=6200)$fatal(1,"wrong first-to-last duration");
  last_on=cycle;ons=ons+1;
 end
 if(ano)begin
  if(ons%32!=0 || cycle-last_on!=10200)$fatal(1,"32 voices did not receive complete 10s hold");
  last_ano=cycle;anos=anos+1;
 end
 if(anos==2)begin
  if(ons!=64)$fatal(1,"bad two-loop note count");
  $display("PASS default32-note timing:64 ordered NOTE_ONs,200ms per slot,6.2s first-to-last,6.4s load stage,10s extra full hold,3s release gap,two ALL_OFF; timestep-scaled not board measurement");$finish;
 end
end
initial begin
 #1;
 if(real_defaults.SLOT_CLKS!=10000000 || real_defaults.HOLD_CLKS!=500000000 || real_defaults.GAP_CLKS!=150000000)$fatal(1,"50MHz defaults wrong");
 #99;rst=1;
end
initial begin #1000000;$fatal(1,"slow sequence test timeout");end
endmodule

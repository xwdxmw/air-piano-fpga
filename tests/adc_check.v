`timescale 1ns/1ps
module adc_check;
localparam CORRUPT=0;
reg clk=0,rst=0;always #10 clk=~clk;
wire sclk,mosi,cs,cv,init_fault;wire[7:0] timeout_mask;
reg miso=0,drdy=1;wire[2:0] ci;wire[11:0] cd;
ads1256_driver #(.CAL_WAIT_US(1000)) d(.clk(clk),.rst_n(rst),
.ads_sclk(sclk),.ads_mosi(mosi),.ads_cs_n(cs),.ads_miso(miso),.ads_drdy(drdy),
.ch_valid(cv),.ch_idx(ci),.ch_data(cd));
integer bits=0,mode=0,addr=0,left=0,channel=0,rbits=0,ready=0,received=0,expected_ch=0,reads=0;
integer fault_mode=0;reg[7:0] b=0,regs[0:3];reg[23:0] serial=0;time last_fall=0;integer changes=0;
always @(negedge sclk)last_fall=$time;
always @(mosi)if(rst&&last_fall>0)begin
 if($time-last_fall<50)$fatal(1,"DIN hold %0d ns",$time-last_fall);changes=changes+1;
end
always @(posedge clk)if(ready>0)begin ready=ready-1;if(ready==0 && fault_mode==0)drdy=0;end
always @(posedge cs)begin bits=0;mode=0;end
always @(posedge sclk)if(!cs&&rbits>0)begin #30;miso=serial[23];serial={serial[22:0],1'b0};rbits=rbits-1;end
always @(negedge sclk)if(!cs)begin
 b={b[6:0],mosi};bits=bits+1;
 if(bits==8)begin
  bits=0;
  case(mode)
   1:begin left=b+1;mode=2;end
   2:begin
      if(addr<4)regs[addr]=b;
      if(addr==0 && b!=8'h02)$fatal(1,"ACAL unexpectedly enabled");
      if(addr==1)channel=b[6:4];
      addr=addr+1;left=left-1;if(left==0)mode=0;
     end
   3:begin left=left-1;if(left==0)mode=0;end
   4:begin
      if(b!=0)$fatal(1,"unexpected RREG length");
      serial={(CORRUPT && addr==3 ? 8'h00 : regs[addr]),16'd0};rbits=8;reads=reads+1;left=1;mode=3;
     end
   default:begin
    if(ready>0 && b!=0 && b!=8'hfe)$fatal(1,"command while ADC busy: %h",b);
    if(b[7:4]==5)begin addr=b[3:0];mode=1;end
    else if(b[7:4]==1)begin addr=b[3:0];mode=4;end
    else if(b==8'hfe)begin drdy=1;ready=29800;regs[0]=0;regs[1]=1;regs[2]=0;regs[3]=8'hf0;end
    else if(b==8'hf0)begin drdy=1;ready=29800;end
    else if(b==8'hfc)begin if(fault_mode!=2)drdy=1;end
    else if(b==0)begin if(fault_mode==0)ready=10500;end
    else if(b==1)begin if(fault_mode!=0)$fatal(1,"RDATA issued after timeout");serial=(channel*300+50)<<11;rbits=24;left=3;mode=3;end
   end
  endcase
 end
end
always @(posedge clk)if(cv)begin
 if(ci!==expected_ch[2:0] || cd!==(expected_ch*300+50))$fatal(1,"sample mismatch");
 received=received+1;expected_ch=(expected_ch+1)%8;
end
integer before_fault;
initial begin
 #100;rst=1;
 wait(received==24);#100;
 if(changes<20)$fatal(1,"configuration not validated");
 $display("PASS explicit calibration wait, ACAL off, 24 ordered samples, DIN hold >=50ns");
 fault_mode=1;drdy=1;ready=0;before_fault=received;
 #10000000;
 if(received!=before_fault)$fatal(1,"DRDY high fault publication");
 // Apply a stuck-low line before the next conversion starts. A high->low
 // transition during an armed conversion is indistinguishable from readiness.
 wait(d.state==d.S_CH_WAKE);fault_mode=2;drdy=0;#10000000;
 if(received!=before_fault)$fatal(1,"DRDY stuck low accepted as fresh conversion");
 $display("PASS DRDY stuck high/low produces no fresh samples or RDATA");$finish;
end
initial begin #40000000;$fatal(1,"protocol test timeout");end
endmodule

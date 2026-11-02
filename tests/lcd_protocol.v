`timescale 1ns/1ps
module lcd_protocol;
reg clk=0,rst=0,mode=1;reg[7:0]ir=8'h55;reg gm=0,tp=0;reg[2:0]gkey=0;always #10 clk=~clk;
wire sclk,mosi,cs,dc,ready;
lcd_panel #(.DLY_120(60),.DLY_20(10),.CAP_WAIT(32),.FRAME_GAP(20)) d(
.clk(clk),.rst_n(rst),.lcd_sclk(sclk),.lcd_mosi(mosi),.lcd_cs_n(cs),.lcd_dc(dc),
.mode(mode),.ir_v(ir),.clk_audio(clk),.rst_audio_n(rst),.sample_tick_audio(1'b0),.voice_active_audio(32'd0),.pcm_audio(16'd0),.keyboard_flute(1'b0),.guide_mode(gm),.test_mode(1'b0),.touch_state(tp),.guide_key(gkey),.ready(ready));
integer bits=0,bytes=0,rects=0,pixels=0,param_i=0,expected_px=0,init_i=0;
integer x0,x1,y0,y1,px,py;integer dump;reg[7:0] shift=0,command=0,highbyte;reg lowbyte=0;
reg[15:0] pixel;reg[34:0] glyph={5'b10001,5'b10001,5'b10001,5'b10001,5'b01010,5'b01010,5'b00100};
reg[7:0] init_data[0:19];reg init_cmd[0:19];time last_reset_end=0,last_sleep_end=0;
task receive(input[7:0] b,input isdata);
begin
 bytes=bytes+1;
 if(init_i<20)begin
  if(b!==init_data[init_i] || isdata===init_cmd[init_i])$fatal(1,"init byte%0d %h dc%b",init_i,b,isdata);
  if(init_i==0)last_reset_end=$time;
  if(init_i==1)begin if($time-last_reset_end<1200)$fatal(1,"reset wait");last_sleep_end=$time;end
  if(init_i==2 && $time-last_sleep_end<1200)$fatal(1,"sleep wait");
  init_i=init_i+1;
 end else if(!isdata)begin
  if(command==8'h2c && (pixels!=expected_px || lowbyte))$fatal(1,"RAMWR count rect%0d got%0d expected%0d",rects,pixels,expected_px);
  command=b;param_i=0;
  if(b==8'h2c)begin
   if(x0>x1 || x0!=0 || x1!=159 || y0!=0 || y1!=127)$fatal(1,"invalid LCD bounds");
   expected_px=(x1-x0+1)*(y1-y0+1);pixels=0;lowbyte=0;rects=rects+1;
  end else if(b!=8'h2a && b!=8'h2b)$fatal(1,"unexpected command %h",b);
  if(rects==2 && b==8'h2a)begin
   if(!ready)$fatal(1,"ready not held");
   $display("PASS LCD init, SPI decode,two composite landscape frames, bounds,exact RGB565 byte counts,landscape MADCTL,frame pixels and state snapshot,no-audio fallback");$finish;
  end
 end else if(command==8'h2a || command==8'h2b)begin
  if((param_i==0 || param_i==2) && b!=0)$fatal(1,"address high");
  if(command==8'h2a)begin if(param_i==1)x0=b;if(param_i==3)x1=b;end
  else begin if(param_i==1)y0=b;if(param_i==3)y1=b;end
  param_i=param_i+1;
 end else if(command==8'h2c)begin
  if(!lowbyte)highbyte=b;
  else begin
   pixel={highbyte,b};
   px=pixels%160;py=pixels/160;
   if(px==80 && py==5 && pixel!==(rects==1?16'hfbe0:16'h0339))$fatal(1,"frame header %h",pixel);
   if(rects==1 && px>=4 && px<=8 && py>=4 && py<=10 && pixel!==(glyph[34-((py-4)*5+px-4)]?16'hffff:16'hfbe0))$fatal(1,"glyph");
   if(px==17 && py==5 && pixel!==(rects==1?16'hffff:16'h0339))$fatal(1,"N/G mode glyph");
   if(px==25 && py==4 && pixel!==(rects==1?16'hfbe0:16'hffff))$fatal(1,"guide key 5 glyph");
   if(px==36 && py==4 && pixel!==(rects==1?16'h2104:16'hffff))$fatal(1,"touch indicator");
   if(px==125 && py==4 && pixel!==16'hffff)$fatal(1,"version AP04 A glyph");
   if(px==145 && py==4 && pixel!==16'hffff)$fatal(1,"version AP04 final digit4 glyph");
   if(px==6 && py==24 && pixel!==(rects==1?16'hf800:16'h0000))$fatal(1,"IR snapshot");
   if(px==10 && py==70 && pixel!==16'h07e0)$fatal(1,"wave fallback");
   if(px==127 && py==69 && pixel!==16'h07ff)$fatal(1,"liss fallback");
   if(px==80 && py==120 && pixel!==16'h0000)$fatal(1,"background");
   if(rects==1)$fwrite(dump,"%04x\n",pixel);
   pixels=pixels+1;
   if(rects==1 && pixels==1)begin mode=0;ir=8'haa;gm=1;tp=1;gkey=4;end
  end
  lowbyte=~lowbyte;
 end else $fatal(1,"data without command");
end endtask
always @(posedge sclk)begin
 if(cs)$fatal(1,"clock while deselected");
 shift={shift[6:0],mosi};bits=bits+1;
 if(bits==8)begin receive(shift,dc);bits=0;end
end
always @(posedge cs)if(rst && bits!=0)$fatal(1,"partial SPI byte");
initial begin
 init_data[0]=8'h01;init_data[1]=8'h11;init_data[2]=8'hb1;init_data[3]=1;init_data[4]=8'h2c;init_data[5]=8'h2d;
 init_data[6]=8'hc0;init_data[7]=8'ha2;init_data[8]=2;init_data[9]=8'h84;init_data[10]=8'hc1;init_data[11]=8'hc5;
 init_data[12]=8'hc5;init_data[13]=8'h0e;init_data[14]=8'h36;init_data[15]=8'h60;init_data[16]=8'h3a;init_data[17]=5;init_data[18]=8'h13;init_data[19]=8'h29;
 for(integer i=0;i<20;i=i+1)init_cmd[i]=(i==0 || i==1 || i==2 || i==6 || i==10 || i==12 || i==14 || i==16 || i==18 || i==19);
 dump=$fopen("tests/results/lcd_frame.hex","w");#100;rst=1;
end
initial begin #150000000;$fatal(1,"LCD timeout rect%0d bytes%0d",rects,bytes);end
endmodule

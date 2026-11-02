`timescale 1ns/1ps
module lcd_poly32_check;
reg clk=0,ca=0,rst=0,tm=1;always #10 clk=~clk;always #41 ca=~ca;
reg[31:0]active=0;wire sc,mo,cs,dc;
lcd_panel #(.DLY_120(60),.DLY_20(10),.CAP_WAIT(2000),.FRAME_GAP(20)) d(
 .clk(clk),.rst_n(rst),.lcd_sclk(sc),.lcd_mosi(mo),.lcd_cs_n(cs),.lcd_dc(dc),.mode(1'b0),.ir_v(8'd0),
 .clk_audio(ca),.rst_audio_n(rst),.sample_tick_audio(1'b0),.pcm_audio(16'd0),.voice_active_audio(active),
 .guide_mode(1'b0),.test_mode(tm),.touch_state(1'b0),.keyboard_flute(1'b0),.guide_key(3'd0),.ready());
integer bits=0,init=0,frames=0,pixels=0,x,y,j,out,checked=0;reg[7:0]shift=0,command=0,highbyte;reg lowbyte=0;
reg[15:0]pixel;reg[31:0]expected;integer expected_count;
task byte_rx(input[7:0]b,input isdata);begin
 if(init<20)init=init+1;
 else if(!isdata)begin
  command=b;
  if(b==8'h2c)begin
   frames=frames+1;pixels=0;lowbyte=0;
   case(frames)1:begin expected=0;expected_count=0;end 2:begin expected=15;expected_count=4;end
    3:begin expected=32'hffffffff;expected_count=32;end 4:begin expected=0;expected_count=0;end
    default:begin expected=3;expected_count=2;end endcase
   if(!d.frame_voice_valid || d.frame_voices!==expected || d.frame_voice_count!==expected_count)$fatal(1,"frame%d did not capture actual mask/count",frames);
   if(d.frame_test!==(frames<5))$fatal(1,"test/normal mode snapshot wrong");
   case(frames)
    1:out=$fopen("tests/results/voices_00.hex","w");
    2:out=$fopen("tests/results/voices_04.hex","w");
    3:out=$fopen("tests/results/voices_32.hex","w");
    4:out=$fopen("tests/results/voices_released.hex","w");
    default:out=$fopen("tests/results/voices_normal.hex","w");
   endcase
  end
 end else if(command==8'h2c)begin
  if(!lowbyte)highbyte=b;
  else begin
   pixel={highbyte,b};x=pixels%160;y=pixels/160;$fwrite(out,"%04x\n",pixel);
   for(j=0;j<32;j=j+1)if(x==108+(j%4)*14 && y==43+(j/4)*8)begin
    if(pixel!==(frames<5 ? (expected[j]?16'h07e0:16'h2104) :16'h0000))$fatal(1,"wrong actual SPI slot%d frame%d %h",j,frames,pixel);
    checked=checked+1;
   end
   if(frames<5 && x>=102 && x<158 && y>=40 && y<104 && (x-102)%14<12 && (y-40)%8<6)
    if(pixel!==(expected[((y-40)/8)*4+(x-102)/14]?16'h07e0:16'h2104))$fatal(1,"grid cell occluded at%d,%d frame%d",x,y,frames);
   if(frames==3 && y==4 && x==90 && pixel!==16'hffff)$fatal(1,"full32 tens3 not displayed");
   if(frames==3 && y==4 && x==96 && pixel!==16'h0339)$fatal(1,"full32 ones2 glyph wrong");
   if(frames==3 && y==4 && x==97 && pixel!==16'hffff)$fatal(1,"full32 ones2 absent");
   if(frames==5 && x==127 && y==69 && pixel!==16'h07ff)$fatal(1,"normal mode did not restore Lissajous");
   if(pixels==0)case(frames)1:active=15;2:active=32'hffffffff;3:active=0;4:begin active=3;tm=0;end endcase
   pixels=pixels+1;
   if(pixels==20480)begin
    $fclose(out);
    if(frames==5)begin if(checked!=160)$fatal(1,"slot pixel coverage");$display("PASS5 actual decoded LCD SPI frames:0/4/32/released0/normal2,160 slot cells,32 decimal header, immutable rendering, normal Lissajous restored");$finish;end
   end
  end
  lowbyte=~lowbyte;
 end
end endtask
always @(posedge sc)begin
 if(cs)$fatal(1,"SPI clock while deselected");shift={shift[6:0],mo};bits=bits+1;
 if(bits==8)begin byte_rx(shift,dc);bits=0;end
end
initial begin #100;rst=1;end
initial begin #250000000;$fatal(1,"LCD32 timeout frames%d",frames);end
endmodule

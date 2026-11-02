`timescale 1ns/1ps
module lcd_pixel_equiv;
reg clk=0,rst=0;always #5 clk=~clk;
reg[7:0]xx=0,yy=0;reg fm=0,fg=0,ft=0,fh=0,fk=0,fv=0;
reg[2:0]key=0;reg[5:0]cnt=0;reg[31:0]mask=0;reg[79:0]bars=0;
lcd_panel #(.DLY_20(1000000000))d(.clk(clk),.rst_n(rst),.mode(1'b0),.ir_v(8'd0),.clk_audio(clk),.rst_audio_n(rst),.sample_tick_audio(1'b0),.pcm_audio(16'd0),.voice_active_audio(32'd0),.guide_mode(1'b0),.test_mode(1'b0),.touch_state(1'b0),.keyboard_flute(1'b0),.guide_key(3'd0));
ap03_lcd_panel #(.DLY_20(1000000000))refd(.clk(clk),.rst_n(rst),.mode(1'b0),.ir_v(8'd0),.clk_audio(clk),.rst_audio_n(rst),.sample_tick_audio(1'b0),.pcm_audio(16'd0),.voice_active_audio(32'd0),.guide_mode(1'b0),.test_mode(1'b0),.touch_state(1'b0),.keyboard_flute(1'b0),.guide_key(3'd0));
integer p,x,y,i,checked=0;
initial begin
 force d.x=xx;force refd.x=xx;force d.y=yy;force refd.y=yy;
 force d.frame_mode=fm;force refd.frame_mode=fm;force d.frame_guide=fg;force refd.frame_guide=fg;
 force d.frame_test=ft;force refd.frame_test=ft;force d.frame_touch=fh;force refd.frame_touch=fh;
 force d.frame_keyboard=fk;force refd.frame_keyboard=fk;force d.frame_key=key;force refd.frame_key=key;
 force d.frame_voice_valid=fv;force refd.frame_voice_valid=fv;
 force d.frame_voice_count=cnt;force refd.frame_voice_count=cnt;force d.frame_voices=mask;force refd.frame_voices=mask;
 force d.frame_spectrum=bars;force refd.frame_spectrum=bars;
 #30;rst=1;
 for(p=0;p<16;p=p+1)begin
  fm=p%2;fg=(p/2)%2;ft=(p/4)%2;fh=(p/8)%2;fk=p%3==0;fv=p!=0;key=p%8;
  case(p)0:cnt=0;1:cnt=1;2:cnt=9;3:cnt=10;4:cnt=11;5:cnt=19;6:cnt=20;7:cnt=21;8:cnt=29;9:cnt=30;10:cnt=31;default:cnt=32;endcase
  mask=32'hf0a55a0f ^ (32'h11111111*p);for(i=0;i<16;i=i+1)bars[i*5+:5]=(i+p)%32;
  repeat(3)@(negedge clk);
  for(y=0;y<128;y=y+1)begin
   yy=y;repeat(2)@(negedge clk);
   for(x=0;x<160;x=x+1)begin
   xx=x;yy=y;#1;
   if(d.base_pixel!==refd.base_pixel)$fatal(1,"pixel mismatch scenario%0d x%0d y%0d got%0d/%0d",p,x,y,d.base_pixel,refd.base_pixel);
   if(x>=2 && x<158 && (d.spec_bin!==(x-2)/10 || d.spec_column!==(x-2)%10))$fatal(1,"spectrum index mismatch");
   checked=checked+1;
   end
  end
 end
 $display("PASS %0d AP03-equivalent base pixels in16 complete160x128 scenarios, N/G/T and all UI layers, spectrum quotient/remainder; reference label normalized toAP04",checked);$finish;
end
endmodule

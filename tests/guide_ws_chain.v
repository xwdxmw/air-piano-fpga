`timescale 1ns/1ps
module guide_ws_chain;
reg clk=0,rst=0;always #10 clk=~clk;wire on,off,gate,hit,guiding;wire[2:0]key;wire[6:0]num;reg[7:0]keys=0;wire[191:0]grb;wire dout;
guide_seq #(.CLK_FREQ_HZ(2000000)) g(.clk(clk),.rst_n(rst),.enable(1'b1),.key_on(keys),.note_on(on),.note_off(off),.note_num(num),.cur_key(key),.guiding(guiding),.led_on(gate),.hit(hit));
guide_led_map m(.guide_mode(1'b1),.gate(gate),.hit(hit),.target(key),.keys(keys),.grb(grb));
wire[719:0]strip={528'd0,grb};
ws2812_tx #(.N_LED(30),.FRAME_US(300)) w(.clk(clk),.rst_n(rst),.grb(strip),.dout(dout));
reg[719:0]history0,history1,expected,decoded=0;integer epoch0,epoch1,epoch;reg gate0,gate1,lit;integer bits=0,ons=0,offs=0,frames=0;time rise_at=0,last_fall=0;reg[13:0]seen_on=0,seen_off=0;reg seen_green=0;integer pixel,bitno;
always @(posedge clk)begin
 history0<=strip;history1<=history0;epoch0<=g.idx;epoch1<=epoch0;gate0<=gate;gate1<=gate0;
end
always @(negedge clk)if(rst)begin
 if(on)begin ons=ons+1;keys=(ons==3)?(8'b1<<key):0;end
 if(off)offs=offs+1;
end
always @(posedge dout)if(rst)begin
 if(bits==0)begin expected=history1;epoch=epoch1;lit=gate1;end
 rise_at=$time;
end
always @(negedge dout)if(rst && rise_at!=0)begin
 pixel=bits/24;bitno=23-bits%24;
 if($time-rise_at!=320 && $time-rise_at!=800)$fatal(1,"invalid high phase");
 decoded[pixel*24+bitno]=($time-rise_at==800);bits=bits+1;last_fall=$time;
 if(bits==720)begin
  if(decoded[719:192]!==0)$fatal(1,"unused pixels lit during guide");
  if(decoded!==expected)$fatal(1,"serial frame differs from actual guide mapping, frame%0d",frames);
  if(epoch<14)begin
   if(lit && decoded!=0)seen_on[epoch]=1;
   if(!lit && decoded==0 && ons>epoch)seen_off[epoch]=1;
  end
  if(decoded===192'h000000_000000_000000_300000_000000_000000_000000_000000)seen_green=1;
  bits=0;decoded=0;frames=frames+1;
 end
end
initial begin
 #100;rst=1;wait(offs==14);#1500000;
 if(ons!=14 || seen_on!==14'h3fff || seen_off!==14'h3fff || !seen_green)$fatal(1,"chain incomplete on%h off%h green%0d",seen_on,seen_off,seen_green);
 $display("PASS 30-pixel wire: all 14 notes and gaps decoded from WS2812 wire, correct key colors, green hit and frame snapshots (%0d frames)",frames);$finish;
end
initial begin #400000000;$fatal(1,"guide WS chain timeout");end
endmodule

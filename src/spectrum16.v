`timescale 1ns/1ps
// 16 selected frequency energies of the ACTUAL post-effect PCM, Goertzel N=512.
// Full audio sample rate; no decimation/alias introduced by this monitor.
// Selected DFT bins: 1,2,3,4,5,6,8,10,12,16,24,32,48,64,96,128.
// One recurrence per clock, 16 clocks/sample < 256 clocks/sample budget.
// Continuous analyzer + acknowledged frozen display snapshot, independent of audio.
module spectrum16(
 input wire clk_a,rst_a,sample_tick,input wire signed[15:0]pcm,
 input wire clk_d,rst_d,capture_req,output reg[79:0]bars,output reg ready);
 function signed[16:0]coef;input[3:0]i;begin case(i)
  0:coef=17'sd32766;1:coef=17'sd32758;2:coef=17'sd32746;3:coef=17'sd32729;
  4:coef=17'sd32706;5:coef=17'sd32679;6:coef=17'sd32610;7:coef=17'sd32522;
  8:coef=17'sd32413;9:coef=17'sd32138;10:coef=17'sd31357;11:coef=17'sd30274;
  12:coef=17'sd27246;13:coef=17'sd23170;14:coef=17'sd12540;15:coef=17'sd0;
 endcase end endfunction
 function[4:0]height;input signed[64:0]p;integer j;reg[5:0]lg;begin
  lg=0;for(j=0;j<64;j=j+1)if(p[j])lg=j;
  if(p<=0)height=0;else if(lg>=26)height=15;else if(lg<=11)height=1;else height=lg-11;
 end endfunction
 reg signed[23:0]s1[0:15],s2[0:15];reg signed[15:0]x;
 reg[8:0]count;reg[3:0]bin;reg[2:0]state;
 reg signed[47:0]sq1,sq2,cross_product;
 reg signed[64:0]scaled_cross;
 reg[79:0]work,latest,snapshot;reg latest_valid;
 wire signed[40:0]recprod=$signed(s1[bin])*$signed(coef(bin));
 wire signed[41:0]next_state=$signed(x)+($signed(recprod)>>>14)-$signed(s2[bin]);
 wire signed[64:0]power=$signed({17'd0,sq1})+$signed({17'd0,sq2})-(scaled_cross>>>14);
 integer i;
 reg req_toggle,req_meta,req_sync,ack_toggle,ack_meta,ack_sync,busy;
 // The source snapshot is held until the NEXT request. Data enters only the
 // first synchronizer, never directly into the visible display registers.
 reg[79:0]data_meta,data_sync;reg settling;
 always @(posedge clk_a or negedge rst_a)begin
  if(!rst_a)begin
   count<=0;bin<=0;state<=0;x<=0;sq1<=0;sq2<=0;cross_product<=0;scaled_cross<=0;
   latest<=0;work<=0;latest_valid<=0;snapshot<=0;req_meta<=0;req_sync<=0;ack_toggle<=0;
   for(i=0;i<16;i=i+1)begin s1[i]<=0;s2[i]<=0;end
  end else begin
   req_meta<=req_toggle;req_sync<=req_meta;
   if(req_sync!=ack_toggle)begin snapshot<=latest_valid?latest:80'd0;ack_toggle<=req_sync;end
   case(state)
    0:if(sample_tick)begin x<=pcm>>>8;bin<=0;state<=1;end
    1:begin
     s2[bin]<=s1[bin];s1[bin]<=next_state[23:0];
     if(bin==15)begin
      bin<=0;
      if(count==511)begin state<=2;count<=0;end else begin count<=count+1'b1;state<=0;end
     end else bin<=bin+1'b1;
    end
    2:begin sq1<=$signed(s1[bin])*$signed(s1[bin]);sq2<=$signed(s2[bin])*$signed(s2[bin]);cross_product<=$signed(s1[bin])*$signed(s2[bin]);state<=3;end
    3:begin scaled_cross<=$signed(cross_product)*$signed(coef(bin));state<=4;end
    4:begin work[bin*5+:5]<=height(power);s1[bin]<=0;s2[bin]<=0;
      if(bin==15)state<=5;else begin bin<=bin+1'b1;state<=2;end
    end
    5:begin latest<=work;latest_valid<=1;state<=0;end
    default:state<=0;
   endcase
  end
 end
 always @(posedge clk_d or negedge rst_d)begin
  if(!rst_d)begin req_toggle<=0;ack_meta<=0;ack_sync<=0;busy<=0;ready<=0;bars<=0;data_meta<=0;data_sync<=0;settling<=0;end
  else begin
   ack_meta<=ack_toggle;ack_sync<=ack_meta;
   data_meta<=snapshot;data_sync<=data_meta;
   if(capture_req && !busy)begin req_toggle<=~req_toggle;busy<=1;ready<=0;settling<=0;end
   else if(busy && ack_sync==req_toggle)begin
    // One EXTRA display clock after ack observes a settled 2FF data bundle.
    if(!settling)settling<=1;
    else begin bars<=data_sync;ready<=1;busy<=0;settling<=0;end
   end
  end
 end
endmodule


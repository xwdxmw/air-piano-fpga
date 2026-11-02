`timescale 1ns/1ps
// Four INDEPENDENT parallel modal oscillators per voice. No inner TDM.
// Ratios approximate the web bell (1,2.756,5.404,8.933) with exact CSD shifts.
// Each mode has independent phase and Q15.16 decay. The shared voice envelope
// supplies velocity, anti-click attack and key-release damping.
module bell_partial #(
 parameter integer INDEX=0
)(input wire clk,rst_n,sample_tick,start,clear,run,
 input wire[35:0]freq,
 output wire signed[17:0]pcm,output wire nonzero);
 localparam[30:0]INITIAL=INDEX==0?31'd2147418112:
   INDEX==1?31'd1288437760:INDEX==2?31'd687144960:31'd386531328;
 reg[31:0]phase;
 reg[30:0]amp;
 reg signed[15:0]sine_q;
 wire freq_ok=freq<=36'd1932735283; // 0.45 Fs, compare BEFORE any truncation
 wire fade_band=freq>36'd1717986918; // 0.40 Fs starts an accelerated fade
 wire[31:0]next_phase=phase+(freq_ok?freq[31:0]:32'd0);
 wire[15:0]sine_val;
 sine_rom #(.D_WIDTH(16),.A_WIDTH(8)) u_sine(.addr(next_phase[31:24]),.dout(sine_val));
 // Combined natural/modal + overall web decay, rounded to multiplier-free CSD.
 // Effective tau at 47.9kHz: ~0.547/0.365/0.210/0.105 seconds.
 wire[30:0]natural_step=INDEX==0?((amp>>15)+(amp>>17)):
   INDEX==1?((amp>>14)-(amp>>18)):
   INDEX==2?((amp>>13)-(amp>>16)-(amp>>17)):
             ((amp>>12)-(amp>>15)-(amp>>16));
 wire[30:0]decay_step=fade_band?(amp>>6):natural_step;
 // Two independent 12x12 multipliers fit one physical DSP. Keep 16bit PCM
 // at the voice output; modal precision is explicitly 12bit (Q11 gain).
 wire signed[23:0]product=$signed(sine_q[15:4])*$signed({1'b0,amp[30:20]});
 assign nonzero=(amp!=0);
 assign pcm=(run && freq_ok)?(product>>>7):18'sd0;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin phase<=0;amp<=0;sine_q<=0;end
  else if(sample_tick)begin
   if(start)begin phase<=0;amp<=INITIAL;sine_q<=0;end
   else if(clear || !run)begin phase<=0;amp<=0;sine_q<=0;end
   else begin
    phase<=next_phase;sine_q<=$signed(sine_val);
    if(amp<=31'd65536)amp<=0; // below one PCM unit, terminate exactly
    else if(decay_step>=amp)amp<=0;
    else amp<=amp-((decay_step==0)?31'd1:decay_step);
   end
  end
 end
endmodule

module bell_bank(
 input wire clk,rst_n,sample_tick,start,clear,input wire[31:0]freq_ctrl,
 output wire signed[17:0]wave,output reg alive);
 wire[35:0]f={4'd0,freq_ctrl};
 wire[35:0]freq0=f;
 wire[35:0]freq1=(f<<1)+(f>>1)+(f>>2)+(f>>8)+(f>>9);
 wire[35:0]freq2=(f<<2)+f+(f>>2)+(f>>3)+(f>>5)-(f>>9);
 wire[35:0]freq3=(f<<3)+f-(f>>4)-(f>>8)-(f>>11);
 wire[143:0]frequencies={freq3,freq2,freq1,freq0};
 wire[71:0]partials;wire[3:0]nonzero;
 genvar i;generate for(i=0;i<4;i=i+1)begin:g_partial
  bell_partial #(.INDEX(i))u_p(.clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),.start(start),
   .clear(clear),.run(alive),.freq(frequencies[i*36+:36]),.pcm(partials[i*18+:18]),.nonzero(nonzero[i]));
 end endgenerate
 wire signed[19:0]sum=$signed(partials[17:0])+$signed(partials[35:18])+
                          $signed(partials[53:36])+$signed(partials[71:54]);
 // ~0.348 gain = 24000/(32767*2.1), bounded to signed16 before outer envelope.
 wire signed[19:0]normalized=(sum>>>2)+(sum>>>4)+(sum>>>5)+(sum>>>8);
 assign wave=normalized[17:0];
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)alive<=0;
  else if(sample_tick)begin
   if(start)alive<=1;
   else if(clear || nonzero==0)alive<=0;
  end
 end
endmodule

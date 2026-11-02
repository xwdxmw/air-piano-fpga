`timescale 1ns / 1ps

//--------------------------------------------------------------------
// SPI 单字节发送器（MSB first，屏在 SCLK 上升沿采样）
//--------------------------------------------------------------------
module spi_byte #(
    parameter integer DIV = 4          // SPI = clk/DIV，必须为偶数
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       req,
    input  wire       cmd,             // 1=命令(DC=0) 0=数据(DC=1)
    input  wire [7:0] data,
    output reg        busy,
    output reg        done,
    output reg        sclk,
    output reg        mosi,
    output reg        cs_n,
    output reg        dc
);
    reg [7:0] sr;
    reg [2:0] bi;
    localparam integer PW=(DIV>2)?$clog2(DIV):1;
    reg [PW-1:0] ph;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sclk <= 1'b0; mosi <= 1'b0; cs_n <= 1'b1; dc <= 1'b1;
            busy <= 1'b0; done <= 1'b0; bi <= 3'd7; ph <= 3'd0; sr <= 8'd0;
        end else begin
            done <= 1'b0;
            if (!busy) begin
                sclk <= 1'b0;
                if (req) begin
                    cs_n <= 1'b0;
                    dc   <= ~cmd;
                    sr   <= data;
                    mosi <= data[7];
                    bi   <= 3'd7;
                    ph   <= 3'd0;
                    busy <= 1'b1;
                end
            end else begin
                if (ph == (DIV/2 - 1)) begin
                    sclk <= 1'b1;
                    ph   <= ph + 3'd1;
                end else if (ph == (DIV - 1)) begin
                    ph   <= 3'd0;
                    sclk <= 1'b0;
                    if (bi == 3'd0) begin
                        busy <= 1'b0;
                        cs_n <= 1'b1;
                        done <= 1'b1;
                    end else begin
                        bi   <= bi - 3'd1;
                        mosi <= sr[bi-1];
                    end
                end else begin
                    ph <= ph + 3'd1;
                end
            end
        end
    end
endmodule


// Landscape ST7735. Build a palette frame in local RAM, then transmit it once.
// Never send a separate black-clear frame to the panel.
module lcd_panel #(
 parameter integer CLK_HZ=50000000,SCLK_DIV=4,
 parameter [7:0] MADCTL=8'h60,X_OFF=0,Y_OFF=0,
 parameter integer CAP_WAIT=2500000,FRAME_GAP=500000,DLY_120=6000000,DLY_20=1000000
)(input wire clk,rst_n,output wire lcd_sclk,lcd_mosi,lcd_cs_n,lcd_dc,
 output reg lcd_rst_n,lcd_bl,input wire mode,input wire[7:0]ir_v,
 input wire clk_audio,rst_audio_n,sample_tick_audio,input wire[15:0]pcm_audio,input wire[31:0]voice_active_audio,input wire guide_mode,test_mode,touch_state,keyboard_flute,input wire[2:0]guide_key,output reg ready);
 reg e_req,e_cmd;reg[7:0]e_data;wire e_busy,e_done;
 spi_byte #(.DIV(SCLK_DIV)) u_spi(.clk(clk),.rst_n(rst_n),.req(e_req),.cmd(e_cmd),.data(e_data),
 .busy(e_busy),.done(e_done),.sclk(lcd_sclk),.mosi(lcd_mosi),.cs_n(lcd_cs_n),.dc(lcd_dc));
 reg mode_meta,mode_sync,frame_mode;reg[7:0]ir_meta,ir_sync,frame_ir;
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin mode_meta<=0;mode_sync<=0;ir_meta<=0;ir_sync<=0;end
 else begin mode_meta<=mode;mode_sync<=mode_meta;ir_meta<=ir_v;ir_sync<=ir_meta;end end
 reg frame_guide,frame_test,frame_touch,frame_keyboard;reg[2:0]frame_key;
 reg capture_req,frame_has_scope;reg[6:0]rd_addr;wire scope_ready;wire[7:0]wave_y,liss_x,liss_y;
 scope_cap #(.TRIGGER_ENABLE(1)) u_scope(.clk_a(clk_audio),.rst_a(rst_audio_n),.sample_tick(sample_tick_audio),.pcm($signed(pcm_audio)),
 .clk_d(clk),.rst_d(rst_n),.raddr(rd_addr),.capture_req(capture_req),.ready(scope_ready),.wave_y(wave_y),.liss_x(liss_x),.liss_y(liss_y));
 wire[79:0]spectrum_bars;wire spectrum_ready;
 spectrum16 u_spectrum(.clk_a(clk_audio),.rst_a(rst_audio_n),.sample_tick(sample_tick_audio),.pcm($signed(pcm_audio)),
   .clk_d(clk),.rst_d(rst_n),.capture_req(capture_req),.bars(spectrum_bars),.ready(spectrum_ready));
 wire voice_ready;wire[31:0]voice_snapshot;wire[5:0]voice_count;
 voice_status_snapshot u_voices(.clk_a(clk_audio),.rst_a(rst_audio_n),.active(voice_active_audio),
   .clk_d(clk),.rst_d(rst_n),.capture_req(capture_req),.ready(voice_ready),.mask(voice_snapshot),.count(voice_count));
 reg[31:0]frame_voices;reg[5:0]frame_voice_count;reg frame_voice_valid;
 reg[79:0]frame_spectrum;
 reg[4:0]ini_i;reg[7:0]ini_b;reg ini_cmd;reg[1:0]ini_dly;localparam N_INI=20;
    always @(*) begin
        ini_cmd = 1'b1; ini_b = 8'h00; ini_dly = 2'd0;
        case (ini_i)
            5'd0 : begin ini_cmd=1; ini_b=8'h01; ini_dly=2'd1; end // SWRESET
            5'd1 : begin ini_cmd=1; ini_b=8'h11; ini_dly=2'd1; end // SLPOUT
            5'd2 : begin ini_cmd=1; ini_b=8'hB1; end                // FRMCTR1
            5'd3 : begin ini_cmd=0; ini_b=8'h01; end
            5'd4 : begin ini_cmd=0; ini_b=8'h2C; end
            5'd5 : begin ini_cmd=0; ini_b=8'h2D; end
            5'd6 : begin ini_cmd=1; ini_b=8'hC0; end                // PWCTR1
            5'd7 : begin ini_cmd=0; ini_b=8'hA2; end
            5'd8 : begin ini_cmd=0; ini_b=8'h02; end
            5'd9 : begin ini_cmd=0; ini_b=8'h84; end
            5'd10: begin ini_cmd=1; ini_b=8'hC1; end                // PWCTR2
            5'd11: begin ini_cmd=0; ini_b=8'hC5; end
            5'd12: begin ini_cmd=1; ini_b=8'hC5; end                // VMCTR1
            5'd13: begin ini_cmd=0; ini_b=8'h0E; end
            5'd14: begin ini_cmd=1; ini_b=8'h36; end                // MADCTL
            5'd15: begin ini_cmd=0; ini_b=MADCTL; end
            5'd16: begin ini_cmd=1; ini_b=8'h3A; end                // COLMOD
            5'd17: begin ini_cmd=0; ini_b=8'h05; end                // 16bit
            5'd18: begin ini_cmd=1; ini_b=8'h13; ini_dly=2'd2; end  // NORON
            default: begin ini_cmd=1; ini_b=8'h29; ini_dly=2'd1; end// DISPON
        endcase
    end


 function[34:0]glyph;input[7:0]ch;begin case(ch)
 8'h41:glyph={5'b01110,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
 8'h51:glyph={5'b01110,5'b10001,5'b10001,5'b10001,5'b10101,5'b10010,5'b01101};
 8'h30:glyph={5'b01110,5'b10001,5'b10011,5'b10101,5'b11001,5'b10001,5'b01110};
 8'h39:glyph={5'b01110,5'b10001,5'b10001,5'b01111,5'b00001,5'b00001,5'b01110};
 8'h2f:glyph={5'b00001,5'b00010,5'b00010,5'b00100,5'b01000,5'b01000,5'b10000};
 8'h50:glyph={5'b11110,5'b10001,5'b10001,5'b11110,5'b10000,5'b10000,5'b10000};
 8'h4d:glyph={5'b10001,5'b11011,5'b10101,5'b10101,5'b10001,5'b10001,5'b10001};
 8'h56:glyph={5'b10001,5'b10001,5'b10001,5'b10001,5'b01010,5'b01010,5'b00100};
 8'h57:glyph={5'b10001,5'b10001,5'b10001,5'b10101,5'b10101,5'b11011,5'b10001};
 8'h4c:glyph={5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b11111};
 8'h47:glyph={5'b01110,5'b10001,5'b10000,5'b10111,5'b10001,5'b10001,5'b01110};
 8'h4e:glyph={5'b10001,5'b11001,5'b11001,5'b10101,5'b10011,5'b10011,5'b10001};
 8'h54:glyph={5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100};
 8'h4b:glyph={5'b10001,5'b10010,5'b10100,5'b11000,5'b10100,5'b10010,5'b10001};
 8'h4a:glyph={5'b00111,5'b00010,5'b00010,5'b00010,5'b00010,5'b10010,5'b01100};
 8'h31:glyph={5'b00100,5'b01100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
 8'h32:glyph={5'b01110,5'b10001,5'b00001,5'b00010,5'b00100,5'b01000,5'b11111};
 8'h33:glyph={5'b11110,5'b00001,5'b00001,5'b01110,5'b00001,5'b00001,5'b11110};
 8'h34:glyph={5'b00010,5'b00110,5'b01010,5'b10010,5'b11111,5'b00010,5'b00010};
 8'h35:glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b00001,5'b00001,5'b11110};
 8'h36:glyph={5'b01110,5'b10000,5'b10000,5'b11110,5'b10001,5'b10001,5'b01110};
 8'h37:glyph={5'b11111,5'b00001,5'b00010,5'b00100,5'b01000,5'b01000,5'b01000};
 8'h38:glyph={5'b01110,5'b10001,5'b10001,5'b01110,5'b10001,5'b10001,5'b01110};
 default:glyph={5'b00000,5'b00000,5'b00000,5'b11111,5'b00000,5'b00000,5'b00000};
 endcase end endfunction
 function[14:0]address;input[7:0]x,y;begin address=({7'd0,y}<<7)+({7'd0,y}<<5)+x;end endfunction
 function[15:0]color;input[2:0]p;begin case(p)
 0:color=16'h0000;1:color=16'h0339;2:color=16'hfbe0;3:color=16'hf800;
 4:color=16'h07e0;5:color=16'h07ff;6:color=16'hffff;default:color=16'h2104;
 endcase end endfunction
 reg[2:0] frame_ram[0:20479];reg wr_en;reg[14:0]wr_addr,read_addr;reg[2:0]wr_data,read_q;
 always @(posedge clk)begin
 if(rst_n && wr_en)frame_ram[wr_addr]<=wr_data;
 read_q<=frame_ram[read_addr];
 end
 localparam POWER=0,INIT=1,WAIT_FRAME=2,CAPTURE=3,CLEAR=4,IR=5,LOAD=6,DRAW_W=7,DRAW_W2=8,DRAW_L=9,WINDOW=10,READ=11,PIXEL=12,DRAIN=13;
 reg[3:0]st;reg[31:0]dly,cap_wait;reg ini_wait;
 reg[7:0]x,y;reg[2:0]ir_idx;reg[3:0]ix,iy;reg[7:0]point_i;reg[1:0]load_count;
 reg[3:0]wsub;reg[14:0]pix;reg low_byte;reg[15:0]pixel_color;
 wire[34:0]head_glyph=glyph(frame_mode?8'h56:8'h2d),wave_glyph=glyph(8'h57),liss_glyph=glyph(frame_test?8'h56:8'h4c);
 wire[34:0]mode_glyph=glyph(frame_guide?8'h47:frame_test?8'h54:8'h4e),key_glyph=glyph(8'h31+frame_key),version_glyph=x<130?glyph(8'h41):x<136?glyph(8'h50):x<142?glyph(8'h30):glyph(8'h34);
 wire[7:0]version_x=x<130?8'd124:x<136?8'd130:x<142?8'd136:8'd142;
 reg[2:0]base_pixel;reg[5:0]glyph_idx;
 wire[3:0]voice_tens=frame_voice_count>=30 ? 4'd3 : frame_voice_count>=20 ? 4'd2 : frame_voice_count>=10 ? 4'd1 : 4'd0;
 wire[5:0]voice_ones=frame_voice_count-(voice_tens==3 ? 6'd30 : voice_tens==2 ? 6'd20 : voice_tens==1 ? 6'd10 : 6'd0);
 reg[7:0]voice_char,voice_char_x;reg[34:0]voice_glyph;
 reg[34:0]tens_glyph_q,ones_glyph_q;
 reg[5:0]header_row_q,footer_row_q;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin tens_glyph_q<=0;ones_glyph_q<=0;header_row_q<=0;footer_row_q<=0;end
  else begin
   tens_glyph_q<=glyph(frame_voice_valid?(8'h30+voice_tens):8'h2d);
   ones_glyph_q<=glyph(frame_voice_valid?(8'h30+voice_ones):8'h2d);
   // Raster y changes at x=0; first font pixel is x=4, allowing this stage to settle.
   header_row_q<=(y-4)*5;footer_row_q<=(y-105)*5;
  end
 end
 wire[1:0]slot_col=(x>=144) ? 2'd3 : (x>=130) ? 2'd2 : (x>=116) ? 2'd1 : 2'd0;
 wire[7:0]slot_x=x-(8'd102+({6'd0,slot_col}<<3)+({6'd0,slot_col}<<2)+({6'd0,slot_col}<<1));
 wire[7:0]slot_y=y-8'd40;wire[4:0]slot_index={slot_y[5:3],slot_col};
 wire[7:0]spec_x=x-8'd2;
 // Used only for x=2..157, so spec_x=0..155. Fixed range decode avoids a divider.
 wire[3:0]spec_bin=spec_x>=150?15:spec_x>=140?14:spec_x>=130?13:spec_x>=120?12:
  spec_x>=110?11:spec_x>=100?10:spec_x>=90?9:spec_x>=80?8:spec_x>=70?7:
  spec_x>=60?6:spec_x>=50?5:spec_x>=40?4:spec_x>=30?3:spec_x>=20?2:spec_x>=10?1:0;
 wire[7:0]spec_origin=({4'd0,spec_bin}<<3)+({4'd0,spec_bin}<<1);
 wire[3:0]spec_column=spec_x-spec_origin;
 always @(*)begin
 base_pixel=0;glyph_idx=0;voice_char=8'h56;voice_char_x=84;voice_glyph=0;
 if(x<90)begin voice_char=8'h56;voice_char_x=84;end
 else if(x<96)begin voice_char=frame_voice_valid?(8'h30+voice_tens):8'h2d;voice_char_x=90;end
 else if(x<102)begin voice_char=frame_voice_valid?(8'h30+voice_ones):8'h2d;voice_char_x=96;end
 else if(x<108)begin voice_char=8'h2f;voice_char_x=102;end
 else if(x<114)begin voice_char=8'h33;voice_char_x=108;end
 else begin voice_char=8'h32;voice_char_x=114;end
 voice_glyph=x<90?glyph(8'h56):x<96?tens_glyph_q:x<102?ones_glyph_q:x<108?glyph(8'h2f):x<114?glyph(8'h33):glyph(8'h32);
 if(y<16)base_pixel=frame_mode?2:1;
 if(y>=4 && y<=10 && x>=4 && x<=8)begin glyph_idx=header_row_q+x-4;if(head_glyph[34-glyph_idx])base_pixel=6;end
 if(y>=4 && y<=10 && x>=16 && x<=20)begin glyph_idx=header_row_q+x-16;if(mode_glyph[34-glyph_idx])base_pixel=6;end
 if(frame_guide && y>=4 && y<=10 && x>=25 && x<=29)begin glyph_idx=header_row_q+x-25;if(key_glyph[34-glyph_idx])base_pixel=6;end
 if(y>=4 && y<=10 && x>=36 && x<=40)base_pixel=frame_touch?6:7;
 if(y>=4 && y<=10 && x>=124 && x<=146 && x-version_x<5)begin glyph_idx=header_row_q+x-version_x;if(version_glyph[34-glyph_idx])base_pixel=6;end
 if(y>=105 && y<=111 && x>=4 && x<=8)begin glyph_idx=footer_row_q+x-4;if(wave_glyph[34-glyph_idx])base_pixel=6;end
 if(y>=105 && y<=111 && x>=106 && x<=110)begin glyph_idx=footer_row_q+x-106;if(liss_glyph[34-glyph_idx])base_pixel=6;end
 // Two timbre blocks: left=keyboard, right=IR harp. White=bell, cyan=flute, green=IR harp.
 if(y>=4 && y<=10 && x>=58 && x<=64)base_pixel=frame_keyboard?5:6;
 if(y>=4 && y<=10 && x>=68 && x<=74)base_pixel=4;
 if(y>=4 && y<=10 && x>=84 && x<=118)begin
   if(x-voice_char_x<5)begin glyph_idx=header_row_q+x-voice_char_x;if(voice_glyph[34-glyph_idx])base_pixel=6;end
 end
 if(frame_test && y>=40 && y<104 && x>=102 && x<158 && slot_x<12 && slot_y[2:0]<6)
   base_pixel=(frame_voice_valid && frame_voices[slot_index])?4:7;
 if(y>=113 && y<=127 && x>=2 && x<158)begin
   if(spec_column<8 && frame_spectrum[spec_bin*5+:5] > 127-y)base_pixel=2;
 end
 if((y==36 || y==104) || (y>=36 && y<=104 && (x==0 || x==99 || x==159)))base_pixel=7;
 if(y==70 && x>=2 && x<=97)base_pixel=7;
 if(!frame_test && y==69 && x>=102 && x<=152)base_pixel=7;
 end
 wire[7:0]wx=2+((point_i*3)>>2),wy=42+(frame_has_scope?wave_y:28);
 wire[7:0]lx=102+(frame_has_scope?liss_x:25),ly=44+(frame_has_scope?liss_y:25);
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin
 st<=POWER;dly<=0;cap_wait<=0;ini_i<=0;ini_wait<=0;e_req<=0;e_cmd<=1;e_data<=0;
 lcd_rst_n<=0;lcd_bl<=0;ready<=0;capture_req<=0;frame_has_scope<=0;frame_mode<=0;frame_ir<=0;frame_guide<=0;frame_test<=0;frame_touch<=0;frame_key<=0;frame_keyboard<=0;frame_spectrum<=0;frame_voices<=0;frame_voice_count<=0;frame_voice_valid<=0;
 wr_en<=0;wr_addr<=0;wr_data<=0;read_addr<=0;x<=0;y<=0;ir_idx<=0;ix<=0;iy<=0;
 point_i<=0;rd_addr<=0;load_count<=0;wsub<=0;pix<=0;low_byte<=0;pixel_color<=0;
 end else begin
 e_req<=0;wr_en<=0;capture_req<=0;
 case(st)
 POWER:if(dly>=DLY_20)begin lcd_rst_n<=1;lcd_bl<=1;dly<=0;st<=INIT;end else dly<=dly+1'b1;
 INIT:begin
 if(ini_wait)begin if(e_done)begin ini_wait<=0;if(ini_dly==1)dly<=DLY_120;else if(ini_dly==2)dly<=DLY_20;
 if(ini_i==N_INI-1)st<=WAIT_FRAME;else ini_i<=ini_i+1'b1;end end
 else if(dly!=0)dly<=dly-1'b1;
 else if(!e_busy && !e_req)begin e_cmd<=ini_cmd;e_data<=ini_b;e_req<=1;ini_wait<=1;end
 end
 WAIT_FRAME:if(dly!=0)dly<=dly-1'b1;else begin capture_req<=1;cap_wait<=0;frame_has_scope<=0;frame_mode<=mode_sync;frame_ir<=ir_sync;frame_guide<=guide_mode;frame_test<=test_mode;frame_touch<=touch_state;frame_key<=guide_key;frame_keyboard<=keyboard_flute;st<=CAPTURE;end
 CAPTURE:if(cap_wait>=3 && ((scope_ready && voice_ready) || cap_wait>=CAP_WAIT))begin frame_has_scope<=scope_ready;frame_voice_valid<=voice_ready;frame_voices<=voice_ready?voice_snapshot:32'd0;frame_voice_count<=voice_ready?voice_count:6'd0;frame_spectrum<=spectrum_ready?spectrum_bars:80'd0;x<=0;y<=0;st<=CLEAR;end else cap_wait<=cap_wait+1'b1;
 CLEAR:begin
 wr_en<=1;wr_addr<=address(x,y);wr_data<=base_pixel;
 if(x==159)begin x<=0;if(y==127)begin ir_idx<=0;ix<=0;iy<=0;st<=IR;end else y<=y+1'b1;end else x<=x+1'b1;
 end
 IR:begin
 wr_en<=1;wr_addr<=address(6+ir_idx*19+ix,22+iy);wr_data<=frame_ir[ir_idx]?3:0;
 if(ix==9)begin ix<=0;if(iy==7)begin iy<=0;if(ir_idx==7)begin point_i<=0;rd_addr<=0;load_count<=0;st<=LOAD;end else ir_idx<=ir_idx+1'b1;end else iy<=iy+1'b1;end else ix<=ix+1'b1;
 end
 LOAD:begin rd_addr<=point_i[6:0];if(load_count==2)begin load_count<=0;st<=point_i<128?DRAW_W:DRAW_L;end else load_count<=load_count+1'b1;end
 DRAW_W:begin wr_en<=1;wr_addr<=address(wx,wy);wr_data<=4;st<=DRAW_W2;end
 DRAW_W2:begin
 wr_en<=1;wr_addr<=address(wx,wy+1'b1);wr_data<=4;
 point_i<=point_i+1'b1;rd_addr<=point_i[6:0]+1'b1;load_count<=0;st<=LOAD;
 end
 DRAW_L:begin
 if(!frame_test)begin wr_en<=1;wr_addr<=address(lx,ly);wr_data<=5;end
 if(point_i==191)begin wsub<=0;pix<=0;read_addr<=0;st<=WINDOW;end
 else begin point_i<=point_i+1'b1;rd_addr<=point_i[6:0]+1'b1;load_count<=0;st<=LOAD;end
 end
 WINDOW:if(!e_busy && !e_req)begin
 e_cmd<=0;
 case(wsub)
 0:begin e_cmd<=1;e_data<=8'h2a;end
 1:e_data<=0;2:e_data<=X_OFF;3:e_data<=0;4:e_data<=159+X_OFF;
 5:begin e_cmd<=1;e_data<=8'h2b;end
 6:e_data<=0;7:e_data<=Y_OFF;8:e_data<=0;9:e_data<=127+Y_OFF;
 default:begin e_cmd<=1;e_data<=8'h2c;end
 endcase
 e_req<=1;if(wsub==10)begin load_count<=0;st<=READ;end else wsub<=wsub+1'b1;
 end
 READ:begin
 read_addr<=pix;
 if(load_count==2)begin pixel_color<=color(read_q);low_byte<=0;load_count<=0;st<=PIXEL;end else load_count<=load_count+1'b1;
 end
 PIXEL:if(!e_busy && !e_req)begin
 e_cmd<=0;e_req<=1;e_data<=low_byte?pixel_color[7:0]:pixel_color[15:8];
 if(!low_byte)low_byte<=1;
 else if(pix==20479)st<=DRAIN;
 else begin pix<=pix+1'b1;read_addr<=pix+1'b1;load_count<=0;st<=READ;end
 end
 DRAIN:if(!e_busy && !e_req)begin ready<=1;dly<=FRAME_GAP;st<=WAIT_FRAME;end
 default:st<=POWER;
 endcase
 end end
endmodule


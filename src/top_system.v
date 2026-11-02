`timescale 1ns / 1ps
//====================================================================
// top_system.v —— Air Piano 最终顶层
//   c_interact_top (50MHz 域) → 事件队列(event_fifo,16深) → 4-phase握手 → top_board
//
// 事件 payload（19bit，owner在[18:17]）：
//   [16]   timbre  0=钟琴 1=键盘笛子/红外竖琴，由owner区分（NOTE_ON时锁存，尾音不随切模式变音色）
//   [15:14] type   00=NOTE_ON 01=NOTE_OFF 10=ALL_NOTES_OFF 11=预留
//   [13:7]  num    音符编号 0~127
//   [6:0]   vel    力度 0~127
//====================================================================
module top_system #(
    parameter USE_ADC  = 0,     // 光电走 ADC 还是 GPIO（0=GPIO）
    parameter USE_DEMO = 0,     // 1=演示序列器（无传感器也能出声，内部自动播放）
                                // 0=传感器交互（c_interact_top），传感器接入后改回 0
    parameter USE_POLY32 = 0,   // 1=32复音测试序列（poly32_seq，频谱数32峰），优先级最高
    parameter [7:0] KEY_MASK = 8'hFF, // 压力键使能：bit0=AIN0 ... bit7=AIN7；0xFF=8 路全开
    parameter integer BOOT_SEL_MS = 500, // 上电采样 TTP 的时刻(ms)：按住=32音测试模式
    parameter integer FIXED_SEMITONES=0, // fixed fine transposition; gesture adds +/-2 octaves
    parameter [7:0] LCD_X_OFF=0,LCD_Y_OFF=0,LCD_MADCTL=8'h60,
    parameter integer DIAG_LED = 0       // 1=4 个 LED 改为显示"超阈值通道数"，调试用
)(
    input  wire clk_50m,
    input  wire rst_n,
    input  wire [7:0]        sensor_gpio,
    input  wire              touch_raw,
    input wire key_bend_n, key_timbre_n, // Dock key0=F15, key1=G15, active-low
    input  wire              calib_run_p,
    input  wire              calib_run_o,
    input  wire              calib_clear,
    //---- ADS1256 24bit ADC（8 路 FSR 压力）物理 SPI 接口 ----
    output wire              ads_sclk,       // → 模块 SCLK
    output wire              ads_mosi,       // → 模块 DIN（主机发/从机收）
    input  wire              ads_miso,       // ← 模块 DOUT
    output wire              ads_cs_n,       // → 模块 CS
    input  wire              ads_drdy,       // ← 模块独立 DRDY；不可用 DOUT 代替
    output wire              ads_reset_n,    // → 模块 RESET
    output wire bclk, ws, dacdat,            // I2S → 板载 PT8211
    inout  wire i2c_sda,                     // PT8211 免配置，恒高阻
    // ---- 状态指示（Dock 板橙色 LED 为共阳接 3V3，【低电平点亮】）----
    output wire led_raw,    // 亮=ADS1256 任意通道读到 >60 码（模拟前端通）
    output wire led_pll,    // 亮=PLL 已锁定（音频域活着）
    output wire led_key,    // 亮=有 FSR 键处于按下（>180 码）
    output wire led_adc,    // 慢闪(~3Hz)=ADS1256 驱动在不断出 adc_valid
    // ---- ST7735 SPI 小屏（接 PMOD0，只用 4 根线）----
    //   屏的 RES/RST 与 BL/LED 直接接 3.3V（背光常亮、上电由屏内 POR 复位），
    //   不占用 FPGA 引脚（R16/N17 是 CPU/SSPI 专用脚，不可用作普通 IO）
    output wire lcd_sclk,   // SPI 时钟 12.5MHz
    output wire lcd_mosi,   // SPI 数据
    output wire lcd_cs_n,   // 片选
    output wire lcd_dc,     // 命令/数据
    // ---- 拓展4：脱机 LED 演奏指引（30颗WS2812，前8提示）----
    output wire ws2812      // 接灯带 DIN（C21）
);


    wire boot_done,test_latched,guide_latched;
    reg touch_meta,touch_sync;
    always @(posedge clk_50m or negedge rst_n)begin
      if(!rst_n)begin touch_meta<=0;touch_sync<=0;end
      else begin touch_meta<=touch_raw;touch_sync<=touch_meta;end
    end
    boot_select #(.FIRST_MS(BOOT_SEL_MS)) u_boot(.clk(clk_50m),.rst_n(rst_n),.touch(touch_sync),
      .done(boot_done),.test_mode(test_latched),.guide_mode(guide_latched));
    wire guide_toggle;reg runtime_override,runtime_guide;
    wire test_mode=boot_done && (USE_POLY32 || (!runtime_override && test_latched));
    wire guide_mode=boot_done && !test_mode && (runtime_override?runtime_guide:guide_latched);
    always @(posedge clk_50m or negedge rst_n)begin
      if(!rst_n)begin runtime_override<=0;runtime_guide<=0;end
      else if(guide_toggle && !test_mode)begin runtime_override<=1;runtime_guide<=!guide_mode;end
    end
    wire touch_clean,vibrato,gesture_changed;wire signed[2:0] octave;
    c_sync_debounce #(.DB_CNT(500000)) u_touch_db(.clk(clk_50m),.rst_n(rst_n),.din(touch_raw),.dout(touch_clean),.rise(),.fall());
    ttp_gestures u_ttp(.clk(clk_50m),.rst_n(rst_n),.enable(boot_done && !test_mode),.touch(touch_clean),.play_enable(!test_mode),
      .vibrato(vibrato),.changed(gesture_changed),.octave(octave),.guide_toggle(guide_toggle));

    wire keyboard_flute;wire[6:0] manual_bend;
    performance_controls u_controls(.clk(clk_50m),.rst_n(rst_n),.enable(boot_done && !test_mode),
      .bend_n(key_bend_n),.timbre_n(key_timbre_n),.keyboard_flute(keyboard_flute),.bend(manual_bend));
    wire[95:0] ads_adc_data;wire ads_adc_valid,ads_ch_valid;wire[2:0] ads_ch_idx;wire[11:0] ads_ch_data;
    ads1256_driver #(.CLK_FREQ_HZ(50000000),.CH_NUM(8),.ADC_W(12),.SCLK_DIV(32)) u_ads(
      .clk(clk_50m),.rst_n(rst_n),.ads_sclk(ads_sclk),.ads_mosi(ads_mosi),.ads_miso(ads_miso),
      .ads_cs_n(ads_cs_n),.ads_drdy(ads_drdy),.ads_reset_n(ads_reset_n),.adc_data(ads_adc_data),
      .adc_valid(ads_adc_valid),.ch_valid(ads_ch_valid),.ch_idx(ads_ch_idx),.ch_data(ads_ch_data));
    wire sw_on,sw_off,sw_vu,sw_timbre;wire[6:0] sw_num,sw_vel,sw_offnum,sw_at,sw_vunum,sw_vuvel;
    wire[7:0] key_on_debug,channel_ready,channel_stale,string_blocked;wire harp_overflow;
    c_interact_top #(.WIDTH(8),.ADC_W(12),.CLK_FREQ_HZ(50000000),.USE_ADC(USE_ADC),.KEY_MASK(KEY_MASK),.IR_ACTIVE_LOW(1)) u_interact(
      .clk(clk_50m),.rst_n(rst_n),.sensor_gpio(sensor_gpio),.adc_p(ads_adc_data),.adc_valid(ads_adc_valid),
      .adc_ch_valid(ads_ch_valid),.adc_ch_idx(ads_ch_idx),.adc_ch_data(ads_ch_data),.adc_o(96'd0),.touch_raw(1'b0),
      .calib_run_p(1'b0),.calib_run_o(1'b0),.calib_clear(!boot_done || test_mode),
      .note_on(sw_on),.note_num(sw_num),.velocity(sw_vel),.note_off(sw_off),.note_off_num(sw_offnum),
      .aftertouch(sw_at),.velupd(sw_vu),.velupd_num(sw_vunum),.velupd_vel(sw_vuvel),.event_timbre(sw_timbre),
      .mode(),.mode_changed(),.all_notes_off(),.string_blocked(string_blocked),.key_on(key_on_debug),
      .calib_done_p(),.calib_done_o(),.pressure_ready(channel_ready),.pressure_stale(channel_stale),
      .harp_overflow(harp_overflow),.strum_dir(),.strum_valid());
    wire tp_on,tp_off,tp_ano;wire[6:0] tp_num,tp_vel,tp_offnum;
    poly32_seq u_poly32(.clk(clk_50m),.rst_n(rst_n && test_mode),.note_on(tp_on),.note_num(tp_num),.velocity(tp_vel),
      .note_off(tp_off),.note_off_num(tp_offnum),.all_notes_off(tp_ano),.mode());
    wire dm_on,dm_off,dm_ano;wire[6:0] dm_num,dm_vel,dm_offnum;
    generate if(USE_DEMO)begin: demo
      demo_seq #(.CLK_FREQ_HZ(50000000)) u_demo(.clk(clk_50m),.rst_n(rst_n && boot_done),
       .note_on(dm_on),.note_num(dm_num),.velocity(dm_vel),.note_off(dm_off),.note_off_num(dm_offnum),.all_notes_off(dm_ano),.mode());
    end else begin: no_demo
      assign dm_on=0;assign dm_off=0;assign dm_ano=0;assign dm_num=0;assign dm_vel=0;assign dm_offnum=0;
    end endgenerate
    wire live=boot_done && !test_mode && !USE_DEMO;
    wire note_on_c=live && sw_on,note_off_c=live && sw_off,velupd_c=live && sw_vu;
    wire[6:0] live_on_pitch,live_off_pitch,live_vu_pitch;
    note_transpose #(.FIXED_SEMITONES(FIXED_SEMITONES)) u_transpose(
      .clk(clk_50m),.rst_n(rst_n),.octave(octave),.on(note_on_c),.harp(sw_timbre),.num(sw_num),
      .off(note_off_c),.off_num(sw_offnum),.vu(velupd_c),.vu_num(sw_vunum),
      .on_pitch(live_on_pitch),.off_pitch(live_off_pitch),.vu_pitch(live_vu_pitch));
    wire g_on,g_off,g_guide,g_hit,g_led;wire[6:0] g_num,g_vel,g_offnum;wire[2:0] g_key;
    guide_seq u_guide(.clk(clk_50m),.rst_n(rst_n),.enable(guide_mode),.key_on(key_on_debug),
      .note_on(g_on),.note_num(g_num),.velocity(g_vel),.note_off(g_off),.note_off_num(g_offnum),
      .cur_key(g_key),.guiding(g_guide),.led_on(g_led),.hit(g_hit));
    function[6:0] transpose_note;input[6:0] n;input signed[2:0] oct;integer v;begin
      v=$signed({1'b0,n})+$signed(oct)*12+FIXED_SEMITONES;
      if(v<0)transpose_note=0;else if(v>127)transpose_note=127;else transpose_note=v[6:0];
    end endfunction
    reg[6:0] guide_pitch;
    always @(posedge clk_50m or negedge rst_n)if(!rst_n)guide_pitch<=60;else if(g_on)guide_pitch<=transpose_note(g_num,octave);

    // Payload [18:17] owner: piano=0,harp=1,demo/test=2,guide=3.
    // Every event has a separate lane; never OR candidate events together.
    wire[7:0] incoming;
    wire[151:0] incoming_data;
    assign incoming=guide_toggle?8'b00000001:{g_off,g_on,(test_mode && tp_off)||(!test_mode && dm_off),
      (test_mode && tp_on)||(!test_mode && dm_on),velupd_c,note_off_c,note_on_c,
      (test_mode && tp_ano)||(!test_mode && dm_ano)};
    assign incoming_data[0*19+:19]={2'd2,1'b0,2'b10,7'd0,7'd0};
    assign incoming_data[1*19+:19]={sw_timbre?2'd1:2'd0,(sw_timbre || keyboard_flute),2'b00,live_on_pitch,sw_vel};
    assign incoming_data[2*19+:19]={2'd0,1'b0,2'b01,live_off_pitch,7'd0};
    assign incoming_data[3*19+:19]={2'd0,1'b0,2'b11,live_vu_pitch,sw_vuvel};
    assign incoming_data[4*19+:19]={2'd2,1'b0,2'b00,test_mode?tp_num:dm_num,test_mode?tp_vel:dm_vel};
    assign incoming_data[5*19+:19]={2'd2,1'b0,2'b01,test_mode?tp_offnum:dm_offnum,7'd0};
    assign incoming_data[6*19+:19]={2'd3,1'b0,2'b00,transpose_note(g_num,octave),g_vel};
    assign incoming_data[7*19+:19]={2'd3,1'b0,2'b01,guide_pitch,7'd0};
    wire[18:0] q_out;wire q_empty,q_full,dropped;wire pop;
    event_queue_multi #(.LANES(8),.DW(19),.DEPTH(64),.AW(6)) u_events(
      .clk(clk_50m),.rst_n(rst_n),.push(incoming),.data(incoming_data),.pop(pop),
      .head(q_out),.empty(q_empty),.full(q_full),.overflow(dropped));
    localparam S_IDLE=0,S_ASSERT=1,S_WAIT_HI=2,S_WAIT_LO=3;
    reg[1:0] tx_state;reg ev_req;reg[18:0] ev_payload;
    wire event_ack_board;reg ack1,ack2;
    always @(posedge clk_50m or negedge rst_n)begin
      if(!rst_n)begin ack1<=0;ack2<=0;end else begin ack1<=event_ack_board;ack2<=ack1;end
    end
    assign pop=tx_state==S_IDLE && !q_empty;
    always @(posedge clk_50m or negedge rst_n)begin
      if(!rst_n)begin tx_state<=S_IDLE;ev_req<=0;ev_payload<=0;end
      else case(tx_state)
        S_IDLE:begin ev_req<=0;if(!q_empty)begin ev_payload<=q_out;tx_state<=S_ASSERT;end end
        S_ASSERT:begin ev_req<=1;tx_state<=S_WAIT_HI;end
        S_WAIT_HI:if(ack2)begin ev_req<=0;tx_state<=S_WAIT_LO;end
        S_WAIT_LO:if(!ack2)tx_state<=S_IDLE;
      endcase
    end
    // Queue overflow is visible only; it does NOT latch global audio reset/mute.
    wire diagnostic_warning=dropped || harp_overflow;
    wire any_key=|key_on_debug;
    wire[6:0] bend_w=test_mode?7'd64:manual_bend; // independent of FSR velocity/aftertouch
    reg[6:0]bend_gray;
    always @(posedge clk_50m or negedge rst_n)if(!rst_n)bend_gray<=7'd96;else bend_gray<=(bend_w>>1)^bend_w;
    wire[31:0] voice_active_w;
    wire pll_locked_w,audio_clk_w,audio_rst_w,audio_tick_w;wire[15:0] pcm_mon_w;
    top_board #(.USE_ENGINE(1),.BEND_GRAY(1)) u_board(.clk_50m(clk_50m),.rst_n(rst_n),.event_req(ev_req),
      .event_payload(ev_payload),.event_ack(event_ack_board),.mode(vibrato),.bend(bend_gray),
      .bclk(bclk),.ws(ws),.dacdat(dacdat),.mclk(),.i2c_sda(i2c_sda),.i2c_scl(),.codec_ready(),
      .active_debug(voice_active_w),.pcm_mix_debug(),.pll_locked_o(pll_locked_w),.audio_clk_o(audio_clk_w),
      .audio_rst_o(audio_rst_w),.audio_tick_o(audio_tick_w),.pcm_mon_o(pcm_mon_w));

    wire[191:0] led_grb;reg[23:0] hb_div;reg[19:0] fresh_age;
    always @(posedge clk_50m or negedge rst_n)begin
      if(!rst_n)begin hb_div<=0;fresh_age<=1000000;end
      else begin hb_div<=hb_div+1'b1;if(ads_ch_valid)fresh_age<=0;else if(fresh_age<1000000)fresh_age<=fresh_age+1'b1;end
    end
    wire adc_fresh=fresh_age<1000000;
    reg any_raw;integer ci;reg[3:0] bad_cnt;
    always @(*)begin any_raw=0;bad_cnt=0;for(ci=0;ci<8;ci=ci+1)begin
      if(ads_adc_data[ci*12+:12]>60)any_raw=1;
      if(ads_adc_data[ci*12+:12]>180)bad_cnt=bad_cnt+1'b1;
    end end
    assign led_raw=DIAG_LED?~bad_cnt[0]:diagnostic_warning?hb_div[21]:~any_raw;
    assign led_pll=DIAG_LED?~bad_cnt[2]:~pll_locked_w;
    assign led_key=DIAG_LED?~bad_cnt[1]:~any_key;
    assign led_adc=DIAG_LED?~bad_cnt[3]:(adc_fresh?hb_div[22]:1'b1);
    // Keep G guide colors/gates intact. In N, display both real FSR and debounced IR.
    wire[191:0] guide_led_grb,live_led_grb;
    guide_led_map u_led_map(.guide_mode(guide_mode),.gate(g_led),.hit(g_hit),.target(g_key),.keys(key_on_debug),.grb(guide_led_grb));
    live_led_follow u_live_led(.clk(clk_50m),.rst_n(rst_n),
      .enable(boot_done && !test_mode && !guide_mode),.keys(key_on_debug),.strings(string_blocked),.grb(live_led_grb));
    assign led_grb=guide_mode?guide_led_grb:live_led_grb;
    wire led_selftest_active;wire[191:0]led_selftest_grb;
    led_startup_test u_led_selftest(.clk(clk_50m),.rst_n(rst_n),.active(led_selftest_active),.grb(led_selftest_grb));
    // 30 physical pixels: first 8 are key hints; pixels 9..30 are cleared every frame.
    wire[719:0] strip_grb={528'd0,led_selftest_active?led_selftest_grb:led_grb};
    ws2812_tx #(.N_LED(30)) u_ws(.clk(clk_50m),.rst_n(rst_n),.grb(strip_grb),.dout(ws2812));
    lcd_panel #(.CLK_HZ(50000000),.SCLK_DIV(4),.X_OFF(LCD_X_OFF),.Y_OFF(LCD_Y_OFF),.MADCTL(LCD_MADCTL)) u_lcd(
      .clk(clk_50m),.rst_n(rst_n),.lcd_sclk(lcd_sclk),.lcd_mosi(lcd_mosi),.lcd_cs_n(lcd_cs_n),.lcd_dc(lcd_dc),
      .lcd_rst_n(),.lcd_bl(),.mode(vibrato),.ir_v(string_blocked),.clk_audio(audio_clk_w),.rst_audio_n(audio_rst_w),
      .sample_tick_audio(audio_tick_w),.pcm_audio(pcm_mon_w),.voice_active_audio(voice_active_w),.guide_mode(guide_mode),.test_mode(test_mode),.touch_state(touch_clean),.keyboard_flute(keyboard_flute),.guide_key(g_key),.ready());
endmodule

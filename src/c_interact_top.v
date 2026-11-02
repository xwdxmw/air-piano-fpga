`timescale 1ns / 1ps
//====================================================================
// c_interact_top  交互顶层（方案1 · 分模块拼装）
//   压力钢琴 pressure_detect
//   光电竖琴 optical_harp
//   电容切换 cap_touch
//   标定     pressure_calib / optical_calib
//   适配     c_to_voice_adapter → voice.v
//
//   板卡：Tang Mega 138K Pro，GW5AST-LV138FPG676A
//   时钟：top_system 显式传入 CLK_FREQ_HZ=50_000_000（交互域，与音频域 12.288M 不同）
//====================================================================
module c_interact_top #(
    parameter integer WIDTH       = 8,
    parameter integer ADC_W       = 12,
    parameter integer USE_ADC     = 0,
    parameter [7:0]   KEY_MASK    = 8'hFF,  // bitg=1 才启用 AINg；0xFF=8 路全开
    parameter integer CLK_FREQ_HZ = 50_000_000,
    // 红外对射模块 DO 极性：
    //   IR_ACTIVE_LOW=1 → 模块在【遮挡】时 DO 输出低电平（绝大多数 LM393 开漏输出如此），
    //                     内部对 sensor_gpio 取反，归一化成“遮挡=1”；
    //   IR_ACTIVE_LOW=0 → 模块遮挡时 DO 输出高电平，直接使用。
    // 上板用万用表量 DO：遮挡时为低则保持 1，为高则改为 0 重新综合。
    parameter integer IR_ACTIVE_LOW = 1
)(
    input  wire                   clk,
    input  wire                   rst_n,

    // 传感器
    input  wire [WIDTH-1:0]       sensor_gpio,   // 光电数字（1=遮挡）
    input  wire [ADC_W*WIDTH-1:0] adc_p,         // 8 路压力
    input  wire                   adc_valid,     // 整轮握手（8 路都采完，1 拍）
    input  wire                   adc_ch_valid,  // 逐通道握手（每采完一路 1 拍）
    input  wire [2:0]             adc_ch_idx,    // 该路通道号
    input  wire [ADC_W-1:0]       adc_ch_data,   // 该路数据
    input  wire [ADC_W*WIDTH-1:0] adc_o,         // 8 路光电 ADC(USE_ADC=1)
    input  wire                   touch_raw,

    // 标定控制
    input  wire                   calib_run_p,
    input  wire                   calib_run_o,
    input  wire                   calib_clear,

    // → voice.v（NOTE_ON / NOTE_OFF 事件，编号跟事件）
    output wire                   note_on,
    output wire [6:0]             note_num,
    output wire [6:0]             velocity,
    output wire                   note_off,
    output wire [6:0]             note_off_num,
    output wire [6:0]             aftertouch,

    // → 力度修正事件（NOTE_ON 已先行发出，2.7ms 后补一次真实力度）
    output wire                   velupd,
    output wire [6:0]             velupd_num,
    output wire [6:0]             velupd_vel,

    // 每个事件自带的音色（双音色常开：钢琴=0 竖琴=1）
    output wire                   event_timbre,

    // 模式
    output wire                   mode,
    output wire                   mode_changed,
    output wire                   all_notes_off,

    // 调试
    output wire [WIDTH-1:0]       string_blocked,
    output wire [WIDTH-1:0]       key_on,
    output wire                   calib_done_p,
    output wire                   calib_done_o,
    output wire [WIDTH-1:0] pressure_ready, pressure_stale,
    output wire harp_overflow,
    output wire [1:0]             strum_dir,
    output wire                   strum_valid
);

    // ---------- 电容消抖 ----------
    wire touch;
    c_sync_debounce #(.DB_CNT(2000)) u_db_touch (
        .clk(clk), .rst_n(rst_n),
        .din(touch_raw), .dout(touch),
        .rise(), .fall()
    );

    // ---------- 光电输入 ----------
    // 极性归一化：成品红外对射模块遮挡时 DO 多为低（LM393 开漏），按 IR_ACTIVE_LOW
    // 取反后，sensor_pol 保证“遮挡=1、光路通=0”，再进消抖。
    wire [WIDTH-1:0] sensor_pol = IR_ACTIVE_LOW ? ~sensor_gpio : sensor_gpio;
    wire [WIDTH-1:0] str_blk;
    generate
        if (USE_ADC == 0) begin : g_gpio
            genvar s;
            for (s = 0; s < WIDTH; s = s + 1) begin : g_db
                // DB_CNT=2000：50MHz 下约 40µs 消抖。手指遮挡为 ms 级，40µs 不误判，
                // 又能滤掉手扫过临界区、环境光造成的 μs 级毛刺；另有 30ms 不应期兜底。
                c_sync_debounce #(.DB_CNT(2000)) u_db_opt (
                    .clk(clk), .rst_n(rst_n),
                    .din(sensor_pol[s]), .dout(str_blk[s]),
                    .rise(), .fall()
                );
            end
        end else begin : g_adc
            wire [ADC_W-1:0] th_b, th_o;
            wire             th_load_o;
            optical_calib #(.ADC_W(ADC_W), .WIDTH(WIDTH), .CLK_FREQ_HZ(CLK_FREQ_HZ)) u_ocalib (
                .clk(clk), .rst_n(rst_n),
                .calib_run(calib_run_o), .sample_clear(calib_clear),
                .adc_bundled(adc_o),
                .calib_done(calib_done_o), .th_load(th_load_o),
                .th_blocked(th_b), .th_open(th_o),
                .calib_state(), .dbg_max(), .dbg_min()
            );
            genvar s;
            for (s = 0; s < WIDTH; s = s + 1) begin : g_q
                optical_quantize #(.ADC_W(ADC_W)) u_q (
                    .clk(clk), .rst_n(rst_n),
                    .adc_val(adc_o[s*ADC_W +: ADC_W]),
                    .th_blocked(th_b), .th_open(th_o), .th_load(th_load_o),
                    .string_blocked(str_blk[s])
                );
            end
        end
    endgenerate

    assign string_blocked = str_blk;

    // ---------- 竖琴 ----------
    wire       h_valid, h_on;
    wire [6:0] h_num, h_vel;
    optical_harp #(.WIDTH(WIDTH), .CLK_FREQ_HZ(CLK_FREQ_HZ)) u_harp (
        .clk(clk), .rst_n(rst_n),
        .string_blocked(str_blk),
        .event_valid(h_valid), .event_on(h_on),
        .event_num(h_num), .event_vel(h_vel),
        .strum_dir(strum_dir), .strum_valid(strum_valid),
        .pluck_pulse()
    );

    // ---------- ADC 握手：逐通道立即锁存（审阅报告 #5）----------
    //   原来等本轮 8 路全部采完才整块更新，某一路最坏要多等近一轮（2.6ms）；
    //   改成"每采完一路就更新一路"，最坏只等该路自己的下一次转换。
    reg [ADC_W*WIDTH-1:0] adc_p_hold;
    reg                   adc_p_valid_q;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            adc_p_hold    <= {(ADC_W*WIDTH){1'b0}};
            adc_p_valid_q <= 1'b0;
        end else begin
            if (adc_ch_valid && adc_ch_idx < WIDTH)
                adc_p_hold[adc_ch_idx*ADC_W +: ADC_W] <= adc_ch_data;
            if (adc_valid) adc_p_valid_q <= 1'b1;   // 整轮握手（仅用于心跳/标定）
        end
    end

    //==============================================================
    // 上电自动调零（ADS1256 开输入缓冲后通常有几十~几百码的直流偏置）
    //   前 AZ_ROUNDS 轮给每一路求平均当基线，之后 adc_p_az = raw - base。
    //   好处：恒定偏置不会再顶穿 180 码阈值 → 消除"不碰也一直按"的幽灵键。
    //   注意：上电后前 ~170ms 不出声（校准期），这段时间请勿按键。
    //==============================================================
    wire [ADC_W*WIDTH-1:0] adc_p_masked;
    pressure_zero #(.WIDTH(WIDTH),.ADC_W(ADC_W),.CLK_FREQ_HZ(CLK_FREQ_HZ),.KEY_MASK(KEY_MASK)) u_zero (
      .clk(clk),.rst_n(rst_n),.clear(calib_clear),.valid(adc_ch_valid),.idx(adc_ch_idx),.data(adc_ch_data),
      .corrected(adc_p_masked),.ready(pressure_ready),.stale(pressure_stale));

    // ---------- 压力：标定 + 检测 ----------
    wire [ADC_W-1:0] th_dn, th_up;
    wire             th_load_p;
    wire [ADC_W-1:0] raw_max;
    pressure_calib #(.ADC_W(ADC_W), .CLK_FREQ_HZ(CLK_FREQ_HZ)) u_pcalib (
        .clk(clk), .rst_n(rst_n),
        .calib_run(calib_run_p), .sample_clear(calib_clear),
        .adc_probe(adc_p_hold[ADC_W-1:0]),
        .calib_done(calib_done_p), .th_load(th_load_p),
        .th_down(th_dn), .th_up(th_up), .raw_max(raw_max),
        .calib_state()
    );

    wire       p_on_valid, p_off_valid, p_vu_valid;
    wire [6:0] p_num, p_vel, p_off_num, p_at, p_vu_num, p_vu_vel;
    pressure_detect #(.WIDTH(WIDTH), .ADC_W(ADC_W), .CLK_FREQ_HZ(CLK_FREQ_HZ)) u_press (
        .clk(clk), .rst_n(rst_n),
        .adc(adc_p_masked),
        .th_down(th_dn), .th_up(th_up), .th_load(th_load_p),
        .raw_max(raw_max), .calib_dead(th_dn),
        .key_on(key_on),
        .press_valid(p_on_valid), .press_num(p_num), .press_vel(p_vel),
        .velupd_valid(p_vu_valid), .velupd_num(p_vu_num), .velupd_vel(p_vu_vel),
        .rel_valid(p_off_valid), .rel_num(p_off_num),
        .aftertouch(p_at)
    );

    // 力度修正只在钢琴模式用（竖琴的力度是拨弦速度，不需要补）
    assign velupd     = p_vu_valid; // Piano VU is independent of the vibrato switch.
    assign velupd_num = p_vu_num;
    assign velupd_vel = p_vu_vel;

    // ---------- 电容模式 ----------
    cap_touch #(.CLK_FREQ_HZ(CLK_FREQ_HZ)) u_cap (
        .clk(clk), .rst_n(rst_n),
        .touch(touch),
        .mode(mode), .mode_changed(mode_changed), .all_notes_off(all_notes_off)
    );

    // ---------- 双音色常开：两路事件合并（不再有模式门控）----------
    //   钢琴与竖琴同时在线，各 Events 自带 timbre：
    //     钢琴 → timbre=0，竖琴 → timbre=1
    //   同一拍撞车时：钢琴优先，竖琴进 1 深队列，下一拍补发（不会丢）
    //   竖琴不再需要"120ms 自动补 NOTE_OFF"：poly_mgr 会按 timbre=1
    //   在包络自然衰减到 IDLE 时自动回收音槽。
    wire        e_valid, e_on;
    wire [6:0]  e_num, e_vel;

    // 钢琴：press 与 rel 交错，一拍一条；编号跟事件
    wire        p_ev   = p_on_valid | p_off_valid;
    wire        p_on_e = p_on_valid;
    wire [6:0]  p_num_e= p_on_valid ? p_num : p_off_num;

    // 竖琴队列：16 深 FIFO（采纳第 4 轮修复版的做法）
    //   原来是我写的 2 深移位寄存器，连续多拍撞车时仍可能丢；换成现成的
    //   event_fifo 后不会丢，而且能通过 dropped 标志上报。
    wire [13:0] hq_head;
    wire        hq_empty, hq_full, harp_dropped;

    assign harp_overflow = harp_dropped;
    wire        take_h = ~p_ev & ~hq_empty;     // 没和钢琴撞车就从队头取
    wire [6:0]  h_num_now = hq_head[13:7];
    wire [6:0]  h_vel_now = hq_head[6:0];

    event_fifo #(.DEPTH(16), .AW(4), .DW(14)) u_harp_fifo (
        .clk      (clk),
        .rst_n    (rst_n),
        .push     (h_valid),
        .push_data({h_num, h_vel}),
        .pop      (take_h),
        .pop_data (hq_head),
        .full     (hq_full),
        .empty    (hq_empty),
        .dropped  (harp_dropped)
    );

    assign e_valid    = p_ev | take_h;
    assign e_on       = p_ev ? p_on_e : 1'b1;      // 竖琴只发 NOTE_ON
    assign e_num      = p_ev ? p_num_e : h_num_now;
    assign e_vel      = p_ev ? (p_on_valid ? p_vel : 7'd0) : h_vel_now;

    // ★ 每个事件自带音色：竖琴=1，钢琴=0
    assign event_timbre = take_h;

    // 触后（弯音）：必须一直是"当前按键压力"，不能只在事件那一拍有效
    //   （审阅报告 #3：原来用 e_at，没事件时输出 0，连续弯音通路断了）
    assign aftertouch = p_at;

    // ---------- 适配：NOTE_ON / NOTE_OFF（无全局 note_release）----------
    c_to_voice_adapter #(.CLK_FREQ_HZ(CLK_FREQ_HZ)) u_adp (
        .clk(clk), .rst_n(rst_n),
        .event_valid(e_valid), .event_on(e_on),
        .event_num(e_num), .event_vel(e_vel),
        .all_notes_off(1'b0),        // 【2026-10-27 修】TTP 已改作颤音开关，
                                     //   不能再让它触发"全音关断"，否则按一下颤音
                                     //   会把还按着的音全部释放（复审 #5）
        .pluck_style(1'b0),          // 竖琴也不再靠适配器补释放
        .note_on(note_on), .note_num(note_num), .velocity(velocity),
        .note_off(note_off), .note_off_num(note_off_num)
    );

    wire _unused_ok = adc_p_valid_q;

endmodule

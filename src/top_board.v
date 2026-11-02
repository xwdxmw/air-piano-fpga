//====================================================================
// top_board.v —— 板级顶层（合并版）
//
// 事件总线（4-phase握手）：
//   event_req     —— 请求脉冲
//   event_payload —— 完整事件数据（17bit）
//     [16]   timbre  0=钢琴 1=竖琴（NOTE_ON时锁存）
//     [15:14] type   00=NOTE_ON 01=NOTE_OFF 10=ALL_NOTES_OFF 11=预留
//     [13:7]  num    音符编号 0~127
//     [6:0]   vel    力度 0~127
//   event_ack     —— 接收端应答
//
// 板载音频：PT8211-S DAC（三线LSBJ，免配置，无MCLK）
//   BCK=E22, LRCK=F24, DIN=G24
//
// 复位：audio_rst_n = rst_n & pll_locked
//====================================================================

module top_board #(
    parameter USE_ENGINE = 1,
    parameter BEND_GRAY = 0,
    parameter USE_PT8211 = 1,
    parameter STANDARD_I2S = 0, // 0: installed PT8211, 1: external I2S DAC ONLY    // 1=板载PT8211免配置 0=外接codec走I2C
    parameter integer LFO_DIV = 38324  // 颤音 LFO 每步时钟数（38325×60 ≈ 187ms ≈ 5.3Hz）
)(
    input  wire clk_50m,        // 板载 50MHz（P16）
    input  wire rst_n,          // 复位（低有效，S0/K16，3.3V bank）

    // ---- 事件总线（50MHz域 → 12.288MHz域，4-phase握手）----
    input  wire        event_req,
    input  wire [18:0] event_payload,
    output wire        event_ack,

    input  wire mode,           // 0=钢琴 1=竖琴（仅LED显示用）
    input  wire [6:0] bend,     // 全局弯音（实时变调用）

    // ---- I2S → 板载 PT8211-S ----
    output wire bclk,           // BCLK约1.533MHz（E22）
    output wire ws,             // WS约47.907kHz（F24，低=左）
    output wire dacdat,         // 串行数据（G24）
    output wire mclk,           // PT8211无MCLK：不绑引脚

    // ---- I2C → 外接codec（PT8211模式下悬空）----
    inout  wire i2c_sda,
    output wire i2c_scl,
    output wire codec_ready,

    // ---- 调试 ----
    output wire [31:0] active_debug,
    output wire [15:0] pcm_mix_debug,
    output wire        pll_locked_o,   // PLL 锁定（给顶层 LED 指示）

    // ---- 给 LCD 示波器用的音频域信号 ----
    output wire        audio_clk_o,    // 12.264MHz
    output wire        audio_rst_o,    // 音频域复位（rst_n & pll_locked）
    output wire        audio_tick_o,   // 47.9kHz 采样脉冲
    output wire [15:0] pcm_mon_o       // 最终音频输出（含延迟效果）
);

    //--------------------------------------------------------------
    // PLL：50M → 12.288M（带locked）
    //--------------------------------------------------------------
    wire clk_12m288;
    wire pll_locked;
    pll_12m288 u_pll (
        .clk_50m    (clk_50m),
        .clk_12m288 (clk_12m288),
        .locked     (pll_locked)
    );

    // 异步复位源：外部复位 & PLL锁定
    wire audio_rst_n_async = rst_n & pll_locked;
    // 音频域复位同步释放：避免复位释放时亚稳态
    reg [1:0] audio_rst_sync;
    always @(posedge clk_12m288 or negedge audio_rst_n_async) begin
        if(!audio_rst_n_async) audio_rst_sync <= 2'b00;
        else audio_rst_sync <= {audio_rst_sync[0], 1'b1};
    end
    wire audio_rst_n = audio_rst_sync[1];

    // PLL 锁定引出（仅给顶层 LED 指示，不参与任何逻辑）
    assign pll_locked_o = pll_locked;

    //--------------------------------------------------------------
    // PT8211 专用发送器：内部自带分频（BCLK=clk/8，WS=clk/256）
    //--------------------------------------------------------------
    wire sample_tick;
    wire [15:0] pcm_mix;     // 混音结果（在此声明，pt8211 例化前可见）
    wire signed [15:0] pcm_fx;   // 加了延迟效果后的最终输出

    //--------------------------------------------------------------
    // 延迟效果器（拓展2 的"效果器"）：150ms 回声，BSRAM 延迟线
    //   一路 0.5 反馈 → 听感是一串逐渐变轻的回声；干湿各半，不改变原音色
    //--------------------------------------------------------------
    delay_fx #(
        .DEPTH (8192),
        .AW    (13),
        .DLY   (7168)          // 7168 / 47.9kHz ≈ 150ms
    ) u_fx (
        .clk         (clk_12m288),
        .rst_n       (audio_rst_n),
        .sample_tick (sample_tick),
        .din         (pcm_mix),
        .dout        (pcm_fx)
    );

    generate if(STANDARD_I2S)begin: g_standard_i2s
      standard_i2s_tx u_tx(.clk(clk_12m288),.rst_n(audio_rst_n),.left_data(pcm_fx),.right_data(pcm_fx),
        .bclk(bclk),.ws(ws),.dacdat(dacdat),.sample_tick(sample_tick));
    end else begin: g_board_pt8211
    pt8211_tx u_pt_tx (
        .clk         (clk_12m288),
        .rst_n       (audio_rst_n),
        .left_data   (pcm_fx),
        .right_data  (pcm_fx),
        .bclk        (bclk),
        .ws          (ws),
        .dacdat      (dacdat),
        .sample_tick (sample_tick)
    );

    end endgenerate

    //--------------------------------------------------------------
    // 事件总线同步（req + payload 打两拍）
    //--------------------------------------------------------------
    reg req1, req2;
    reg [18:0] pl1, pl2;

    always @(posedge clk_12m288 or negedge audio_rst_n) begin
        if (!audio_rst_n) begin
            req1 <= 1'b0; req2 <= 1'b0;
            pl1 <= 19'd0; pl2 <= 19'd0;
        end else begin
            req1 <= event_req;  req2 <= req1;
            pl1 <= event_payload; pl2 <= pl1;
        end
    end

    //--------------------------------------------------------------
    // 弯音(bend)信号跨域同步
    // Registered Gray code from the 50MHz controller, then 2FF and decode.
    // Default standalone module mode retains the legacy binary input contract.
    reg [6:0] bend1, bend2;
    function[6:0]gray_to_binary;input[6:0]g;integer i;begin
      gray_to_binary[6]=g[6];for(i=5;i>=0;i=i-1)gray_to_binary[i]=gray_to_binary[i+1]^g[i];
    end endfunction
    wire[6:0]bend_audio=BEND_GRAY?gray_to_binary(bend2):bend2;
    always @(posedge clk_12m288 or negedge audio_rst_n) begin
        if (!audio_rst_n) begin
            bend1      <= BEND_GRAY?7'd96:7'd64;
            bend2 <= BEND_GRAY?7'd96:7'd64;
        end else begin
            bend1      <= bend;
            bend2 <= bend1;
        end
    end

    // 从payload解码事件字段
    wire [1:0] ev_source=pl2[18:17];
    wire        ev_timbre  = pl2[16];
    wire [1:0]  ev_type    = pl2[15:14];
    wire [6:0]  ev_num     = pl2[13:7];
    wire [6:0]  ev_vel     = pl2[6:0];
    wire        ev_on      = (ev_type == 2'b00);   // NOTE_ON
    wire        ev_ano     = (ev_type == 2'b10);   // ALL_NOTES_OFF

    //--------------------------------------------------------------
    // 4-phase握手 ack
    //--------------------------------------------------------------
    reg ack_r;
    always @(posedge clk_12m288 or negedge audio_rst_n) begin
        if(!audio_rst_n) ack_r <= 1'b0;
        else if(req2 && !ack_r) ack_r <= 1'b1;
        else if(!req2 && ack_r) ack_r <= 1'b0;
    end
    assign event_ack = ack_r;

    //--------------------------------------------------------------
    // 颤音：5Hz 三角波 LFO，音高调制（加法偏移，不占 DSP）
    //   开关电平 mode 来自 50MHz 域的 TTP223 → 2 拍同步到音频域
    //   偏移单位与弯音一致（相位字），C4 处约 ±0.51%（≈±9 音分）
    //--------------------------------------------------------------
    reg mode_s1, mode_s2;
    always @(posedge clk_12m288 or negedge audio_rst_n) begin
        if (!audio_rst_n) begin
            mode_s1 <= 1'b0;
            mode_s2 <= 1'b0;
        end else begin
            mode_s1 <= mode;
            mode_s2 <= mode_s1;
        end
    end

    reg  [15:0]       lfo_div;
    reg  signed [4:0] lfo_val;
    reg               lfo_dir;
    always @(posedge clk_12m288 or negedge audio_rst_n) begin
        if (!audio_rst_n) begin
            lfo_div <= 16'd0;
            lfo_val <= 5'sd0;
            lfo_dir <= 1'b1;
        end else begin
            lfo_div <= lfo_div + 16'd1;
            if (lfo_div == LFO_DIV[15:0] - 16'd1) begin   // 60 步 × LFO_DIV ≈ 187ms → 5.3Hz
                lfo_div <= 16'd0;
                // ★ 审阅报告 #4：原写法在 ±15 处还会再加一步，5bit 有符号溢出，
                //   变成 -16/+15 之间来回跳（听感是 160Hz 的怪叫）。这里先判方向再自增。
                if (lfo_dir) begin
                    if (lfo_val >= 5'sd15) lfo_dir <= 1'b0;
                    else                   lfo_val <= lfo_val + 5'sd1;
                end else begin
                    if (lfo_val <= -5'sd15) lfo_dir <= 1'b1;
                    else                    lfo_val <= lfo_val - 5'sd1;
                end
            end
        end
    end

    wire signed [4:0]  lfo_use   = mode_s2 ? lfo_val : 5'sd0;
    // ±15 × 16000 = ±240000 相位字：C4 约 ±1.02%（≈±17.6 音分），听感明显的自然颤音
    wire signed [22:0] vib_off_s = lfo_use * 23'sd16_000;

    //--------------------------------------------------------------
    // 动态增益归一：按"当前活跃声部数"选右移位数
    //   1→÷1  2→÷2  3~4→÷4  5~8→÷8  9~16→÷16  17~32→÷32
    //   这样单音响度恒定、16 路同时响也不会削顶（原来固定 ÷4，
    //   8 键同时按就已经超 32767）。
    //   每采样更新目标档位，mixer用Q16平滑增益，避免瞬间6dB跳变。
    //--------------------------------------------------------------
    wire [31:0] act_cnt_src;

    function [5:0] popcnt32;
        input [31:0] v;
        integer i;
        begin
            popcnt32 = 6'd0;
            for (i = 0; i < 32; i = i + 1) popcnt32 = popcnt32 + v[i];
        end
    endfunction

    function [3:0] gain_sh;
        input [5:0] n;
        begin
            if      (n <= 6'd1)  gain_sh = 4'd0;
            else if (n <= 6'd2)  gain_sh = 4'd1;
            else if (n <= 6'd4)  gain_sh = 4'd2;
            else if (n <= 6'd8)  gain_sh = 4'd3;
            else if (n <= 6'd16) gain_sh = 4'd4;
            else                 gain_sh = 4'd5;
        end
    endfunction

    reg [3:0]  gsh_r;
    always @(posedge clk_12m288 or negedge audio_rst_n) begin
        if (!audio_rst_n) begin
            gsh_r   <= 4'd1;
        end else begin
            // Update every sample; mixer interpolates gain instead of 6dB steps.
            if(sample_tick) gsh_r <= gain_sh(popcnt32(act_cnt_src));
        end
    end

    //--------------------------------------------------------------
    // 发声源 + 混音器
    //--------------------------------------------------------------

    generate
        if (USE_ENGINE == 1) begin: g_engine
            wire [32*16-1:0] pcm_out_v;
            wire [31:0]      active;

            top_synth #(.N(32)) u_synth (
                .clk           (clk_12m288),
                .rst_n         (audio_rst_n),
                .sample_tick   (sample_tick),
                .event_valid   (req2),
                .event_type    (ev_type),
                .event_num     (ev_num),
                .event_vel     (ev_vel),
                .event_timbre  (ev_timbre),
                .event_source(ev_source),
                .mode          (mode),
                .bend          (bend_audio),   // 已同步到音频域的弯音
                .vib_off       (vib_off_s),    // 5Hz 三角波颤音偏移
                .pcm_out_v     (pcm_out_v),
                .active_debug  (active)
            );

            assign act_cnt_src = active;

            mixer #(
                .N          (32),.SMOOTH_GAIN(1)
            ) u_mixer (
                .clk         (clk_12m288),
                .rst_n       (audio_rst_n),
                .sample_tick (sample_tick),
                .pcm_in_v    (pcm_out_v),
                .gain_shift  (gsh_r),
                .pcm_mix     (pcm_mix)
            );

            assign active_debug = active;
        end
        else begin: g_minimal
            wire [15:0] pcm_min;

            osc #(
                .DATA_WIDTH (16),
                .TABLE_SIZE (256),
                .PHASE_WIDTH(32)
            ) u_osc (
                .clk         (clk_12m288),
                .rst_n       (audio_rst_n),
                .sample_tick (sample_tick),
                .freq_ctrl   (32'h0258BF26),   // A4 = 440Hz
                .pcm_out     (pcm_min)
            );

            mixer #(
                .N          (1)
            ) u_mixer (
                .clk         (clk_12m288),
                .rst_n       (audio_rst_n),
                .sample_tick (sample_tick),
                .pcm_in_v    (pcm_min),
                .gain_shift  (4'd0),
                .pcm_mix     (pcm_mix)
            );

            assign act_cnt_src = 32'd0;
            assign active_debug = 32'd0;
        end
    endgenerate

    //--------------------------------------------------------------
    // codec 分支：板载 PT8211 免配置 / 外接 codec 走 I2C
    //--------------------------------------------------------------
    generate
        if (USE_PT8211 == 1) begin: g_pt8211
            assign codec_ready = 1'b1;
            assign i2c_scl     = 1'b1;   // 释放I2C
            assign i2c_sda     = 1'bz;
            assign mclk        = 1'b0;   // PT8211无MCLK
        end
        else begin: g_ext_codec
            codec_init u_codec (
                .clk         (clk_12m288),
                .rst_n       (audio_rst_n),
                .i2c_scl     (i2c_scl),
                .i2c_sda     (i2c_sda),
                .codec_ready (codec_ready),
                .ack_err     ()
            );
            assign mclk = clk_12m288;
        end
    endgenerate

    assign pcm_mix_debug = pcm_mix;

    // 给 LCD 示波器：音频时钟 / 复位 / 采样脉冲 / 最终输出
    assign audio_clk_o  = clk_12m288;
    assign audio_rst_o  = audio_rst_n;
    assign audio_tick_o = sample_tick;
    assign pcm_mon_o    = pcm_fx;

endmodule

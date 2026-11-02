//====================================================================
// mixer.v —— 32 路混音器（队员 B · 契约 mixer_interface.md §3）
//
// 规格：
//   sum = Σ pcm[i]（i=0..31，signed 16bit）
//   中间位宽 22bit signed（[21:0]），保证 32×32767 ≈ 2^20 不溢出；
//   输出 16bit signed，必须【饱和截位】，严禁直接取低 16 位
//   （直接截断 = 大信号波形翻转成噪声）。
//
// 参数：
//   N          = 输入路数（32；最小闭环验收时可用 1）
//   GAIN_SHIFT = 输出前右移位数（0~2，默认 1 = ÷2 ≈ -6dB，和弦安全）
//
// 时序：引擎在 sample_tick 沿更新 32 路 PCM，本模块在同一沿锁存
//       pcm_mix；对 I2S 而言每采样周期一个有效值，无需 FIFO。
//====================================================================

module mixer #(
    parameter N          = 32,
    parameter SMOOTH_GAIN = 0,
    parameter GAIN_SHIFT = 1
)(
    input  wire                clk,
    input  wire                rst_n,          // 低有效异步复位
    input  wire                sample_tick,    // 48kHz 采样脉冲（与引擎同源）
    input  wire [N*16-1:0]     pcm_in_v,       // N×16bit 有符号 PCM
    input  wire [3:0]          gain_shift,     // 【动态增益】按活跃声部数给的右移位数
    output reg  [15:0]         pcm_mix         // 16bit 有符号混音输出
);

    // ---- 组合加法：32 项 signed 相加（综合器自动综合成加法树）----
    reg signed [21:0] sum;
    integer i;

    always @(*) begin
        sum = 22'sd0;
        for (i = 0; i < N; i = i + 1)
            sum = sum + $signed(pcm_in_v[i*16 +: 16]);
    end

    // ---- 锁存 + 增益右移 + 饱和截位 ----
    // sum >>> GAIN_SHIFT 为算术右移（signed 自动符号扩展）；
    // 与契约骨架 sum[15+GAIN_SHIFT -: 16] 等价。
    reg signed [21:0] sum_shifted;
    reg[16:0]gain_q16;
    wire[16:0]target_gain=17'd65536 >> gain_shift;
    wire[16:0]gain_gap=(gain_q16>target_gain)?gain_q16-target_gain:target_gain-gain_q16;
    wire[16:0]gain_step=(gain_gap+17'd63)>>6;
    wire signed[39:0]scaled_sum=$signed(sum)*$signed({1'b0,gain_q16});

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pcm_mix <= 16'sd0;
            gain_q16 <= 17'd65536 >> GAIN_SHIFT;
        end
        else if (sample_tick) begin
            if(gain_q16>target_gain)gain_q16<=gain_q16-gain_step;
            else if(gain_q16<target_gain)gain_q16<=gain_q16+gain_step;
            sum_shifted = SMOOTH_GAIN ? (scaled_sum >>> 16) : (sum >>> gain_shift);
            if (sum_shifted >  22'sd32767)
                pcm_mix <= 16'sd32767;        // 正饱和
            else if (sum_shifted < -22'sd32768)
                pcm_mix <= -16'sd32768;       // 负饱和
            else
                pcm_mix <= sum_shifted[15:0]; // 正常范围：取低 16 位
        end
    end

endmodule

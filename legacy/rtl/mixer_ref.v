// ============================================================================
// mixer_ref.v —— 混音器【参考实现 / 占位版】（队员 A 提供，供联合仿真用）
// ============================================================================
// 说明：这是 mixer_interface.md 契约 §3 的完整参考实现，功能与规格一一对应。
//       B 同学交付正式 mixer.v 后，联合仿真时用它替换本文件即可（接口一致）。
// 功能：32 路 16bit 有符号 PCM 相加 → 22bit 中间累加 → 增益右移 → 饱和截位 16bit。
// ============================================================================

module mixer_ref #(
    parameter N          = 32,
    parameter GAIN_SHIFT = 1        // 0 不加增益；1 右移1位（÷2）
)(
    input  wire                clk,
    input  wire                rst_n,
    input  wire                sample_tick,       // 48kHz
    input  wire [N*16-1:0]     pcm_in_v,          // 32×16bit signed
    output reg  [15:0]         pcm_mix            // 16bit signed
);

    reg signed [21:0] sum;
    integer i;

    // 组合加法：32 项相加（综合器自动做成加法树）
    always @(*) begin
        sum = 22'sd0;
        for (i = 0; i < N; i = i + 1)
            sum = sum + $signed(pcm_in_v[i*16 +: 16]);
    end

    // 锁存 + 增益 + 饱和
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pcm_mix <= 16'sd0;
        end
        else if (sample_tick) begin
            if (sum >= (22'sd32767 << GAIN_SHIFT))
                pcm_mix <= 16'sd32767;
            else if (sum <= (-22'sd32768 << GAIN_SHIFT))
                pcm_mix <= -16'sd32768;
            else
                pcm_mix <= sum[15 + GAIN_SHIFT -: 16];
        end
    end

endmodule

// ============================================================================
// osc_synth.v（综合版，正弦表改 case ROM） —— 单音正弦振荡器（相位累加器 + 波表查表）
// 队员 A · 合成引擎第一步 · 零基础友好注释版
// 【可集成】本模块是"发声单元"，会被 voice.v（振荡器+ADSR）和顶层实例化复用；
//           同一个正弦表 sine.mem 被所有振荡器实例共享，只存一份。
// ============================================================================
// 【原理，一句话】
//   每个采样时刻（sample_tick 来一个脉冲），相位累加器加上"频率控制字"；
//   累加器的值就是相位，取它的高 8 位作为地址去查正弦表，得到当前采样值。
//   相位从 0 转到 2^32（溢出回绕）正好是正弦波的一个周期。
//
// 【频率怎么定】
//   频率控制字 freq_ctrl = 目标频率(Hz) × 2^32 ÷ 采样率(Hz)
//   例：440Hz @ 48kHz → freq_ctrl = 440 × 2^32 ÷ 48000 ≈ 39_370_534 = 0x0258BF26
//   常用音符的控制字见 README_osc.md 的对照表（或查 note_freq.mem 全音域表）。
// ============================================================================

module osc #(
    parameter DATA_WIDTH  = 16,     // 输出采样值位宽（16bit 有符号 PCM，标准音频格式）
    parameter TABLE_SIZE  = 256,    // 正弦表长度（sine.mem 共 256 个点）
    parameter PHASE_WIDTH = 32,     // 相位累加器位宽（32bit，频率分辨率足够细）
    parameter SAMPLE_RATE = 48000   // 采样率（仅作记录与换算参考，不影响逻辑）
)(
    input  wire                   clk,         // 系统时钟（板卡主时钟，如 27MHz）
    input  wire                   rst_n,       // 复位，低有效（0 = 复位）
    input  wire                   sample_tick, // 采样脉冲：每 1/48000 秒来一个（高电平 1 拍）
    input  wire [PHASE_WIDTH-1:0] freq_ctrl,   // 频率控制字（32bit，决定音高）
    output reg  [DATA_WIDTH-1:0]  pcm_out      // 输出：当前采样点的正弦值（有符号）
);

    // ---- 正弦波表：256 × 16bit 有符号整数（综合版：case ROM 替代 $readmemh）----
    wire [DATA_WIDTH-1:0] sine_val;
    sine_rom #(.D_WIDTH(DATA_WIDTH), .A_WIDTH(8)) u_sine_rom (
        .addr (next_phase[PHASE_WIDTH-1 -: 8]),
        .dout (sine_val)
    );

    // ---- 相位累加器 ----
    reg  [PHASE_WIDTH-1:0] phase;              // 当前相位（32bit 循环计数器）
    wire [PHASE_WIDTH-1:0] next_phase = phase + freq_ctrl;  // 下一个相位（组合电路）

    // ---- 每个采样时刻：相位前进 + 输出该相位对应的正弦值 ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin                       // 复位：相位清零，输出静默
            phase   <= 32'd0;
            pcm_out <= 16'd0;
        end else if (sample_tick) begin
            phase   <= next_phase;              // 相位前进一格
            // 用"更新后"的相位查表：取高 8 位做 256 点地址
            pcm_out <= sine_val;
        end
        // sample_tick 为 0 的拍：什么都不做，振荡器保持上一个输出
    end

endmodule

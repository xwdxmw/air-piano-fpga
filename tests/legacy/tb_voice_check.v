// ============================================================================
// tb_voice_check.v —— 用真实采样节奏验证 voice 音槽：
//   ① 输出频率是不是 261.6Hz（C4）
//   ② 钢琴 vs 竖琴的包络差异到底多大（量化音色区别）
// 用法：iverilog -g2012 -o vcheck.vvp voice_synth.v note_freq_rom.v osc_synth.v sine_rom.v tb_voice_check.v
//       vvp vcheck.vvp
// 输出：voice_pcm.txt（每采样一拍 pcm + ad_state）
// ============================================================================
`timescale 1ns/1ps
module tb_voice_check;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg [7:0] ph = 8'd0;
    reg sample_tick = 1'b0;

    // ---- 注入信号 ----
    reg note_on = 1'b0;
    reg [6:0] note_num = 7'd0;
    reg [6:0] velocity = 7'd0;
    reg note_release = 1'b0;
    reg timbre_sel = 1'b0;
    wire [15:0] pcm_out;
    wire [2:0] ad_state;

    // 10ns 时钟（加速仿真；逻辑按"多少个clk"工作，等价 12.288M）
    always #5 clk = ~clk;

    // sample_tick：每 256 clk 一拍（等价 48kHz）
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ph <= 8'd0;
            sample_tick <= 1'b0;
        end else begin
            ph <= ph + 8'd1;
            sample_tick <= (ph == 8'hFF);
        end
    end

    // ---- 被测：单音槽 ----
    voice #(
        .SAMPLE_RATE(48000), .TABLE_SIZE(256), .PCM_WIDTH(16), .PHASE_WIDTH(32)
    ) u_voice (
        .flute_sel(1'b0),
        .clk(clk), .rst_n(rst_n), .sample_tick(sample_tick),
        .note_on(note_on), .note_num(note_num), .velocity(velocity),
        .note_release(note_release), .timbre_sel(timbre_sel),
        .freq_update(1'b0), .new_freq(32'd0), .bend(7'd64),
        .pcm_out(pcm_out), .ad_state(ad_state)
    );

    // ---- 采样拍：记录 PCM + ADSR 状态 ----
    integer fid;
    initial fid = $fopen("voice_pcm.txt", "w");
    always @(posedge clk) begin
        if (sample_tick)
            $fwrite(fid, "%0d %0d\n", pcm_out, ad_state);
    end

    // ---- 事件序列（按采样拍计数：48000 采样 = 1s 真实）----
    integer samp;
    always @(posedge clk) begin
        if (sample_tick) samp <= samp + 1;
    end

    always @(posedge clk) begin
        if (sample_tick) begin
            case (samp)
                10: begin
                    // 音1：钢琴 C4，力度100
                    note_on <= 1'b1;
                    note_num <= 7'd60;
                    velocity <= 7'd100;
                    timbre_sel <= 1'b0;
                end
                11: note_on <= 1'b0;
                48000+10: begin
                    // 钢琴音结束（发 release）
                    note_release <= 1'b1;
                end
                48000+48000+10: begin
                    // 音2：竖琴 C4（同音符，timbre=1）
                    note_release <= 1'b0;
                    note_on <= 1'b1;
                    note_num <= 7'd60;
                    velocity <= 7'd100;
                    timbre_sel <= 1'b1;
                end
                48000+48000+11: note_on <= 1'b0;
                48000+48000+48000+10: note_release <= 1'b1;
                48000*3+24000: begin
                    $display("=== DONE ===");
                    $fclose(fid);
                    $finish;
                end
            endcase
        end
    end

    initial begin
        samp = 0;
        rst_n = 1'b0;
        #100 rst_n = 1'b1;
    end

endmodule

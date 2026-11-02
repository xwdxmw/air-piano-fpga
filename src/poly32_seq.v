// AP02: slow visible 32-voice build-up, long FFT hold, quiet release gap.
// ============================================================================
// poly32_seq.v —— 32 复音“现场验收”测试序列器（拓展1证据）
//
// 【为什么需要它】
//   赛题要求“支持测试模式下输出多路不同频率音频，频谱可观测对应数量独立谱峰”。
//   常规 demo 最多 3 音、物理只有 8 键，无法证明 32 复音。本模块在一次测试里
//   让 32 个音槽同时发声，每个音一个独立频率，频谱上能数到 32 个独立谱峰。
//
// 【32 个音】
//   MIDI 36~67（C2=65.4Hz 到 G4=392Hz，共 32 个连续 MIDI 号），
//   32 个不同的基频 → 32 个独立频谱 bin（基频互不重合）。
//
// 【循环时序（方便评委反复抓频谱）】
//   上电等待 100ms（系统稳定）
//   → 触发：每 200ms 发一个 NOTE_ON，32 个加载阶段共 6.4s（事件队列逐拍消费，不溢出）
//   → 保持 10000ms（32 音同时持续，这段时间抓频谱，可数到 32 个峰）
//   → 发 1 个 ALL_NOTES_OFF（32 音全体释放）
//   → 空 3000ms，然后回到“触发”循环
//
// 【力度】
//   固定40：继承AP01动态平滑增益，满32声部时目标增益为÷32；
//   使典型瞬时混音不削顶，32 个峰清晰可辨。
//
// 【接口】
//   与 demo_seq 完全一致，top_system 用 USE_POLY32=1 时替换事件源；
//   事件队列/握手/引擎一行不改。所有事件均为 1 拍脉冲。
// ============================================================================
module poly32_seq #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter [6:0] NOTE_BASE = 7'd36,   // 32 音起始 MIDI 号（C2）
    // 各阶段时长（时钟数）。默认=真实值（供现场抓频谱）；仿真 tb 可传入小值
    // 快速跑完整个循环（逻辑不变，仅时间基准缩放）。
    parameter [31:0] WAIT_CLKS = 100  * (CLK_FREQ_HZ/1000),  // 上电等待 100ms
    parameter [31:0] SLOT_CLKS = 200  * (CLK_FREQ_HZ/1000),  // 每个 NOTE_ON 间隔 200ms
    parameter [31:0] HOLD_CLKS = 10000* (CLK_FREQ_HZ/1000),  // 32 音保持 10s
    parameter [31:0] GAP_CLKS  = 3000 * (CLK_FREQ_HZ/1000)   // 释放后空 3s
)(
    input  wire        clk,
    input  wire        rst_n,

    // ---- 事件输出（1 拍脉冲）----
    output reg         note_on,
    output reg  [6:0]  note_num,
    output reg  [6:0]  velocity,
    output reg         note_off,
    output reg  [6:0]  note_off_num,
    output reg         all_notes_off,
    output wire        mode
);

    // 阶段
    localparam [2:0] P_WAIT    = 3'd0,
                     P_TRIGGER = 3'd1,
                     P_HOLD    = 3'd2,
                     P_ANO     = 3'd3,
                     P_GAP     = 3'd4;

    reg [2:0]  phase;
    reg [31:0] tmr;          // 阶段/槽内计时器
    reg [5:0]  trig_i;       // 触发到第几个音 0..31

    assign mode = 1'b0;      // source2持续诊断音，不随普通钟琴自动衰减

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase        <= P_WAIT;
            tmr          <= 32'd0;
            trig_i       <= 6'd0;
            note_on      <= 1'b0;
            note_num     <= 7'd0;
            velocity     <= 7'd40;
            note_off     <= 1'b0;
            note_off_num <= 7'd0;
            all_notes_off<= 1'b0;
        end else begin
            // 默认：脉冲清零
            note_on       <= 1'b0;
            note_off      <= 1'b0;
            all_notes_off <= 1'b0;

            case (phase)
                // ---------- 上电等待 ----------
                P_WAIT: begin
                    if (tmr >= WAIT_CLKS-1) begin tmr <= 0; trig_i <= 0; phase <= P_TRIGGER; end
                    else tmr <= tmr + 32'd1;
                end

                // ---------- 逐音触发：每个 200ms 槽起始发 1 个 NOTE_ON ----------
                P_TRIGGER: begin
                    if (tmr == 32'd0) begin
                        note_on  <= 1'b1;                       // 仅 1 拍
                        note_num <= NOTE_BASE + trig_i;          // 36..67
                    end
                    if (tmr >= SLOT_CLKS-1) begin
                        tmr <= 0;
                        if (trig_i == 6'd31) begin
                            trig_i <= 0; phase <= P_HOLD;        // 32 音发完 → 保持
                        end else begin
                            trig_i <= trig_i + 6'd1;
                        end
                    end else tmr <= tmr + 32'd1;
                end

                // ---------- 32 音保持 ----------
                P_HOLD: begin
                    if (tmr >= HOLD_CLKS-1) begin
                        tmr <= 0; phase <= P_ANO;
                    end else tmr <= tmr + 32'd1;
                end

                // ---------- 发 1 个 ALL_NOTES_OFF ----------
                P_ANO: begin
                    all_notes_off <= 1'b1;   // 1 拍
                    phase <= P_GAP;
                    tmr   <= 0;
                end

                // ---------- 空窗后循环 ----------
                P_GAP: begin
                    if (tmr >= GAP_CLKS-1) begin tmr <= 0; phase <= P_TRIGGER; end
                    else tmr <= tmr + 32'd1;
                end

                default: begin phase <= P_WAIT; tmr <= 0; end
            endcase
        end
    end

endmodule

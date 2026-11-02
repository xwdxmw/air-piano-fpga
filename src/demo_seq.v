// ============================================================================
// demo_seq.v —— 演示序列器（Demo Sequencer）
// 作者：豆包 · 队员 A/B/C 联合调试用
//
// 【这个模块是干什么的】
//   在没有传感器的情况下，用内部自动生成的事件序列驱动合成引擎，
//   验证三件事：
//     ① 音符 → 频率 → 发声（单音琶音）
//     ② 多音符同时发声（三音和弦 = 多音槽/复音）
//     ③ 钢琴 ↔ 竖琴 音色切换（两段旋律音色不同）
//
// 【放在哪】
//   top_system.v 内，USE_DEMO=1 时替代 c_interact_top（传感器交互）作为事件源。
//   它产生的信号接口与 c_interact_top 完全一致（note_on / note_num / ... ），
//   因此事件队列、握手、合成引擎的代码一行都不用改。
//
// 【时钟域】
//   50MHz（与 c_interact_top 同域，事件总线本来就在 50MHz 域）。
//
// 【演示内容（无限循环）】
//   段落0（钢琴 timbre=0）：
//     C4 → E4 → G4 → (C4+E4+G4 三音和弦) → C5 → G4 → E4 → C4
//   段落1（竖琴 timbre=1）：
//     同样的 8 步（竖琴 ADSR 音头更长、尾音很长，听感明显不同）
//   两段循环播放 → 每次循环你都能对比两种音色
//
// 【节奏】
//   每步 400ms；单音在第 240ms 松开（NOTE_OFF）；和弦在第 240ms 全体释放（ANO）
//   力度固定 100（0~127 中等偏强）
//
// 【重要时序约定】
//   所有事件输出都是"1 拍脉冲"（20ns 高电平），因为 top_system 的事件队列
//   在 50MHz 每个时钟沿都会采样 push 信号，若电平保持多拍会重复入队。
// ============================================================================

module demo_seq #(
    parameter CLK_FREQ_HZ = 50_000_000,   // 输入时钟频率（Hz）
    parameter STEP_MS     = 400           // 每个音符/步骤的时长（ms）
)(
    input  wire        clk,               // 50MHz 系统时钟
    input  wire        rst_n,             // 复位（低有效）

    // ---- 事件输出（脉冲式：高电平只保持 1 拍）----
    output reg         note_on,           // NOTE_ON 脉冲
    output reg  [6:0]  note_num,          // 音符编号 0~127（MIDI：60=C4, 69=A4, 72=C5）
    output reg  [6:0]  velocity,          // 力度 0~127（本 demo 固定 100）
    output reg         note_off,          // NOTE_OFF 脉冲（单音松开）
    output reg  [6:0]  note_off_num,      // 松开哪个音符
    output reg         all_notes_off,     // ANO 脉冲（和弦全体释放）
    output wire        mode               // 当前段落音色：0=钢琴 1=竖琴（wire 别名）
);

    // ==================== 1. 20ms 节拍 ====================
    // 50MHz ÷ 1000 = 50_000 计数 = 1ms；乘 20 = 1_000_000 计数 = 20ms
    localparam TICK_MS    = 20;                        // 基本节拍 20ms
    localparam CNT_MAX    = CLK_FREQ_HZ / 1000 * TICK_MS; // 1_000_000
    localparam TICKS_STEP = STEP_MS / TICK_MS;         // 每步 20 个 tick

    reg [23:0] cnt;          // 20ms 计数器
    reg        tick;         // 20ms 节拍脉冲（高 1 拍）

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt  <= 24'd0;
            tick <= 1'b0;
        end else begin
            tick <= 1'b0;                              // 默认清零（脉冲）
            if (cnt >= CNT_MAX - 1) begin
                cnt  <= 24'd0;
                tick <= 1'b1;                          // 到 20ms：发一个节拍脉冲
            end else begin
                cnt <= cnt + 24'd1;
            end
        end
    end

    // ==================== 2. 段落 & 步进 ====================
    // phase ：段落号（0=钢琴，1=竖琴），2 段循环
    // step  ：段内步号（0~7）
    // tick_in_step：步内第几个 tick（0~19）
    reg [1:0]  phase;
    reg [3:0]  step;
    reg [4:0]  tick_in_step;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase        <= 2'd0;
            step         <= 4'd0;
            tick_in_step <= 5'd0;
        end else if (tick) begin
            if (tick_in_step >= TICKS_STEP - 1) begin  // 步末尾：进入下一步
                tick_in_step <= 5'd0;
                if (step >= 4'd7) begin                // 段末尾：进入下一段
                    step  <= 4'd0;
                    phase <= phase + 2'd1;             // 0→1→0→1…（音色切换）
                end else begin
                    step <= step + 4'd1;
                end
            end else begin
                tick_in_step <= tick_in_step + 5'd1;
            end
        end
    end

    assign mode = phase[0];   // 段落最低位即音色：0=钢琴 1=竖琴

    // ==================== 3. 音符表（每步的音符） ====================
    // note_a：主音；note_b / note_c：和弦的第二、三音（0=无，仅和弦步非 0）
    reg [6:0] note_a, note_b, note_c;
    always @* begin
        case (step)
            4'd0: begin note_a = 7'd60; note_b = 7'd0;  note_c = 7'd0;  end // C4  261.6Hz
            4'd1: begin note_a = 7'd64; note_b = 7'd0;  note_c = 7'd0;  end // E4  329.6Hz
            4'd2: begin note_a = 7'd67; note_b = 7'd0;  note_c = 7'd0;  end // G4  392.0Hz
            4'd3: begin note_a = 7'd60; note_b = 7'd64; note_c = 7'd67; end // C 大三和弦(60/64/67)
            4'd4: begin note_a = 7'd72; note_b = 7'd0;  note_c = 7'd0;  end // C5  523.3Hz
            4'd5: begin note_a = 7'd67; note_b = 7'd0;  note_c = 7'd0;  end // G4
            4'd6: begin note_a = 7'd64; note_b = 7'd0;  note_c = 7'd0;  end // E4
            4'd7: begin note_a = 7'd60; note_b = 7'd0;  note_c = 7'd0;  end // C4
            default: begin note_a = 7'd0; note_b = 7'd0; note_c = 7'd0; end
        endcase
    end

    wire is_chord = (note_b != 7'd0);   // 本步是否三音和弦（仅 step 3）

    // ==================== 4. 事件产生 ====================
    // 步内时刻表（以 tick 计数）：
    //   tick 0  ：NOTE_ON(主音 note_a)
    //   tick 2  ：若有第二音 → NOTE_ON(note_b)（和弦）
    //   tick 4  ：若有第三音 → NOTE_ON(note_c)（和弦）
    //   tick 12 ：单音 → NOTE_OFF(note_a)；和弦 → ANO（全体释放）
    // 注意：note_on / note_off / all_notes_off 默认清零，仅在产生的那 1 拍
    //       置 1，保证事件队列只入队一次。
    localparam REL_TICK = 12;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            note_on       <= 1'b0;
            note_num      <= 7'd0;
            velocity      <= 7'd100;      // 力度固定中等偏强
            note_off      <= 1'b0;
            note_off_num  <= 7'd0;
            all_notes_off <= 1'b0;
        end else begin
            // ---- 默认：事件脉冲清零（保证 1 拍脉冲）----
            note_on       <= 1'b0;
            note_off      <= 1'b0;
            all_notes_off <= 1'b0;

            if (tick) begin
                case (tick_in_step)
                    5'd0: begin                      // 步开始：发主音
                        note_on  <= 1'b1;
                        note_num <= note_a;
                    end
                    5'd2: begin                      // 和弦第二音（若有）
                        if (note_b != 7'd0) begin
                            note_on  <= 1'b1;
                            note_num <= note_b;
                        end
                    end
                    5'd4: begin                      // 和弦第三音（若有）
                        if (note_c != 7'd0) begin
                            note_on  <= 1'b1;
                            note_num <= note_c;
                        end
                    end
                    5'd12: begin                     // 松开：单音 OFF / 和弦 ANO
                        if (is_chord)
                            all_notes_off <= 1'b1;   // 和弦全体释放
                        else begin
                            note_off      <= 1'b1;
                            note_off_num  <= note_a;
                        end
                    end
                    default: ;
                endcase
            end
        end
    end

endmodule

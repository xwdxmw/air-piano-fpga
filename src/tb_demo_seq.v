// ============================================================================
// tb_demo_seq.v —— demo_seq 仿真验证
// 用法：iverilog -g2012 -o demo_sim.vvp demo_seq.v tb_demo_seq.v && vvp demo_sim.vvp
//
// 【加速仿真技巧】
//   把 CLK_FREQ_HZ 从 50M 改成 1000，使 CNT_MAX = 20（本来 1_000_000），
//   每个 tick 从 20ms 缩短到 200ns（@10ns 时钟），整个两段循环 64us 内跑完。
//   逻辑不变，只是时间基准缩放，事件顺序/间距/脉冲宽度全部真实可查。
//
// 【验证点】
//   1. NOTE_ON 脉冲宽度 = 1 拍（10ns），不会重复入队
//   2. 单音步：tick0 发 NOTE_ON，tick12 发 NOTE_OFF（同一音符）
//   3. 和弦步（第 4 步）：NOTE_ON 60 → 64 → 67（间隔 2 tick），tick12 发 ANO
//   4. 段落切换：16 步后 mode 0→1（钢琴→竖琴），音符序列重复
//   5. 力度恒为 100
// ============================================================================
`timescale 1ns/1ps
module tb_demo_seq;

    reg clk = 1'b0;
    reg rst_n = 1'b0;

    wire        note_on, note_off, ano;
    wire [6:0]  note_num, note_off_num, velocity;
    wire        mode;

    // 被测模块（加速参数：CNT_MAX=20，tick=200ns，步=4us）
    demo_seq #(
        .CLK_FREQ_HZ(1000),   // 加速 50000 倍
        .STEP_MS    (400)
    ) u_dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .note_on      (note_on),
        .note_num     (note_num),
        .velocity     (velocity),
        .note_off     (note_off),
        .note_off_num (note_off_num),
        .all_notes_off(ano),
        .mode         (mode)
    );

    // 10ns 时钟
    always #5 clk = ~clk;

    // ---- 事件日志（在事件有效的那一拍打印）----
    always @(posedge clk) begin
        if (note_on)  $display("[%0t] NOTE_ON  num=%0d vel=%0d mode=%0b", $time, note_num, velocity, mode);
        if (note_off) $display("[%0t] NOTE_OFF num=%0d mode=%0b",       $time, note_off_num, mode);
        if (ano)      $display("[%0t] ANO      mode=%0b",               $time, mode);
    end

    // ---- 脉冲宽度检查：note_on 连续 2 拍为高即失败 ----
    reg note_on_q;
    always @(posedge clk) note_on_q <= note_on;
    always @(posedge clk) begin
        if (note_on && note_on_q) begin
            $display("ERROR[%0t] note_on 脉冲超过 1 拍（重复入队风险）", $time);
            $finish;
        end
    end

    integer idx;
    initial begin
        rst_n = 1'b0;
        #100 rst_n = 1'b1;         // 复位释放
        #70000;                    // 跑完两段（64us）+ 余量
        $display("=== SIM DONE ===");
        $finish;
    end

endmodule

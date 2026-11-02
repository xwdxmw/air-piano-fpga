`timescale 1ns / 1ps
//====================================================================
// tb_poly_mgr.v  —— 验证竖琴音槽自动回收（整机修复任务10）
//   通过例化完整合成引擎 top_synth（poly_mgr + voice_array），最贴近真机。
//   场景 A：竖琴 note_on（timbre=1）后【不发 NOTE_OFF】，包络自然衰减到
//           IDLE 后，音槽应自动回收（active 由 1 回 0）。
//   场景 B：钢琴 note_on（timbre=0）后不发 NOTE_OFF，应停在 SUSTAIN，
//           音槽保持占用（active 仍为 1），证明自动回收只对竖琴生效。
//   说明：为缩短仿真，sample_tick 用 64 分频（逻辑与采样率无关）。
//====================================================================
module tb_poly_mgr;
    localparam DIV = 64;
    localparam N = 32;
    reg clk = 1'b0; always #40 clk = ~clk;   // 12.5MHz
    reg rst_n = 1'b0;

    // ---- top_synth 事件总线 ----
    reg        event_valid = 1'b0;
    reg [1:0]  event_type = 2'b00;
    reg [6:0]  event_num = 7'd60;
    reg [6:0]  event_vel = 7'd100;
    reg        event_timbre = 1'b1;
    reg        mode = 1'b0;
    reg [6:0]  bend = 7'd64;

    wire [N*16-1:0] pcm_out_v;
    wire [N-1:0]    active_debug;

    // sample_tick：DIV 分频，div 数到 DIV-1 后回 0（tick 高 1 拍）
    reg [7:0] div = 8'd0;
    wire sample_tick = (div == DIV-1);
    always @(posedge clk) div <= (div == DIV-1) ? 8'd0 : div + 1'b1;

    top_synth #(.N(N)) u_engine (
        .clk(clk), .rst_n(rst_n), .sample_tick(sample_tick),
        .event_valid(event_valid), .event_type(event_type),
        .event_num(event_num), .event_vel(event_vel),
        .event_timbre(event_timbre), .mode(mode), .bend(bend),
        .pcm_out_v(pcm_out_v), .active_debug(active_debug)
    );

    integer active_n;
    always @(*) active_n = $countones(active_debug);

    integer peak_active = 0;
    always @(posedge clk) if (active_n > peak_active) peak_active = active_n;

    integer fail = 0;
    integer n;

    // 调试监控：每 100000 拍打印 active 数与槽0 的 ADSR 状态
    integer snap = 0;
    always @(posedge clk) begin
        if (rst_n && (snap % 100000 == 0))
            $display("    t=%0d active=%0d slot0_state=%0d",
                     snap, active_n, u_engine.ad_state_v[2:0]);
        snap = snap + 1;
    end

    task send_event;
        input [1:0] etype;
        input [6:0] num;
        input [6:0] vel;
        input       timb;
        begin
            @(negedge clk);
            event_type   = etype;
            event_num    = num;
            event_vel    = vel;
            event_timbre = timb;
            event_valid  = 1'b1;
            @(negedge clk);
            event_valid  = 1'b0;
        end
    endtask

    initial begin
        $dumpfile("tb_poly_mgr.vcd");
        $dumpvars(0, tb_poly_mgr);

        repeat (8) @(posedge clk);
        rst_n = 1'b1;
        repeat (10) @(posedge clk);

        // ============================================================
        // 场景 A：竖琴，不发 note_off，等待自然衰减回收
        // ============================================================
        $display("[A] 竖琴 note_on（不发 note_off），预期自然衰减后自动回收");
        send_event(2'b00, 7'd60, 7'd100, 1'b1);

        for (n = 0; n < 1_350_000; n = n + 1) @(posedge clk);

        if (peak_active < 1) begin
            $display("[A] FAIL: 音符似乎从未起音（peak_active=%0d）", peak_active);
            fail = fail + 1;
        end else if (active_n !== 0) begin
            $display("[A] FAIL: 竖琴音未自动回收（active=%0d，peak=%0d）",
                     active_n, peak_active);
            fail = fail + 1;
        end else
            $display("[A] OK: 竖琴曾起音(peak=%0d)，自然衰减后已自动回收", peak_active);

        // ============================================================
        // 场景 B：钢琴，不发 note_off，应保持占用
        // ============================================================
        $display("[B] 钢琴 note_on（不发 note_off），预期停在 SUSTAIN 保持占用");
        peak_active = 0;
        send_event(2'b00, 7'd60, 7'd100, 1'b0);

        for (n = 0; n < 1_350_000; n = n + 1) @(posedge clk);

        if (active_n !== 1) begin
            $display("[B] FAIL: 钢琴音槽占用数=%0d（期望 1，不该自动回收）", active_n);
            fail = fail + 1;
        end else
            $display("[B] OK: 钢琴停在 SUSTAIN，音槽保持占用（active=1）");

        if (fail == 0) $display("==== TEST PASSED ====");
        else           $display("==== TEST FAILED, fail=%0d ====", fail);
        $finish;
    end
endmodule

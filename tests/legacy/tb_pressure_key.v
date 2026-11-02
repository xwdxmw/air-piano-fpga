`timescale 1ns / 1ps
//====================================================================
// tb_pressure_key.v  —— 钢琴力度时序（对齐 fixed 实测参数）
//   阈值 180 / 回差 70 / 2.7ms 峰值窗口 / force_map 后 settle 8 拍 / 最小力度 24
//
//   场景 A：重按 3500 → 2.7ms 窗口+settle 后 press_confirm，力度≈127（削顶），非 0
//   场景 C：轻按 300  → press_confirm，力度≈28（≥最小 24），轻按也可闻
//   场景 B：1ms 内快速松开（< 2.7ms 窗口）→ 不发 press_confirm
//
//   CLK_FREQ=50MHz，ATK_CYC = 50*2700 = 135000 拍 = 2.7ms。
//   force_map（dead=80, raw_max=3000）：
//     重按 raw=3500 → num=3420/span=2920 → 削顶 idx=15 → vel=127
//     轻按 raw=300  → num=220, prod=56100，thr1=46720<thr2=93440 → idx=1 → vel=28
//====================================================================
module tb_pressure_key;
    localparam integer CLK_FREQ = 50_000_000;
    localparam integer ATK_CYC  = (CLK_FREQ/1_000_000)*2700;   // 135000 = 2.7ms

    reg clk = 1'b0; always #10 clk = ~clk;   // 50MHz，周期 20ns
    reg rst_n = 1'b0;
    reg  [11:0] adc = 12'd0;
    reg  [11:0] th_down = 12'd80, th_up = 12'd180;
    reg         th_load = 1'b0;              // 0=用模块默认 THRESHOLD=180
    reg  [11:0] raw_max = 12'd3000, calib_dead = 12'd80;

    wire        key_on, rel_pulse, press_confirm;
    wire [6:0]  velocity, aftertouch;

    integer fail = 0;
    integer t;

    pressure_key #(
        .ADC_W(12), .CLK_FREQ_HZ(CLK_FREQ)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .adc_val(adc), .th_down(th_down), .th_up(th_up), .th_load(th_load),
        .raw_max(raw_max), .calib_dead(calib_dead),
        .key_on(key_on), .rel_pulse(rel_pulse), .press_confirm(press_confirm),
        .velocity(velocity), .aftertouch(aftertouch)
    );

    reg confirm_seen = 1'b0;
    always @(posedge clk) if (press_confirm) confirm_seen <= 1'b1;

    // 等到 press_confirm 或超时；结束后用全局 t 判定（settle 8 拍 → 约 ATK_CYC+8）
    task wait_confirm;
        begin
            t = 0;
            fork : WAIT_W
                begin : CPATH
                    while (!press_confirm) begin
                        @(posedge clk);
                        t = t + 1;
                    end
                    disable TPATH;
                end
                begin : TPATH
                    repeat (ATK_CYC + 30) @(posedge clk);
                    disable CPATH;
                end
            join
        end
    endtask

    initial begin
        $dumpfile("tb_pressure_key.vcd");
        $dumpvars(0, tb_pressure_key);

        // ---------------- 复位 ----------------
        repeat (8) @(posedge clk);
        rst_n = 1'b1;
        repeat (10) @(posedge clk);

        // ============================================================
        // 场景 A：重按 3500
        // ============================================================
        $display("[A] 重按 3500，预期约 %0d 拍后 confirm、velocity≈127", ATK_CYC);
        @(negedge clk);
        adc = 12'd3500;
        wait_confirm;
        if (t < ATK_CYC - 2 || t > ATK_CYC + 15) begin
            $display("[A] FAIL: confirm 时机 t=%0d（期望约 %0d）", t, ATK_CYC);
            fail = fail + 1;
        end else
            $display("[A] OK: confirm 在 %0d 拍后出现", t);
        if (velocity < 7'd100) begin
            $display("[A] FAIL: confirm 时 velocity=%0d（期望约127）", velocity);
            fail = fail + 1;
        end else
            $display("[A] OK: confirm 时 velocity=%0d", velocity);
        @(posedge clk);
        if (press_confirm !== 1'b0) begin
            $display("[A] FAIL: press_confirm 未在 1 拍后拉低");
            fail = fail + 1;
        end

        // 松开清场
        @(negedge clk); adc = 12'd0;
        repeat (300) @(posedge clk);

        // ============================================================
        // 场景 C：轻按 300（验证最小力度 24，轻按不静音）
        // ============================================================
        $display("[C] 轻按 300，预期 confirm、velocity≥24");
        confirm_seen = 1'b0;
        @(negedge clk);
        adc = 12'd300;
        wait_confirm;
        if (t < ATK_CYC - 2 || t > ATK_CYC + 15) begin
            $display("[C] FAIL: confirm 时机 t=%0d（期望约 %0d）", t, ATK_CYC);
            fail = fail + 1;
        end else
            $display("[C] OK: confirm 在 %0d 拍后出现", t);
        if (velocity < 7'd24) begin
            $display("[C] FAIL: 轻按 velocity=%0d（应≥24）", velocity);
            fail = fail + 1;
        end else
            $display("[C] OK: 轻按 velocity=%0d", velocity);

        // 松开清场
        @(negedge clk); adc = 12'd0;
        repeat (300) @(posedge clk);

        // ============================================================
        // 场景 B：1ms 内快速松开（< 2.7ms 窗口），不发 confirm
        // ============================================================
        $display("[B] 1ms 内快速松开（<2.7ms 窗口），预期不发 press_confirm");
        confirm_seen = 1'b0;
        @(negedge clk);
        adc = 12'd3500;
        repeat (50000) @(posedge clk);          // 保持 1ms（小于 2.7ms 窗口）
        @(negedge clk); adc = 12'd0;           // 松开
        repeat (ATK_CYC + 100) @(posedge clk);
        if (confirm_seen) begin
            $display("[B] FAIL: 快速松开后出现了 press_confirm");
            fail = fail + 1;
        end else
            $display("[B] OK: 快速松开未触发 confirm");

        // ============================================================
        if (fail == 0) $display("==== TEST PASSED ====");
        else           $display("==== TEST FAILED, fail=%0d ====", fail);
        $finish;
    end
endmodule

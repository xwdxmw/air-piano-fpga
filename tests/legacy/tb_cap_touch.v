`timescale 1ns / 1ps
//====================================================================
// tb_cap_touch —— 验证 TTP223（cap_touch）模式切换的边沿/冷却/上电行为
//
//   这是 USE_DEMO=0 整机实际生效的触摸路径（c_interact_top -> cap_touch）。
//   为缩短仿真，例化时把时间参数调小：
//       PWR_MASK_MS=3（上电屏蔽 3ms）  COOLDOWN_MS=2（冷却 2ms）
//   时钟 50MHz（#10 半周期 = 20ns）。
//
//   覆盖：
//     T1 上电屏蔽窗内就按住：窗口结束不得翻转（防止上电误触发）
//     T2 正常点按（按下上升沿）：mode 0->1
//     T3 长按超过多个冷却周期：mode 必须恒为 1，不得反复翻转（旧版电平触发会挂）
//     T4 松手（下降沿）：不翻转
//     T5 冷却窗内“松-再按”连点：不翻转；冷却结束后仍按住：也不翻转
//     T6 真正松手、冷却过后再按：翻转 0->1
//   最终还检查 mode_changed 有效脉冲总数 = 3（与 T2/T5/T6 三次翻转对应）。
//====================================================================
module tb_cap_touch;
    reg clk = 0;
    reg rst_n = 0;
    reg touch = 0;
    wire mode, mode_changed, all_notes_off;

    integer err = 0;
    integer toggles = 0;   // 统计 mode_changed 有效脉冲数

    always #10 clk = ~clk;  // 50MHz，周期 20ns

    // 计数有效翻转脉冲
    always @(posedge clk) if (mode_changed) toggles <= toggles + 1;

    cap_touch #(
        .CLK_FREQ_HZ(50_000_000),
        .COOLDOWN_MS(2),
        .PWR_MASK_MS(3)
    ) dut (
        .clk(clk), .rst_n(rst_n), .touch(touch),
        .mode(mode), .mode_changed(mode_changed), .all_notes_off(all_notes_off)
    );

    // 期望电平检查
    task chk;
        input [256*8-1:0] label;
        input expected;
        begin
            if (mode !== expected) begin
                $display("FAIL [%0s] mode=%b expected=%b @%0t", label, mode, expected, $time);
                err = err + 1;
            end else begin
                $display("PASS [%0s] mode=%b @%0t", label, mode, $time);
            end
        end
    endtask

    initial begin
        // ---- 复位 ----
        rst_n = 0; touch = 0;
        #200;
        rst_n = 1;

        // ---- T1 上电屏蔽：复位后 0.5ms 就按住（在 3ms 屏蔽窗内），一直保持到 4.5ms ----
        #500_000;          // 0.5ms
        touch = 1;
        #4_000_000;        // 再保持 4ms（当前 4.5ms，已过 3ms 屏蔽窗）
        chk("T1_touch_in_pwr_mask_no_toggle", 1'b0);
        touch = 0;
        #1_000_000;        // 松手后等 1ms（也超过冷却）

        // ---- T2 正常点按：按下（上升沿）翻转 0->1 ----
        touch = 1;
        #100_000;          // 0.1ms
        chk("T2_press_toggle_to_1", 1'b1);

        // ---- T3 长按：保持 6ms，跨越 3 个冷却周期（2ms），mode 必须恒为 1 ----
        #2_000_000; chk("T3a_hold_2ms_still_1", 1'b1);
        #2_000_000; chk("T3b_hold_4ms_still_1", 1'b1);
        #2_000_000; chk("T3c_hold_6ms_still_1", 1'b1);

        // ---- T4 松手：下降沿不翻转 ----
        touch = 0;
        #1_000_000;
        chk("T4_release_no_toggle", 1'b1);

        // ---- T5 冷却内连点 ----
        // 第一次按下（冷却已过）：翻转 1->0
        touch = 1;
        #100_000; chk("T5a_press_toggle_to_0", 1'b0);
        // 0.2ms 后松手，再 0.1ms 后又按下（距第一次按下仅 0.3ms，在 2ms 冷却内）
        touch = 0;
        #200_000;
        touch = 1;
        #100_000; chk("T5b_rapid_repress_in_cooldown_ignored", 1'b0);
        // 继续按住：2.1ms 后（距第一次按下约 2.4ms，冷却已结束），但没有新上升沿，不翻转
        #2_100_000; chk("T5c_cooldown_over_but_still_held_no_toggle", 1'b0);
        #1_000_000; chk("T5d_still_held_no_toggle", 1'b0);

        // ---- T6 真正松手、冷却过后再按：翻转 0->1 ----
        touch = 0;
        #500_000;
        touch = 1;
        #100_000; chk("T6_fresh_press_after_release_toggle_to_1", 1'b1);

        // ---- 有效翻转总数应为 3（T2、T5a、T6） ----
        if (toggles !== 3) begin
            $display("FAIL [toggle_count] toggles=%0d expected=3", toggles);
            err = err + 1;
        end else begin
            $display("PASS [toggle_count] toggles=3");
        end

        if (err == 0) $display("==== tb_cap_touch ALL PASS ====");
        else          $display("==== tb_cap_touch FAIL err=%0d ====", err);
        $finish;
    end

    // 看门狗，防止卡死
    initial begin
        #50_000_000;
        $display("FAIL watchdog timeout");
        $finish;
    end
endmodule

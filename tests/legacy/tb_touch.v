`timescale 1ns / 1ps
//====================================================================
// tb_touch.v —— 验证 TTP223 手动音色切换（验收第三项）
//   场景：USE_DEMO=1 时摸 TTP223 → 音色翻转（钢琴↔竖琴）
//   验证点：
//     ① 复位后 mode_led=0（钢琴）
//     ② 带毛刺的触摸（<10ms 抖动应被消抖抑制）→ 稳定 10ms 后翻转竖琴
//     ③ 第二次触摸 → 翻回钢琴
//     ④ 第三次触摸 → 竖琴（确认可反复切换）
//   方法：整链实例化 top_system，用 stub 代替 Gowin PLL IP
//====================================================================
// ---- Gowin PLL stub（仿真用：/4 分频，locked 恒 1）----
module pll_12m288 (input clk_50m, output clk_12m288, output locked);
    reg [1:0] div;
    initial div = 0;
    always @(posedge clk_50m) div <= div + 1'b1;
    assign clk_12m288 = div[1];   // 50M/4 = 12.5M（仅仿真，频率不影响本验证）
    assign locked = 1'b1;
endmodule

module tb_touch;
    reg clk = 0, rst_n = 0;
    reg touch_raw = 0;
    reg [7:0]  sensor_gpio = 8'd0;
    reg [95:0] fsr_adc = 96'd0;
    reg calib_run_p = 0, calib_run_o = 0, calib_clear = 0;
    wire bclk, ws, dacdat, mclk;
    wire i2c_sda; wire i2c_scl;
    wire codec_ready, mode_led;
    wire [31:0] active_debug;
    wire [15:0] pcm_mix_debug;
    wire [7:0]  key_on_debug;

    integer err = 0;

    top_system #(.USE_DEMO(1)) uut (
        .clk_50m(clk), .rst_n(rst_n),
        .sensor_gpio(sensor_gpio), .fsr_adc(fsr_adc), .touch_raw(touch_raw),
        .calib_run_p(calib_run_p), .calib_run_o(calib_run_o), .calib_clear(calib_clear),
        .bclk(bclk), .ws(ws), .dacdat(dacdat), .mclk(mclk),
        .i2c_sda(i2c_sda), .i2c_scl(i2c_scl), .codec_ready(codec_ready),
        .active_debug(active_debug), .pcm_mix_debug(pcm_mix_debug),
        .key_on_debug(key_on_debug), .mode_led(mode_led)
    );

    always #10 clk = ~clk;   // 50MHz

    // 一次"触摸"：先给 <10ms 的毛刺（消抖应抑制），再稳定拉高/低
    task touch_once;
        input val;
        begin
            // 毛刺：快速跳 3 次（总时长 <10ms，消抖不应采信）
            repeat (3) begin
                #200 touch_raw = val;
                #200 touch_raw = ~val;
            end
            #200 touch_raw = val;   // 真正稳定
            #11_000_000;            // 等 11ms > 10ms 消抖窗口
        end
    endtask

    task check_mode;
        input expected;
        begin
            if (mode_led !== expected) begin
                $display("[%0t] FAIL: mode_led=%b 期望=%b", $time, mode_led, expected);
                err = err + 1;
            end else begin
                $display("[%0t] PASS: mode_led=%b (期望=%b)", $time, mode_led, expected);
            end
        end
    endtask

    initial begin
        $display("=== TTP223 音色切换验证 ===");
        #100 rst_n = 1'b1;
        #2000;
        check_mode(1'b0);                    // ① 复位=钢琴

        touch_once(1'b1);                    // ② 第一次摸 → 竖琴
        check_mode(1'b1);

        touch_once(1'b0);                    // ③ 第二次摸 → 钢琴
        check_mode(1'b0);

        touch_once(1'b1);                    // ④ 第三次摸 → 竖琴
        check_mode(1'b1);

        if (err == 0) $display("ALL PASS ✓");
        else          $display("FAILED: %0d 项未通过", err);
        $finish;
    end
endmodule

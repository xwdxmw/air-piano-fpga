`timescale 1ns / 1ps
//====================================================================
// tb_optical_harp  光电竖琴拨弦检测测试
//   覆盖：单拨触发+默认力度、不应期屏蔽、多弦同拍 pending 弹出、
//         快速扫弦方向识别（strum_valid）。
//   时钟 50MHz（#10 半周期）。
//   ★激励统一在下降沿（negedge）改变 str，保证 DUT 在下一个上升沿
//     才采样到新电平，避免阻塞赋值与时钟沿同拍导致上升沿丢失。
//   例化参数缩短以便仿真：REFRAC_MS=1(1ms)、STRUM_WINDOW_MS=10(10ms)。
//====================================================================
module tb_optical_harp;
    reg clk = 0, rst_n = 0;
    reg [7:0] str = 0;
    wire ev, on;
    wire [6:0] num, vel;
    wire [1:0] dir;
    wire sv;
    wire [7:0] pluck;

    always #10 clk = ~clk; // 50MHz

    optical_harp #(
        .CLK_FREQ_HZ(50_000_000),
        .REFRAC_MS(1),        // 不应期 1ms = 50000 拍
        .STRUM_WINDOW_MS(10), // 扫弦窗口 10ms = 500000 拍
        .DEFAULT_VELOCITY(7'd90)
    ) dut (
        .clk(clk), .rst_n(rst_n), .string_blocked(str),
        .event_valid(ev), .event_on(on), .event_num(num), .event_vel(vel),
        .strum_dir(dir), .strum_valid(sv), .pluck_pulse(pluck)
    );

    integer errors = 0;
    integer strum_seen = 0;
    always @(posedge clk) if (sv) strum_seen = strum_seen + 1;

    // 下降沿驱动 str（建立半周期，上升沿再被 DUT 采样）
    task set_str(input [7:0] v);
        begin
            @(negedge clk);
            str = v;
        end
    endtask

    // 轮询等待某音符事件（两级流水线，事件晚 2~3 拍）
    // vexp=127 表示不检查力度
    task expect_ev(input [6:0] n, input [6:0] vexp);
        integer t;
        begin
            t = 0;
            while (!(ev && on && num == n) && (t < 1000)) begin
                @(posedge clk);
                t = t + 1;
            end
            if (ev && on && num == n) begin
                if (vexp != 7'd127 && vel != vexp) begin
                    $display("FAIL note=%0d vel exp=%0d got=%0d", n, vexp, vel);
                    errors = errors + 1;
                end else
                    $display("OK  note=%0d vel=%0d", num, vel);
            end else begin
                $display("FAIL exp note=%0d got ev=%b on=%b num=%0d", n, ev, on, num);
                errors = errors + 1;
            end
        end
    endtask

    // 捕获指定音符事件的力度（用于力度单调性测试；超时返回 127 并报错）
    task capture_vel;
        input  [6:0] n;
        output [6:0] v;
        integer t;
        begin
            t = 0;
            while (!(ev && on && num == n) && (t < 1000)) begin
                @(posedge clk);
                t = t + 1;
            end
            if (ev && on && num == n) v = vel;
            else begin
                v = 7'd127;
                $display("FAIL capture_vel timeout waiting note=%0d", n);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        // 复位（在下降沿释放，干净）
        @(negedge clk); rst_n = 0;
        repeat (5) @(negedge clk);
        @(negedge clk); rst_n = 1;
        repeat (5) @(negedge clk);

        // 1) 单拨第 1 弦（idx0→C4=60）：无相邻拨弦，走默认力度 90
        set_str(8'b00000001);
        expect_ev(7'd60, 7'd90);
        set_str(8'b00000000);
        repeat (5) @(posedge clk);

        // 2) 不应期内（远小于 1ms）再拨同一弦：应被忽略
        set_str(8'b00000001);
        @(posedge clk);
        if (ev) begin
            $display("FAIL refractory not working");
            errors = errors + 1;
        end else
            $display("OK  refractory blocks re-trigger");
        set_str(8'b00000000);

        // 3) 复位后拨第 3 弦（idx2→E4=64），默认力度 90
        @(negedge clk); rst_n = 0;
        repeat (2) @(negedge clk);
        @(negedge clk); rst_n = 1;
        repeat (5) @(negedge clk);
        set_str(8'b00000100);
        expect_ev(7'd64, 7'd90);
        set_str(8'b00000000);

        // 4) 复位后多弦同拍：第2弦(D4=62)+第4弦(F4=65)，应收到两个事件，低编号先出
        @(negedge clk); rst_n = 0;
        repeat (2) @(negedge clk);
        @(negedge clk); rst_n = 1;
        repeat (5) @(negedge clk);
        set_str(8'b00001010);
        expect_ev(7'd62, 7'd127);
        expect_ev(7'd65, 7'd127);
        set_str(8'b00000000);

        // 5) 复位后扫弦：0→1→2→3 依次拨，每根间隔 0.5ms（<10ms 窗口）
        //    第 2 根起应识别为扫弦，strum_valid 至少出现 2 次
        @(negedge clk); rst_n = 0;
        repeat (2) @(negedge clk);
        @(negedge clk); rst_n = 1;
        repeat (5) @(negedge clk);
        set_str(8'b00000001); expect_ev(7'd60, 7'd127); set_str(8'b00000000); repeat (25000) @(posedge clk);
        set_str(8'b00000010); expect_ev(7'd62, 7'd127); set_str(8'b00000000); repeat (25000) @(posedge clk);
        set_str(8'b00000100); expect_ev(7'd64, 7'd127); set_str(8'b00000000); repeat (25000) @(posedge clk);
        set_str(8'b00001000); expect_ev(7'd65, 7'd127); set_str(8'b00000000);
        if (strum_seen >= 2)
            $display("OK  strum_valid x%0d (扫弦方向被识别)", strum_seen);
        else begin
            $display("FAIL strum not detected, seen=%0d", strum_seen);
            errors = errors + 1;
        end

        // 6) 扫弦力度单调性：相邻弦间隔越短（扫得越快），力度越大且在 [16,127]
        //    本 tb STRUM_WINDOW_MS=10 -> STRUM_CNT=500000 拍。
        //    慢扫 8ms=400000 拍 / 中扫 4ms=200000 拍 / 快扫 1ms=50000 拍。
        //    （旧版写死系数 156 时，快扫会溢出回绕、力度反而更小，这里会 FAIL。）
        begin : velmono
            reg [6:0] vs, vm, vf;

            // 慢扫：拨弦0(C4) 后间隔 8ms 拨弦1(D4)
            @(negedge clk); rst_n = 0;
            repeat (2) @(negedge clk);
            @(negedge clk); rst_n = 1;
            repeat (5) @(negedge clk);
            set_str(8'b00000001); expect_ev(7'd60, 7'd127); set_str(8'b00000000);
            repeat (400000) @(posedge clk);
            set_str(8'b00000010); capture_vel(7'd62, vs); set_str(8'b00000000);

            // 中扫：间隔 4ms
            @(negedge clk); rst_n = 0;
            repeat (2) @(negedge clk);
            @(negedge clk); rst_n = 1;
            repeat (5) @(negedge clk);
            set_str(8'b00000001); expect_ev(7'd60, 7'd127); set_str(8'b00000000);
            repeat (200000) @(posedge clk);
            set_str(8'b00000010); capture_vel(7'd62, vm); set_str(8'b00000000);

            // 快扫：间隔 1ms
            @(negedge clk); rst_n = 0;
            repeat (2) @(negedge clk);
            @(negedge clk); rst_n = 1;
            repeat (5) @(negedge clk);
            set_str(8'b00000001); expect_ev(7'd60, 7'd127); set_str(8'b00000000);
            repeat (50000) @(posedge clk);
            set_str(8'b00000010); capture_vel(7'd62, vf); set_str(8'b00000000);

            $display("strum velocity: slow(8ms)=%0d mid(4ms)=%0d fast(1ms)=%0d", vs, vm, vf);
            if ((vs >= 16) && (vs <= 127) && (vm > vs) && (vf > vm) && (vf <= 127))
                $display("OK  strum velocity monotonic & in [16,127] (fast>mid>slow)");
            else begin
                $display("FAIL strum velocity not monotonic or out of range");
                errors = errors + 1;
            end
        end

        if (errors == 0) $display("==== tb_optical_harp ALL PASS ====");
        else             $display("==== tb_optical_harp FAIL errors=%0d ====", errors);
        $finish;
    end

    // 全局看门狗，防止卡死
    initial begin
        #(50_000_000);
        $display("FAIL watchdog timeout");
        $finish;
    end
endmodule

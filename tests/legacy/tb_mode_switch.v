`timescale 1ns/1ps
//====================================================================
// tb_mode_switch.v  系统级验证：钢琴↔竖琴模式切换 + 竖琴触发
//
// 直接实例化 c_interact_top（KEY_MASK=0 屏蔽钢琴，避免 ADS 数据干扰；
// USE_ADC=0 竖琴走 GPIO），在 50MHz 下验证：
//   阶段A  mode=0 钢琴：遮挡红外 sensor_gpio 不应产生 note_on（模式 mux 隔离）
//   阶段B  点动触摸（按住高、松手低）：mode 0→1，且只翻转一次、松手不翻转，
//          同时打出 1 拍 all_notes_off
//   阶段C  mode=1 竖琴：遮挡第 1 根弦（红外 DO 拉低，IR_ACTIVE_LOW 归一化为遮挡）
//          → 产生 1 个 note_on，音号 60(C4)，单拨默认力度 90
//   阶段D  再点动触摸：mode 1→0，all_notes_off 再打 1 拍
//   阶段E  mode=0 钢琴：再次遮挡红外不产生 note_on
//
// 为缩短仿真，用 defparam 把 cap_touch 的上电屏蔽/冷却由 500ms/300ms 改为 1ms。
// 竖琴 30ms 不应期保持不变（真实值），用于验证切竖琴后必须等不应期过再拨。
//====================================================================
module tb_mode_switch;
    localparam CLK_HZ = 50_000_000;
    reg clk=0; always #10 clk=~clk;   // 50MHz，周期 20ns
    reg rst_n=0;

    reg [7:0] sensor_gpio = 8'hFF;    // 红外：上拉=未遮挡；遮挡时对应位拉低
    reg [95:0] adc_p = 96'd0;
    reg        adc_valid = 1'b0;
    reg [95:0] adc_o = 96'd0;
    reg        touch_raw = 1'b0;

    wire       note_on, note_off, mode, mode_changed, all_notes_off;
    wire [6:0] note_num, velocity, note_off_num;
    wire [7:0] string_blocked, key_on;
    wire       calib_done_p, calib_done_o;
    wire [1:0] strum_dir;
    wire       strum_valid;

    c_interact_top #(
        .WIDTH(8), .ADC_W(12), .USE_ADC(0),
        .KEY_MASK(8'h00),               // 屏蔽全部钢琴键，钢琴路径恒不触发
        .CLK_FREQ_HZ(CLK_HZ),
        .IR_ACTIVE_LOW(1)               // 模块遮挡 DO=低
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .sensor_gpio(sensor_gpio), .adc_p(adc_p), .adc_valid(adc_valid),
        .adc_o(adc_o), .touch_raw(touch_raw),
        .calib_run_p(1'b0), .calib_run_o(1'b0), .calib_clear(1'b0),
        .note_on(note_on), .note_num(note_num), .velocity(velocity),
        .note_off(note_off), .note_off_num(note_off_num), .aftertouch(),
        .mode(mode), .mode_changed(mode_changed), .all_notes_off(all_notes_off),
        .string_blocked(string_blocked), .key_on(key_on),
        .calib_done_p(calib_done_p), .calib_done_o(calib_done_o),
        .strum_dir(strum_dir), .strum_valid(strum_valid)
    );

    // 把上电屏蔽/冷却缩短到 1ms（50000 拍）
    defparam dut.u_cap.PWR_MASK_MS  = 1;
    defparam dut.u_cap.COOLDOWN_MS  = 1;

    // ---- 事件记录 ----
    integer on_cnt=0, ano_cnt=0, toggles=0;
    reg [6:0] on_num[0:31], on_vel[0:31];
    reg [6:0] mode_seen=0;
    always @(posedge clk) begin
        if (note_on) begin
            on_num[on_cnt] <= note_num;
            on_vel[on_cnt] <= velocity;
            on_cnt <= on_cnt + 1;
        end
        if (all_notes_off) ano_cnt <= ano_cnt + 1;
        if (mode_changed)   toggles <= toggles + 1;
    end

    // 分阶段 note_on 计数（每个阶段开始清零）
    integer phase_on=0;
    task PHASE_RESET; begin phase_on=0; end endtask
    always @(posedge clk) if (note_on) phase_on=phase_on+1;

    initial begin
        $dumpfile("tb_ms.vcd"); $dumpvars(0,tb_mode_switch);

        // 复位
        repeat(500) @(posedge clk);
        rst_n=1;
        // 等过上电屏蔽（1ms=50000 拍），留足余量
        repeat(100000) @(posedge clk);

        //========== 阶段A：mode=0 钢琴，遮挡红外第 0 弦 ==========
        PHASE_RESET;
        sensor_gpio[0]=1'b0;             // 遮挡（DO 拉低）
        repeat(200000) @(posedge clk);  // 4ms（远过 40us 消抖）
        sensor_gpio[0]=1'b1;            // 离开
        repeat(100000) @(posedge clk);
        $display("PHASE A  mode=%0d  piano-mode IR notes = %0d (expect 0)", mode, phase_on);
        if (phase_on!==0) begin $display("FAIL [A] piano mode must ignore IR"); $finish; end

        //========== 阶段B：点动触摸切到竖琴 ==========
        touch_raw=1'b1;                  // 按下
        repeat(5000) @(posedge clk);    // 高 5000 拍（过 40us 消抖）
        touch_raw=1'b0;                  // 松手（点动）
        repeat(100000) @(posedge clk);  // 留余量
        $display("PHASE B  mode=%0d  toggles=%0d  ano_cnt=%0d (expect mode=1, 1 toggle, >=1 ano)",
                 mode, toggles, ano_cnt);
        if (mode!==1'b1)        begin $display("FAIL [B] mode should become 1 (harp)"); $finish; end
        if (toggles!==1)        begin $display("FAIL [B] one momentary press must toggle exactly once"); $finish; end
        if (ano_cnt<1)          begin $display("FAIL [B] switch must issue all_notes_off"); $finish; end

        //========== 阶段C：mode=1 竖琴。先等 30ms 不应期 + 60ms 扫弦窗口
        //          （阶段A 虽被静音，但 optical_harp 内部仍更新了扫弦时间戳；
        //           等满 64ms 使其成为独立单拨，力度才取默认值 90）====
        PHASE_RESET;
        repeat(3200000) @(posedge clk); // 64ms > 30ms 不应期且 > 60ms 扫弦窗口
        sensor_gpio[0]=1'b0;             // 重新拨第 0 弦（遮挡）
        repeat(200000) @(posedge clk);  // 4ms 遮挡
        sensor_gpio[0]=1'b1;
        repeat(200000) @(posedge clk);  // 等事件弹出
        $display("PHASE C  mode=%0d  harp-mode notes = %0d", mode, phase_on);
        if (phase_on<1) begin $display("FAIL [C] harp mode must sound on string block"); $finish; end

        //========== 阶段D：再点动触摸切回钢琴 ==========
        repeat(60000) @(posedge clk);   // 过冷却 1ms
        touch_raw=1'b1;
        repeat(5000) @(posedge clk);
        touch_raw=1'b0;
        repeat(100000) @(posedge clk);
        $display("PHASE D  mode=%0d  toggles=%0d  ano_cnt=%0d (expect mode=0, 2 toggles, >=2 ano)",
                 mode, toggles, ano_cnt);
        if (mode!==1'b0) begin $display("FAIL [D] mode should return to 0 (piano)"); $finish; end
        if (toggles!==2) begin $display("FAIL [D] total toggles should be 2"); $finish; end

        //========== 阶段E：mode=0 钢琴，再次遮挡红外不应响 ==========
        PHASE_RESET;
        repeat(1600000) @(posedge clk);
        sensor_gpio[0]=1'b0;
        repeat(200000) @(posedge clk);
        sensor_gpio[0]=1'b1;
        repeat(100000) @(posedge clk);
        $display("PHASE E  mode=%0d  piano-mode IR notes = %0d (expect 0)", mode, phase_on);
        if (phase_on!==0) begin $display("FAIL [E] back in piano mode must ignore IR"); $finish; end

        // 汇总所有 note_on 事件（应只在阶段C出现：num=60，单拨力度=90）
        $display("---- captured note_on events (total %0d) ----", on_cnt);
        begin : dump
            integer j;
            for (j=0;j<on_cnt;j=j+1)
                $display("  note_on num=%0d vel=%0d", on_num[j], on_vel[j]);
        end
        if (on_cnt!==1) begin $display("FAIL [C] expect exactly 1 note_on total, got %0d", on_cnt); $finish; end
        if (on_num[0]!==60) begin $display("FAIL [C] string0 note must be 60(C4), got %0d", on_num[0]); $finish; end
        if (on_vel[0]!==90) begin $display("FAIL [C] single pluck default velocity must be 90, got %0d", on_vel[0]); $finish; end

        $display("==== tb_mode_switch ALL PASS ====");
        $finish;
    end

    // 看门狗
    initial begin
        #200_000_000;  // 200ms 上限
        $display("FAIL watchdog timeout"); $finish;
    end
endmodule

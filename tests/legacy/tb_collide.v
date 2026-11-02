`timescale 1ns/1ps
// tb_collide: 验证审阅报告 #1（起音/松键撞车不丢 NOTE_OFF）
//              与 #3（无事件时 aftertouch 仍然有效）
module tb_collide;
    reg clk = 0; always #10 clk = ~clk;
    reg rst_n = 0;
    reg [95:0]  adc_p = 0;
    reg         adc_valid = 0;
    reg         adc_ch_valid = 0;
    reg [2:0]   adc_ch_idx = 0;
    reg [11:0]  adc_ch_data = 0;

    wire note_on, note_off, velupd;
    wire [6:0] note_num, velocity, note_off_num, aftertouch, velupd_num, velupd_vel;
    wire mode, mode_changed, all_notes_off, ev_timbre;
    wire [7:0] key_on, string_blocked;
    wire calib_done_p, calib_done_o;
    wire [1:0] strum_dir;
    wire strum_valid;

    c_interact_top #(
        .WIDTH(8), .ADC_W(12), .USE_ADC(0), .KEY_MASK(8'hFF), .CLK_FREQ_HZ(50_000_000)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .sensor_gpio(8'hFF), .adc_p(adc_p), .adc_valid(adc_valid),
        .adc_ch_valid(adc_ch_valid), .adc_ch_idx(adc_ch_idx), .adc_ch_data(adc_ch_data),
        .adc_o({12*8{1'b0}}), .touch_raw(1'b0),
        .calib_run_p(1'b0), .calib_run_o(1'b0), .calib_clear(1'b0),
        .note_on(note_on), .note_num(note_num), .velocity(velocity),
        .note_off(note_off), .note_off_num(note_off_num), .aftertouch(aftertouch),
        .velupd(velupd), .velupd_num(velupd_num), .velupd_vel(velupd_vel),
        .event_timbre(ev_timbre),
        .mode(mode), .mode_changed(mode_changed), .all_notes_off(all_notes_off),
        .string_blocked(string_blocked), .key_on(key_on),
        .calib_done_p(calib_done_p), .calib_done_o(calib_done_o),
        .strum_dir(strum_dir), .strum_valid(strum_valid)
    );

    integer n_on = 0, n_off = 0;
    always @(posedge clk) begin
        if (note_on)  begin n_on  = n_on  + 1; $display("  ON  num=%0d", note_num); end
        if (note_off) begin n_off = n_off + 1; $display("  OFF num=%0d", note_off_num); end
    end

    // 逐通道推一路数据（模拟 ADS 驱动）
    task ch(input [2:0] idx, input [11:0] val);
        begin
            @(posedge clk);
            adc_ch_idx = idx; adc_ch_data = val; adc_ch_valid = 1'b1;
            @(posedge clk);
            adc_ch_valid = 1'b0;
        end
    endtask

    integer at_ok = 0, at_bad = 0;
    initial begin
        #300 rst_n = 1;
        repeat (50) @(posedge clk);

        // ---- 第一轮：0~3 键按下 ----
        for (integer k=0;k<4;k=k+1) ch(k[2:0], 12'd1800);
        adc_valid = 1; @(posedge clk); adc_valid = 0;
        repeat (60) @(posedge clk);
        $display("按下 4 键后：ON=%0d OFF=%0d", n_on, n_off);

        // ---- 第二轮：0~3 松开，同时 4~7 按下（同一轮 → 撞车）----
        for (integer k=0;k<4;k=k+1) ch(k[2:0], 12'd0);        // 松开
        for (integer k=4;k<8;k=k+1) ch(k[2:0], 12'd1800);     // 按下
        adc_valid = 1; @(posedge clk); adc_valid = 0;
        repeat (200) @(posedge clk);

        $display("--- 结果：ON=%0d (期望 8)  OFF=%0d (期望 4) ---", n_on, n_off);
        if (n_on == 8 && n_off == 4) $display("PASS: 起音/松键撞车不丢事件");
        else                         $display("FAIL: 有事件丢失");

        // ---- aftertouch 连续性：4~7 还按着，等 aftertouch 低通更新（1ms 周期）----
        #2_000_000;                       // 2ms，够 aftertouch 低通跑几轮
        repeat (100) begin
            @(posedge clk);
            if (aftertouch != 7'd0) at_ok = at_ok + 1; else at_bad = at_bad + 1;
        end
        $display("aftertouch 常驻检查：非零 %0d 拍 / 零 %0d 拍", at_ok, at_bad);
        if (at_bad == 0) $display("PASS: 按住期间 aftertouch 连续有效");
        else             $display("FAIL: aftertouch 断断续续");
        $finish;
    end
endmodule

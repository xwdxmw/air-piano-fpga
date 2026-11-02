`timescale 1ns/1ps
// tb_autozero: 验证"上电自动调零"能否消除恒定直流偏置造成的幽灵键
module tb_autozero;
    reg clk = 0; always #10 clk = ~clk;
    reg rst_n = 0;
    reg         adc_valid = 0, adc_ch_valid = 0;
    reg  [2:0]  adc_ch_idx = 0;
    reg  [11:0] adc_ch_data = 0;

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
        .sensor_gpio(8'hFF), .adc_p(96'd0), .adc_valid(adc_valid),
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

    task one_round(input [11:0] v0,v1,v2,v3,v4,v5,v6,v7);
        integer k;
        begin
            for (k = 0; k < 8; k = k + 1) begin
                @(posedge clk);
                adc_ch_idx = k[2:0];
                case (k)
                    0: adc_ch_data = v0; 1: adc_ch_data = v1;
                    2: adc_ch_data = v2; 3: adc_ch_data = v3;
                    4: adc_ch_data = v4; 5: adc_ch_data = v5;
                    6: adc_ch_data = v6; 7: adc_ch_data = v7;
                endcase
                adc_ch_valid = 1'b1;
                @(posedge clk);
                adc_ch_valid = 1'b0;
            end
            adc_valid = 1'b1; @(posedge clk); adc_valid = 1'b0;
        end
    endtask

    integer n_on = 0, i, err = 0;
    always @(posedge clk) if (note_on) n_on = n_on + 1;

    initial begin
        #300 rst_n = 1;
        repeat (10) @(posedge clk);

        // ---- 校准期：喂 8 路恒定 300 码（模拟 ADS 的直流偏置）----
        for (i = 0; i < 70; i = i + 1) one_round(300,300,300,300,300,300,300,300);
        $display("校准完成=%b", dut.az_done);
        if (dut.az_done !== 1'b1) begin $display("  !! FAIL: 校准没完成"); err = err + 1; end

        // ---- 场景 A：偏置仍然存在（300 码），不该有任何按键 ----
        n_on = 0;
        for (i = 0; i < 20; i = i + 1) one_round(300,300,300,300,300,300,300,300);
        $display("场景A 恒偏置 300：key_on=%b 事件=%0d (期望 0 / 0)", key_on, n_on);
        if (key_on !== 8'd0 || n_on != 0) begin $display("  !! FAIL: 偏置造成幽灵键"); err = err + 1; end

        // ---- 场景 B：偏置 + ch0 真的按下（300+1800）----
        n_on = 0;
        for (i = 0; i < 5; i = i + 1) one_round(2100,300,300,300,300,300,300,300);
        $display("场景B 按 ch0：key_on=%b 事件=%0d (期望 00000001 / 1)", key_on, n_on);
        if (key_on !== 8'b0000_0001) begin $display("  !! FAIL: 位图不对"); err = err + 1; end
        if (n_on != 1)               begin $display("  !! FAIL: 事件数不对"); err = err + 1; end

        $display("--- 失败项：%0d ---", err);
        if (err == 0) $display("PASS: 自动调零消除了恒定偏置的幽灵键，且不影响正常按键");
        else          $display("FAIL");
        $finish;
    end
endmodule

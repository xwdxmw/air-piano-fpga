`timescale 1ns / 1ps
// 验证 KEY_MASK：AIN1~AIN6 悬空乱跳时不得发声；
// AIN0 与 AIN7 同时按下时，应各发一个 NOTE_ON。
module tb_key_mask;
    reg clk = 0;
    always #500 clk = ~clk;      // 1MHz

    reg rst_n = 0;
    reg [95:0] adc_p = 0;
    reg adc_valid = 0;
    reg [63:0] sensor_gpio = 0;
    reg [95:0] adc_o = 0;
    reg touch_raw = 0;

    wire note_on, note_off;
    wire [6:0] note_num, velocity, note_off_num, aftertouch;
    wire mode, mode_changed, all_notes_off;
    wire [7:0] key_on;
    wire [7:0] string_blocked;
    wire calib_done_p, calib_done_o;
    wire [1:0] strum_dir;
    wire strum_valid;

    c_interact_top #(
        .WIDTH(8), .ADC_W(12), .USE_ADC(0),
        .KEY_MASK(8'h81), .CLK_FREQ_HZ(1_000_000)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .sensor_gpio(sensor_gpio[7:0]), .adc_p(adc_p), .adc_valid(adc_valid),
        .adc_o(adc_o), .touch_raw(touch_raw),
        .calib_run_p(1'b0), .calib_run_o(1'b0), .calib_clear(1'b0),
        .note_on(note_on), .note_num(note_num), .velocity(velocity),
        .note_off(note_off), .note_off_num(note_off_num),
        .aftertouch(aftertouch),
        .mode(mode), .mode_changed(mode_changed), .all_notes_off(all_notes_off),
        .string_blocked(string_blocked), .key_on(key_on),
        .calib_done_p(calib_done_p), .calib_done_o(calib_done_o),
        .strum_dir(strum_dir), .strum_valid(strum_valid)
    );

    integer errors = 0;
    integer on_count = 0;
    integer off_count = 0;
    integer i;
    reg [6:0] on_num_q [0:3];
    reg [6:0] off_num_q [0:3];

    always @(posedge clk) begin
        if (note_on) begin
            on_num_q[on_count] = note_num;
            on_count = on_count + 1;
            $display("NOTE_ON  num=%0d vel=%0d", note_num, velocity);
        end
        if (note_off) begin
            off_num_q[off_count] = note_off_num;
            off_count = off_count + 1;
            $display("NOTE_OFF num=%0d", note_off_num);
        end
    end

    task pulse_valid;
        begin
            adc_valid = 1'b1;
            @(posedge clk);
            adc_valid = 1'b0;
            @(posedge clk);
        end
    endtask

    initial begin
        $display("==== tb_key_mask start ====");
        #3000 rst_n = 1;
        repeat (20) @(posedge clk);

        // AIN1~AIN6 故意给高中毒值，模拟悬空乱跳；它们应被 KEY_MASK 屏蔽
        adc_p = 96'd0;
        for (i = 1; i <= 6; i = i + 1)
            adc_p[i*12 +: 12] = 12'd4000;
        pulse_valid();
        repeat (10000) @(posedge clk);
        if (on_count != 0) begin
            $display("FAIL: floating AIN1~6 caused %0d note(s)", on_count);
            errors = errors + 1;
        end else $display("PASS: floating AIN1~6 ignored");

        // AIN0 / AIN7 同时按下
        adc_p[11:0]   = 12'd1800;
        adc_p[95:84]  = 12'd1800;
        pulse_valid();
        repeat (10000) @(posedge clk);

        if (on_count != 2) begin
            $display("FAIL: expected 2 NOTE_ON, got %0d", on_count);
            errors = errors + 1;
        end else if (!((on_num_q[0] == 7'd60 && on_num_q[1] == 7'd72) ||
                       (on_num_q[0] == 7'd72 && on_num_q[1] == 7'd60))) begin
            $display("FAIL: note nums %0d %0d", on_num_q[0], on_num_q[1]);
            errors = errors + 1;
        end else $display("PASS: AIN0/AIN7 both emitted NOTE_ON");

        adc_p[11:0]  = 12'd0;
        adc_p[95:84] = 12'd0;
        pulse_valid();
        repeat (20) @(posedge clk);

        if (off_count != 2) begin
            $display("FAIL: expected 2 NOTE_OFF, got %0d", off_count);
            errors = errors + 1;
        end else $display("PASS: both NOTE_OFF emitted");

        if (errors == 0) $display("==== ALL TESTS PASSED ====");
        else $display("==== %0d ERRORS ====", errors);
        $finish;
    end

    initial begin
        #30_000_000;
        $display("ERROR: watchdog timeout");
        $finish;
    end
endmodule
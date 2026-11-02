`timescale 1ns / 1ps
// 8 路同时按下/松开的压力事件自测
module tb_eight_keys;
    reg clk = 0;
    always #500 clk = ~clk;      // 1MHz

    reg rst_n = 0;
    reg [95:0] adc_p = 0;
    reg adc_valid = 0;

    wire note_on, note_off;
    wire [6:0] note_num, velocity, note_off_num, aftertouch;
    wire mode, mode_changed, all_notes_off;
    wire [7:0] key_on, string_blocked;
    wire calib_done_p, calib_done_o;
    wire [1:0] strum_dir;
    wire strum_valid;

    c_interact_top #(
        .WIDTH(8), .ADC_W(12), .USE_ADC(0),
        .KEY_MASK(8'hFF), .CLK_FREQ_HZ(1_000_000)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .sensor_gpio(8'd0), .adc_p(adc_p), .adc_valid(adc_valid),
        .adc_o({12*8{1'b0}}), .touch_raw(1'b0),
        .calib_run_p(1'b0), .calib_run_o(1'b0), .calib_clear(1'b0),
        .note_on(note_on), .note_num(note_num), .velocity(velocity),
        .note_off(note_off), .note_off_num(note_off_num), .aftertouch(aftertouch),
        .mode(mode), .mode_changed(mode_changed), .all_notes_off(all_notes_off),
        .string_blocked(string_blocked), .key_on(key_on),
        .calib_done_p(calib_done_p), .calib_done_o(calib_done_o),
        .strum_dir(strum_dir), .strum_valid(strum_valid)
    );

    integer i;
    integer on_count = 0;
    integer off_count = 0;
    integer errors = 0;
    reg [6:0] on_num [0:7];
    reg [6:0] off_num [0:7];

    always @(posedge clk) begin
        if (note_on) begin
            on_num[on_count] = note_num;
            if (velocity < 7'd24) begin
                $display("FAIL: note %0d velocity=%0d", note_num, velocity);
                errors = errors + 1;
            end
            $display("NOTE_ON  [%0d] num=%0d vel=%0d", on_count, note_num, velocity);
            on_count = on_count + 1;
        end
        if (note_off) begin
            off_num[off_count] = note_off_num;
            $display("NOTE_OFF [%0d] num=%0d", off_count, note_off_num);
            off_count = off_count + 1;
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
        $display("==== tb_eight_keys start ====");
        #3000 rst_n = 1;
        repeat (20) @(posedge clk);

        // 8 路同时按下
        for (i = 0; i < 8; i = i + 1)
            adc_p[i*12 +: 12] = 12'd1800;
        pulse_valid();
        repeat (10000) @(posedge clk);

        if (on_count != 8) begin
            $display("FAIL: expected 8 NOTE_ON, got %0d", on_count);
            errors = errors + 1;
        end else begin

            if (!(on_num[0]==60 && on_num[1]==62 && on_num[2]==64 && on_num[3]==65 &&
                  on_num[4]==67 && on_num[5]==69 && on_num[6]==71 && on_num[7]==72)) begin
                $display("FAIL: note order wrong");
                errors = errors + 1;
            end else $display("PASS: 8 NOTE_ON, correct notes");
        end

        // 8 路同时松开
        adc_p = 96'd0;
        pulse_valid();
        repeat (30) @(posedge clk);

        if (off_count != 8) begin
            $display("FAIL: expected 8 NOTE_OFF, got %0d", off_count);
            errors = errors + 1;
        end else $display("PASS: 8 NOTE_OFF");

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
`timescale 1ns/1ps
// tb_harp: v2 复审 #1 —— 队列非空时新到的竖琴事件是否被丢掉
//   场景：先来一个竖琴事件（与钢琴撞车→入队），紧接着第二个竖琴事件在
//         "无撞车"的下一拍到达。旧代码会直接丢掉第二个。
module tb_harp;
    reg clk = 0; always #10 clk = ~clk;
    reg rst_n = 0;
    reg [95:0] adc_p = 0;
    reg adc_valid = 0, adc_ch_valid = 0;
    reg [2:0] adc_ch_idx = 0;
    reg [11:0] adc_ch_data = 0;

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

    integer n_harp = 0;
    always @(posedge clk) begin
        if (note_on && ev_timbre) begin
            n_harp = n_harp + 1;
            $display("  HARP NOTE_ON num=%0d  (第 %0d 个)", note_num, n_harp);
        end
    end

    initial begin
        #200 rst_n = 1;
        repeat (20) @(posedge clk);

        // ---- 第 1 拍：竖琴事件 + 模拟钢琴撞车 → 入队 ----
        @(negedge clk);
        force dut.p_ev  = 1'b1;
        force dut.h_valid = 1'b1;
        force dut.h_num   = 7'd64;
        force dut.h_vel   = 7'd80;
        @(negedge clk);
        // ---- 第 2 拍：又来一个竖琴事件，但这次没有撞车 ----
        //      旧代码：取队头 64，新的 67 被丢弃
        //      新代码：取队头 64，同时把 67 入队
        force dut.p_ev  = 1'b0;
        force dut.h_num   = 7'd67;
        @(negedge clk);
        // ---- 第 3 拍：恢复正常，队列里的 67 应该出来 ----
        release dut.h_valid;
        force dut.h_valid = 1'b0;
        release dut.h_num;
        release dut.h_vel;
        release dut.p_ev;
        repeat (10) @(posedge clk);

        $display("--- 竖琴 NOTE_ON 共 %0d 个（期望 2）---", n_harp);
        if (n_harp == 2) $display("PASS: 队列非空时新事件不再丢失");
        else             $display("FAIL: 丢了 %0d 个", 2-n_harp);
        $finish;
    end
endmodule

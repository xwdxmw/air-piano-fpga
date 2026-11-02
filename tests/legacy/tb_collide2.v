`timescale 1ns/1ps
// tb_collide2: v2 复审 #2 —— 原 tb_collide 没有真正制造仲裁重合
//   这里直接 force 让 press_pend 和 rel_pend 同拍非零，
//   验证两条事件都能发出去（旧代码会丢 NOTE_OFF）。
module tb_collide2;
    reg clk = 0; always #10 clk = ~clk;
    reg rst_n = 0;
    reg [95:0] adc = 0;
    reg [11:0] th_down = 12'd110, th_up = 12'd180;
    reg        th_load = 1;
    reg [11:0] raw_max = 12'd3000, calib_dead = 12'd110;

    wire [7:0] key_on;
    wire press_valid, rel_valid, vu_valid;
    wire [6:0] press_num, press_vel, rel_num, vu_num, vu_vel, aftertouch;

    pressure_detect #(.WIDTH(8), .ADC_W(12), .CLK_FREQ_HZ(50_000_000)) dut (
        .clk(clk), .rst_n(rst_n),
        .adc(adc), .th_down(th_down), .th_up(th_up), .th_load(th_load),
        .raw_max(raw_max), .calib_dead(calib_dead),
        .key_on(key_on),
        .press_valid(press_valid), .press_num(press_num), .press_vel(press_vel),
        .velupd_valid(vu_valid), .velupd_num(vu_num), .velupd_vel(vu_vel),
        .rel_valid(rel_valid), .rel_num(rel_num), .aftertouch(aftertouch)
    );

    integer n_on = 0, n_off = 0, overlap = 0;
    always @(posedge clk) begin
        if (dut.p_busy && dut.r_busy) overlap = overlap + 1;
        if (press_valid) begin n_on = n_on + 1; $display("  PRESS num=%0d", press_num); end
        if (rel_valid)   begin n_off = n_off + 1; $display("  REL   num=%0d", rel_num); end
    end

    initial begin
        #200 rst_n = 1;
        repeat (20) @(posedge clk);

        // 同拍制造：键0 起音 pending + 键1 松键 pending
        @(negedge clk);
        force dut.press_pend = 8'b0000_0001;
        force dut.rel_pend   = 8'b0000_0010;
        @(negedge clk);
        release dut.press_pend;
        release dut.rel_pend;
        repeat (20) @(posedge clk);

        $display("--- press=%0d rel=%0d 仲裁重合次数=%0d ---", n_on, n_off, overlap);
        if (n_on >= 1 && n_off == 1 && overlap >= 1)
            $display("PASS: 同拍撞车时两条事件都发出（且确实重合过）");
        else if (overlap == 0)
            $display("FAIL: 测试没造出重合，无效");
        else
            $display("FAIL: 丢事件");
        $finish;
    end
endmodule

`timescale 1ns/1ps
// tb_push2: 复审 #4 —— 连续两拍各来 2 条事件，4 条必须全部发出
module tb_push2;
    reg clk = 0; always #10 clk = ~clk;
    reg rst_n = 0;
    reg [7:0] sg = 8'hFF; reg touch = 0;
    wire ads_sclk, ads_mosi, ads_cs_n, ads_reset_n;
    reg  ads_miso = 0, ads_drdy = 1;
    wire bclk, ws, dacdat, i2c_sda;
    wire led_raw, led_pll, led_key, led_adc;
    wire lcd_sclk, lcd_mosi, lcd_cs_n, lcd_dc, ws2812;

    top_system #(.BOOT_SEL_MS(1)) dut(
        .clk_50m(clk), .rst_n(rst_n),
        .sensor_gpio(sg), .touch_raw(touch),
        .calib_run_p(1'b0), .calib_run_o(1'b0), .calib_clear(1'b0),
        .ads_sclk(ads_sclk), .ads_mosi(ads_mosi), .ads_miso(ads_miso),
        .ads_cs_n(ads_cs_n), .ads_drdy(ads_drdy), .ads_reset_n(ads_reset_n),
        .bclk(bclk), .ws(ws), .dacdat(dacdat), .i2c_sda(i2c_sda),
        .led_raw(led_raw), .led_pll(led_pll), .led_key(led_key), .led_adc(led_adc),
        .lcd_sclk(lcd_sclk), .lcd_mosi(lcd_mosi), .lcd_cs_n(lcd_cs_n), .lcd_dc(lcd_dc),
        .ws2812(ws2812));

    integer pushed = 0;
    always @(posedge clk) if (dut.push_any) begin
        pushed = pushed + 1;
        $display("  PUSH type=%0d num=%0d", dut.push_data[15:14], dut.push_data[13:7]);
    end

    initial begin
        #200 rst_n = 1;
        repeat (50) @(posedge clk);

        // 连续两拍，每拍同时给 ON + OFF
        @(negedge clk);
        force dut.note_on_c = 1'b1;  force dut.note_num_c = 7'd60;
        force dut.note_off_c = 1'b1; force dut.note_off_num_c = 7'd62;
        @(negedge clk);
        // 第二拍同样的组合
        force dut.note_num_c = 7'd64;
        force dut.note_off_num_c = 7'd65;
        @(negedge clk);
        force dut.note_on_c = 1'b0;
        force dut.note_off_c = 1'b0;
        @(negedge clk);
        repeat (30) @(posedge clk);

        $display("--- 共推出 %0d 条（期望 4）---", pushed);
        if (pushed >= 4) $display("PASS: 连续两拍双事件全部发出");
        else             $display("FAIL: 丢了 %0d 条", 4-pushed);
        $finish;
    end
endmodule

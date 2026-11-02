`timescale 1ns/1ps
// tb_push: v2 复审 #3 —— 顶层同拍两条事件是否都进了 FIFO
module tb_push;
    reg clk = 0; always #10 clk = ~clk;
    reg rst_n = 0;
    reg [7:0] sg = 8'hFF;
    reg touch = 0;
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
    always @(posedge clk) begin
        if (dut.push_any) begin
            pushed = pushed + 1;
            $display("  PUSH type=%0d num=%0d vel=%0d", dut.push_data[15:14],
                     dut.push_data[13:7], dut.push_data[6:0]);
        end
    end

    initial begin
        #200 rst_n = 1;
        repeat (50) @(posedge clk);

        // 同拍强制起音 + 松键（模拟两条事件同时到达）
        @(negedge clk);
        force dut.note_on_c      = 1'b1;
        force dut.note_num_c     = 7'd60;
        force dut.velocity_c     = 7'd100;
        force dut.note_off_c     = 1'b1;
        force dut.note_off_num_c = 7'd62;
        @(negedge clk);
        force dut.note_on_c  = 1'b0;
        force dut.note_off_c = 1'b0;
        @(negedge clk);
        release dut.note_on_c;  release dut.note_num_c;  release dut.velocity_c;
        release dut.note_off_c; release dut.note_off_num_c;
        repeat (20) @(posedge clk);

        $display("--- 共推入 %0d 条（期望 >= 2）---", pushed);
        if (pushed >= 2) $display("PASS: 同拍两条事件都进了 FIFO");
        else             $display("FAIL: 丢了一条");
        $finish;
    end
endmodule

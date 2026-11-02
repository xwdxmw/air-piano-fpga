`timescale 1ns / 1ps
//====================================================================
// optical_quantize  单路 ADC → 「弦是否被遮挡」数字电平（骨架原模块补全）
//   遮挡 → 光强下降 → ADC 下降 → 低于 th_blocked 判定「被挡」
//   解除需高于 th_open，形成回差，防阈值附近抖动。
//   th_* 由 optical_calib 标定后写入（或上电默认）。
//====================================================================
module optical_quantize #(
    parameter integer ADC_W           = 12,
    parameter integer THRESHOLD_DEF   = 12'd2000,
    parameter integer HYST_DEF        = 12'd120
)(
    input  wire                clk,
    input  wire                rst_n,
    input  wire [ADC_W-1:0]    adc_val,
    input  wire [ADC_W-1:0]    th_blocked,  // 低于此 = 挡住
    input  wire [ADC_W-1:0]    th_open,     // 高于此 = 打开
    input  wire                th_load,     // 1=使用校准阈值；0=用默认
    output reg                 string_blocked
);
    wire [ADC_W-1:0] th_b = th_load ? th_blocked : THRESHOLD_DEF[ADC_W-1:0];
    wire [ADC_W-1:0] th_o = th_load ? th_open    : (THRESHOLD_DEF[ADC_W-1:0] + HYST_DEF[ADC_W-1:0]);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) string_blocked <= 1'b0;
        else begin
            if (string_blocked)
                string_blocked <= (adc_val > th_o) ? 1'b0 : 1'b1;
            else
                string_blocked <= (adc_val < th_b) ? 1'b1 : 1'b0;
        end
    end
endmodule

`timescale 1ns / 1ps
//====================================================================
// pressure_calib  力度标定（第 3-4 周）
//   目标：把 FSR 的 0~4095 原始值映射为「手感力度」0~127。
//
//   标定步骤（calib_run 上升沿启动）：
//     1) 零点：未按下时采样 max 噪声 → th_down = zero + DEADBAND
//     2) 满量程：演示「重按」采样 max → raw_max
//     3) 输出 th_up = th_down + DEADBAND（按下阈）
//        力度映射系数 raw_max 存下，供 force_map 使用
//
//   force_map：velocity = ((raw - dead) / (raw_max - dead)) 的 7bit 近似
//             再开平方近似（(x + x/2)/... 粗拟合 γ≈0.5~0.7）
//====================================================================
module pressure_calib #(
    parameter integer ADC_W       = 12,
    parameter integer CLK_FREQ_HZ = 12_288_000,
    parameter integer ACQ_MS      = 200,
    parameter integer DEADBAND    = 80,
    parameter integer HYST        = 100    // 标定后按下阈相对零点的回差（码值）
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire             calib_run,     // 1=启动一轮
    input  wire             sample_clear,
    input  wire [ADC_W-1:0] adc_probe,     // 探针：一般接第 0 键

    output reg              calib_done,
    output reg              th_load,
    output reg  [ADC_W-1:0] th_down,
    output reg  [ADC_W-1:0] th_up,
    output reg  [ADC_W-1:0] raw_max,       // 满量程，给 force_map
    output reg  [1:0]       calib_state    // 0空 1零点 2满程 3完成
);
    localparam integer ACQ_CNT = (CLK_FREQ_HZ / 1000) * ACQ_MS;
    localparam [1:0] S_IDLE=0, S_ZERO=1, S_FULL=2, S_DONE=3;

    reg [31:0] tcnt;
    reg [ADC_W-1:0] zero_peak;
    reg [ADC_W-1:0] full_peak;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            calib_state <= S_IDLE;
            calib_done  <= 1'b0;
            th_load     <= 1'b0;
            th_down     <= 12'd80;     // 未标定时死区下限（同时作 force_map 的 dead）
            th_up       <= 12'd180;    // 未标定按下阈（约 0.22V（PGA=1/VREF=2.5V，校零后增量）），轻按即可响
            raw_max     <= 12'd3000;   // 约 3.66V 对应此默认力度尺度，须按实际可用输入标定
            tcnt        <= 0;
            zero_peak   <= 0;
            full_peak   <= 0;
        end else begin
            case (calib_state)
                S_IDLE: begin
                    calib_done <= 1'b0;
                    if (sample_clear) begin
                        tcnt <= 0; zero_peak <= 0; full_peak <= 0;
                    end else if (calib_run) begin
                        calib_state <= S_ZERO;
                        tcnt <= 0;
                        zero_peak <= 0;
                    end
                end
                S_ZERO: begin
                    // 未按下：取最大噪声
                    if (adc_probe > zero_peak) zero_peak <= adc_probe;
                    if (tcnt >= ACQ_CNT[31:0]) begin
                        th_down <= zero_peak + DEADBAND[ADC_W-1:0];
                        th_up   <= zero_peak + DEADBAND[ADC_W-1:0] + HYST[ADC_W-1:0];
                        tcnt    <= 0;
                        full_peak <= 0;
                        calib_state <= S_FULL;
                    end else tcnt <= tcnt + 32'd1;
                end
                S_FULL: begin
                    // 重按：取峰值
                    if (adc_probe > full_peak) full_peak <= adc_probe;
                    if (tcnt >= ACQ_CNT[31:0]) begin
                        if (full_peak > th_down)
                            raw_max <= full_peak;
                        else
                            raw_max <= th_down + 12'd500;
                        th_load     <= 1'b1;
                        calib_done  <= 1'b1;
                        calib_state <= S_DONE;
                    end else tcnt <= tcnt + 32'd1;
                end
                S_DONE: begin
                    if (sample_clear) calib_state <= S_IDLE;
                end
            endcase
        end
    end
endmodule

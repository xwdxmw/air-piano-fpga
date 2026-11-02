`timescale 1ns / 1ps
//====================================================================
// optical_calib  遮挡标定（第 3-4 周）
//   目标：环境光变化时，自动/手动得到稳定「挡住 / 打开」阈值。
//
//   流程（calib_run=1 进入校准）：
//     1) 空档采样：所有弦未遮挡，记录 adc 最大值(最亮)与均值
//     2) 遮挡采样：演示拨弦/遮挡，记录 adc 最小值(最暗)
//     3) 输出：
//          th_open    = min + (max-min)*OPEN_NUM/OPEN_DEN   （约 60% 亮处）
//          th_blocked = min + (max-min)*BLK_NUM/BLK_DEN     （约 40% 亮处）
//     4) th_load=1 写入 optical_quantize
//
//   也可纯上电自动：复位后自动采 100ms 基线，再用相对阈值。
//====================================================================
module optical_calib #(
    parameter integer ADC_W      = 12,
    parameter integer WIDTH      = 8,
    parameter integer CLK_FREQ_HZ= 12_288_000,
    parameter integer ACQ_MS     = 100,     // 每步采集时长
    parameter integer HYST       = 120
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    calib_run,     // 1=进入标定
    input  wire                    sample_clear,  // 1 拍：重新开始本轮
    input  wire [ADC_W*WIDTH-1:0]  adc_bundled,   // 8 路 ADC 拼接

    output reg                     calib_done,
    output reg                     th_load,
    output reg  [ADC_W-1:0]        th_blocked,
    output reg  [ADC_W-1:0]        th_open,
    output reg  [1:0]              calib_state,   // 0空闲 1采亮 2采暗 3完成
    output reg  [ADC_W-1:0]        dbg_max,
    output reg  [ADC_W-1:0]        dbg_min
);
    localparam integer ACQ_CNT = (CLK_FREQ_HZ / 1000) * ACQ_MS;
    localparam [1:0] S_IDLE=2'd0, S_BRIGHT=2'd1, S_DARK=2'd2, S_DONE=2'd3;

    reg [31:0] tcnt;
    reg [ADC_W-1:0] acc_max [0:WIDTH-1];
    reg [ADC_W-1:0] acc_min [0:WIDTH-1];

    // 取当前拍 8 路中的最大/最小
    function [ADC_W-1:0] f_max8;
        input [ADC_W*WIDTH-1:0] bus;
        integer k;
        reg [ADC_W-1:0] m;
        begin
            m = bus[ADC_W-1:0];
            for (k = 1; k < WIDTH; k = k + 1)
                if (bus[k*ADC_W +: ADC_W] > m) m = bus[k*ADC_W +: ADC_W];
            f_max8 = m;
        end
    endfunction

    function [ADC_W-1:0] f_min8;
        input [ADC_W*WIDTH-1:0] bus;
        integer k;
        reg [ADC_W-1:0] m;
        begin
            m = bus[ADC_W-1:0];
            for (k = 1; k < WIDTH; k = k + 1)
                if (bus[k*ADC_W +: ADC_W] < m) m = bus[k*ADC_W +: ADC_W];
            f_min8 = m;
        end
    endfunction

    wire [ADC_W-1:0] v_max = f_max8(adc_bundled);
    wire [ADC_W-1:0] v_min = f_min8(adc_bundled);

    reg [ADC_W-1:0] bright_max;  // 亮场最大（未遮挡）
    reg [ADC_W-1:0] dark_min;    // 暗场最小（遮挡）

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            calib_state <= S_IDLE;
            calib_done  <= 1'b0;
            th_load     <= 1'b0;
            th_blocked  <= 12'd2000;
            th_open     <= 12'd2120;
            tcnt        <= 0;
            bright_max  <= 0;
            dark_min    <= {ADC_W{1'b1}};
            dbg_max     <= 0;
            dbg_min     <= 0;
        end else begin
            case (calib_state)
                S_IDLE: begin
                    calib_done <= 1'b0;
                    if (sample_clear) begin
                        tcnt <= 0;
                        bright_max <= 0;
                        dark_min   <= {ADC_W{1'b1}};
                    end else if (calib_run) begin
                        calib_state <= S_BRIGHT;
                        tcnt        <= 0;
                        bright_max  <= 0;
                    end
                end
                S_BRIGHT: begin
                    // 采集「全亮 / 未遮挡」
                    if (v_max > bright_max) bright_max <= v_max;
                    if (tcnt >= ACQ_CNT[31:0]) begin
                        dbg_max     <= bright_max;
                        tcnt        <= 0;
                        dark_min    <= {ADC_W{1'b1}};
                        calib_state <= S_DARK;
                    end else tcnt <= tcnt + 32'd1;
                end
                S_DARK: begin
                    // 采集「被挡最暗」
                    if (v_min < dark_min) dark_min <= v_min;
                    if (tcnt >= ACQ_CNT[31:0]) begin
                        dbg_min <= dark_min;
                        // 阈值：在 亮-暗 区间取 40% / 60%
                        // th_blocked = dark + 0.4*(bright-dark)
                        // th_open    = dark + 0.6*(bright-dark)
                        if (bright_max > dark_min) begin
                            th_blocked <= dark_min + ((bright_max - dark_min) * 12'd2) / 12'd5; // 40%
                            th_open    <= dark_min + ((bright_max - dark_min) * 12'd3) / 12'd5; // 60%
                        end else begin
                            th_blocked <= 12'd2000;
                            th_open    <= 12'd2000 + HYST[11:0];
                        end
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

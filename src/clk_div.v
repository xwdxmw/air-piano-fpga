//====================================================================
// clk_div.v —— 分频模块 v2（队员 B · 契约 mixer_interface.md §4）
//
// 功能：由 PLL 主时钟（MCLK = 12.288 MHz）分频产生：
//   - bclk      ：I2S 位时钟 3.072 MHz（= MCLK/4 = 48k×64）
//   - ws        ：I2S 帧时钟 48 kHz（WS 低电平 = 左声道，契约 §4.2）
//   - sample_tick：48 kHz 采样脉冲（1 拍高电平），喂引擎/混音器，
//                 与 I2S 同源，避免跨时钟（契约 §4.1）
//
// 参数均为频率分频比：
//   BCK_DIV  = MCLK/BCLK = 4（须为偶数，50% 占空比）
//   LRCK_DIV = BCLK/WS   = 64（左右各 32 位）
//
// WS 在 BCLK 下降沿翻转（贴近标准 I2S），复位后 WS=0（左声道）。
// sample_tick 在 WS 下降沿（左声道开始）后一拍输出。
//====================================================================

module clk_div #(
    parameter BCK_DIV  = 4,    // 12.288M / 3.072M = 4
    parameter LRCK_DIV = 64    // 3.072M / 48k = 64
)(
    input  wire clk,           // PLL 输出主时钟（12.288 MHz）
    input  wire rst_n,         // 低有效复位
    output reg  bclk,          // I2S 位时钟 3.072 MHz
    output reg  ws,            // I2S 帧时钟 48 kHz（低=左声道）
    output reg  sample_tick    // 48 kHz 采样脉冲（喂引擎与混音器）
);

    //--------------------------------------------------------------
    // 1. BCLK 分频：每 BCK_DIV/2 个 clk 翻转一次
    //--------------------------------------------------------------
    localparam BCK_CNT_MAX = BCK_DIV / 2 - 1;
    reg [$clog2(BCK_DIV)-1:0] bclk_cnt;
    wire bclk_tick;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            bclk_cnt <= 0;
        else if (bclk_cnt == BCK_CNT_MAX)
            bclk_cnt <= 0;
        else
            bclk_cnt <= bclk_cnt + 1'b1;
    end
    assign bclk_tick = (bclk_cnt == BCK_CNT_MAX);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            bclk <= 1'b0;
        else if (bclk_tick)
            bclk <= ~bclk;
    end

    //--------------------------------------------------------------
    // 2. WS 分频：在 BCLK 下降沿计数，每 LRCK_DIV/2 个 BCLK 翻转
    //    复位后 WS=0（左声道）；低=左、高=右（契约 §4.2）
    //--------------------------------------------------------------
    reg bclk_d;
    wire bclk_fall;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) bclk_d <= 1'b0;
        else        bclk_d <= bclk;
    end
    assign bclk_fall = bclk_d & ~bclk;

    localparam LRCK_CNT_MAX = LRCK_DIV / 2 - 1;
    reg [$clog2(LRCK_DIV)-1:0] ws_cnt;
    wire ws_tick;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            ws_cnt <= 0;
        else if (bclk_fall) begin
            if (ws_cnt == LRCK_CNT_MAX)
                ws_cnt <= 0;
            else
                ws_cnt <= ws_cnt + 1'b1;
        end
    end
    assign ws_tick = (ws_cnt == LRCK_CNT_MAX);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            ws <= 1'b0;                    // 复位后 = 左声道
        else if (bclk_fall && ws_tick)
            ws <= ~ws;
    end

    //--------------------------------------------------------------
    // 3. sample_tick：WS 下降沿（左声道开始）后一拍输出
    //--------------------------------------------------------------
    reg ws_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) ws_d <= 1'b0;
        else        ws_d <= ws;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            sample_tick <= 1'b0;
        else
            sample_tick <= ~ws & ws_d;     // WS 下降沿打一拍后的脉冲
    end

endmodule

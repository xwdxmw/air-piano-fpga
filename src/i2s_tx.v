//====================================================================
// i2s_tx.v —— I2S 发送模块 v2（队员 B · 契约 mixer_interface.md §4.2）
//
// 时序（标准 I2S）：
//   - WS 低电平 = 左声道，高电平 = 右声道（契约 §4.2，低=左）
//   - MSB first；数据比 WS 跳变晚约 1 个 BCLK（标准 I2S，非左/右对齐）
//   - 数据在 BCLK 下降沿变化，codec 在 BCLK 上升沿采样
//   - 每声道 32 个 BCLK（有效 16bit 样本 + 低位补 0）
//
// 参数：
//   FRAME_WIDTH  = 每声道帧长（BCLK 数），默认 32
//   SAMPLE_WIDTH = 有效样本位宽，默认 16（高位对齐，低位补 0）
//
// 数据装载：WS 边沿（打 1 拍检测）立即装载并输出 MSB，MSB 相对
//   WS 边沿提前约 0.5 BCLK 生效，避开 codec 采样沿竞争；样本由
//   混音器在 sample_tick 同步更新（比 WS 沿晚 1 拍生效），装载读到
//   的是最近一帧稳定样本（固定 1~2 帧流水延迟 ≈ 42 µs，远小于
//   10 ms 演奏延迟指标）。
//====================================================================

module i2s_tx #(
    parameter FRAME_WIDTH  = 32,
    parameter SAMPLE_WIDTH = 16
)(
    input  wire                    clk,            // 系统时钟（12.288 MHz）
    input  wire                    rst_n,          // 低有效复位
    input  wire                    bclk,           // 位时钟（来自 clk_div）
    input  wire                    ws,             // 帧时钟（低=左，来自 clk_div）
    input  wire                    sample_tick,    // 采样脉冲（引擎侧同步用，本模块装载自同步）
    input  wire [SAMPLE_WIDTH-1:0] left_data,      // 左声道样本（有符号 PCM）
    input  wire [SAMPLE_WIDTH-1:0] right_data,     // 右声道样本（有符号 PCM）
    output reg                     dacdat          // I2S 串行数据 → codec DACDAT
);

    //--------------------------------------------------------------
    // 打拍：检测 BCLK 边沿与 WS 边沿
    //   - bclk_fall2：BCLK 下降沿（打 2 拍）→ 数据移位节拍
    //   - ws_edge1 ：WS 边沿（打 1 拍）→ 装载节拍
    //   注：WS 在 clk_div 中于 BCLK 下降沿翻转，故 WS 边沿与 BCLK
    //   上升沿几乎同拍。若用打 2 拍检测 WS 边沿，MSB 生效时刻会恰
    //   落在 codec 采样沿（WS 边沿后第 2 个 BCLK 上升沿）上造成
    //   亚稳态竞争（数据左移 1 位）。装载提前 1 拍：MSB 在采样沿前
    //   约 0.5 BCLK 生效，建立时间充足。
    //--------------------------------------------------------------
    reg bclk_d, bclk_dd;
    reg ws_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bclk_d  <= 1'b0;
            bclk_dd <= 1'b0;
            ws_d    <= 1'b0;
        end
        else begin
            bclk_d  <= bclk;
            bclk_dd <= bclk_d;
            ws_d    <= ws;
        end
    end

    wire bclk_fall2 = bclk_dd & ~bclk_d;   // BCLK 下降沿（延迟 2 拍）
    wire ws_edge1   = ws ^ ws_d;           // WS 边沿（延迟 1 拍，任意方向）

    //--------------------------------------------------------------
    // 装载 + 移位发送（标准 I2S，MSB 在 WS 边沿后约 1 BCLK 有效）：
    //   WS 边沿检测（打 2 拍）→ 立即装载并输出 MSB
    //   （WS 低=左声道装载 left_data，高=右声道装载 right_data）
    //   之后每个 BCLK 下降沿输出一位 MSB-first，低位补 0
    //
    // 时序说明：WS 边沿后 2 拍（≈0.5 BCLK）装载并输出 MSB，codec 在
    //   WS 边沿后第 2 个 BCLK 上升沿（≈1.5 BCLK）采样 MSB，建立时间
    //   充足；装载读到的样本是最近一帧已稳定的值（固定 1~2 帧流水
    //   延迟 ≈ 42 µs，远小于 10 ms 演奏延迟指标）。
    //--------------------------------------------------------------
    reg [FRAME_WIDTH-1:0] shift_reg;
    reg hold_msb;                    // 装载后跳过 1 次移位，延长 MSB 保持

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dacdat    <= 1'b0;
            shift_reg <= {FRAME_WIDTH{1'b0}};
            hold_msb  <= 1'b0;
        end
        else if (ws_edge1) begin
            // WS 低 = 左声道（ws_d 已是 WS 新值）；立即装载并直接输出 MSB
            if (!ws_d) begin
                shift_reg <= {left_data, {(FRAME_WIDTH-SAMPLE_WIDTH){1'b0}}};
                dacdat    <= left_data[SAMPLE_WIDTH-1];
            end
            else begin
                shift_reg <= {right_data, {(FRAME_WIDTH-SAMPLE_WIDTH){1'b0}}};
                dacdat    <= right_data[SAMPLE_WIDTH-1];
            end
            hold_msb <= 1'b1;        // 跳过下一次移位：MSB 保持 2 个 BCLK，
                                     // 确保 codec 在 WS 边沿后 1.5 BCLK 采样
        end
        else if (bclk_fall2) begin
            if (hold_msb)
                hold_msb <= 1'b0;    // 跳过 1 次移位（MSB 保持）
            else begin
                dacdat    <= shift_reg[FRAME_WIDTH-1];           // 输出最高位
                shift_reg <= {shift_reg[FRAME_WIDTH-2:0], 1'b0}; // 左移
            end
        end
    end

endmodule

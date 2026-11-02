//====================================================================
// pt8211_tx.v —— PT8211 专用 I2S 发送器
//   每声道 16 bit，MSB first；BCLK = clk/8；WS = clk/256
//   音频时钟 12.264MHz → BCLK≈1.533MHz，WS≈47.9kHz
//   替换旧 clk_div + i2s_tx 组合
//====================================================================
module pt8211_tx #(
    parameter LEFT_WS_LEVEL = 1'b0   // 低=左声道（按数据手册确认，反了改这里）
)(
    input  wire        clk,          // 音频时钟 12.264MHz
    input  wire        rst_n,
    input  wire [15:0] left_data,
    input  wire [15:0] right_data,
    output wire        bclk,
    output wire        ws,
    output reg         dacdat,
    output wire        sample_tick
);
    reg [7:0] phase;
    reg [15:0] shift_reg;
    reg [15:0] right_hold;

    assign bclk = phase[2];
    assign ws   = phase[7] ^ LEFT_WS_LEVEL;
    assign sample_tick = (phase == 8'hFF);   // 每256拍一个采样脉冲

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase      <= 8'd0;
            shift_reg  <= 16'd0;
            right_hold <= 16'd0;
            dacdat     <= 1'b0;
        end else begin
            phase <= phase + 8'd1;
            // phase低3位=111时，本拍后BCLK下降沿
            if (phase[2:0] == 3'b111) begin
                if (phase == 8'hFF) begin
                    // 新立体声帧：锁存两声道，开始左声道
                    right_hold <= right_data;
                    dacdat     <= left_data[15];
                    shift_reg  <= {left_data[14:0], 1'b0};
                end else if (phase == 8'h7F) begin
                    // 左声道16位发完，切右声道
                    dacdat    <= right_hold[15];
                    shift_reg <= {right_hold[14:0], 1'b0};
                end else begin
                    dacdat    <= shift_reg[15];
                    shift_reg <= {shift_reg[14:0], 1'b0};
                end
            end
        end
    end
endmodule

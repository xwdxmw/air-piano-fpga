`timescale 1ns / 1ps
//====================================================================
// delay_fx  延迟/回声效果器（BSRAM 延迟线 + 0.5 反馈）
//
//   原理：y[n] = x[n] + 0.5 · y[n-D]
//     写回延迟线的信号含反馈，所以听感上是一串逐渐变轻的回声；
//     输出取"干声 + 一半湿声"，不改变原音色，只是加一层空间感。
//
//   资源：DEPTH×16bit 的 BSRAM（8192 深 ≈ 8 块 18Kb），
//         运算只有加法 + 算术右移，【不占 DSP】。
//
//   时钟：音频域 12.264MHz，每 sample_tick（47.9kHz）推进一个采样点。
//         读/写用 2 拍小状态机完成（BRAM 同步读 → 下一拍写）。
//====================================================================
module delay_fx #(
    parameter integer DEPTH = 8192,        // 延迟线深度（2 的幂）
    parameter integer AW    = 13,          // 地址位宽 = log2(DEPTH)
    parameter integer DLY   = 7168         // 延迟点数：7168 / 47.9kHz ≈ 150ms
)(
    input  wire               clk,
    input  wire               rst_n,
    input  wire               sample_tick,
    input  wire signed [15:0] din,
    output reg  signed [15:0] dout
);

    // 延迟线（综合成 BSRAM）
    reg signed [15:0] mem [0:DEPTH-1];
    reg [AW-1:0]      wp;
    reg [AW-1:0]      rd_addr;

    reg [AW:0] written;
    reg history_valid;
    wire signed [15:0] wet = history_valid ? rd_q : 16'sd0;
    reg [1:0]         st;
    reg signed [15:0] rd_q;

    wire [AW-1:0] rd_addr_w = wp - DLY[AW-1:0];

    // 18bit → 16bit 饱和（回声音量叠加后防溢出）
    function signed [15:0] sat16;
        input signed [17:0] v;
        begin
            if      (v >  18'sd32767) sat16 =  16'sd32767;
            else if (v < -18'sd32768) sat16 = -16'sd32768;
            else                      sat16 = v[15:0];
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            written <= 0;history_valid <= 0;
            wp      <= {AW{1'b0}};
            rd_addr <= {AW{1'b0}};
            st      <= 2'd0;
            dout    <= 16'sd0;
            rd_q    <= 16'sd0;
        end else begin
            case (st)
            2'd0: if (sample_tick) begin
                      history_valid <= (written >= DLY);
                      rd_addr <= rd_addr_w;
                      rd_q    <= mem[rd_addr_w];    // 同步读（BSRAM 输出寄存器）
                      st      <= 2'd1;
                  end
            2'd1: begin
                      // 写回：干声 + 0.5 × 上次回声 → 多级重复
                      mem[wp] <= sat16(din + (wet >>> 1));
                      // 输出：干声 + 0.5 × 回声
                      dout    <= sat16(din + (wet >>> 1));
                      if(written < DLY) written <= written + 1'b1;
                      wp      <= wp + 1'b1;
                      st      <= 2'd2;
                  end
            2'd2: st <= 2'd0;
            default: st <= 2'd0;
            endcase
        end
    end

endmodule

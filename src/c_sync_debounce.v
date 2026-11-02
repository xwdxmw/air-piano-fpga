`timescale 1ns / 1ps
//====================================================================
// c_sync_debounce  异步 GPIO 同步 + 多数表决消抖
//   用途：红外对射数字输出、电容触摸等开关量进 FPGA 前的统一调理。
//   两级触发器同步后，用连续 N 拍一致才翻转的多数表决消除抖动。
//   板卡：Tang Mega 138K Pro，clk=50MHz 时，DB_CNT=2000 拍 = 2000/50MHz = 40us（约 40 微秒）。
//====================================================================
module c_sync_debounce #(
    parameter integer DB_CNT = 2000   // 消抖计数阈值（时钟周期）
)(
    input  wire clk,
    input  wire rst_n,
    input  wire din,        // 异步原始输入
    output reg  dout,       // 消抖后的干净电平
    output wire rise,       // 1 拍：上升沿
    output wire fall        // 1 拍：下降沿
);
    // ---- 两级同步 ----
    reg [2:0] sync;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) sync <= 3'b000;
        else        sync <= {sync[1:0], din};
    end
    wire din_s = sync[2];

    // ---- 计数式消抖：新电平连续保持 DB_CNT 拍才接受 ----
    reg             din_q;
    localparam integer CNT_W = (DB_CNT<2)?1:$clog2(DB_CNT+1);
    reg [CNT_W-1:0] cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dout  <= 1'b0;
            din_q <= 1'b0;
            cnt   <= {CNT_W{1'b0}};
        end else begin
            din_q <= din_s;
            if (din_s == dout) begin
                cnt <= {CNT_W{1'b0}};
            end else if (cnt >= DB_CNT-1) begin
                dout <= din_s;
                cnt  <= {CNT_W{1'b0}};
            end else begin
                cnt <= cnt + 1'b1;
            end
        end
    end

    reg dout_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) dout_d <= 1'b0;
        else        dout_d <= dout;
    end
    assign rise =  dout & ~dout_d;
    assign fall = ~dout &  dout_d;
endmodule

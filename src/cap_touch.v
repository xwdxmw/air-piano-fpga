`timescale 1ns / 1ps
//====================================================================
// cap_touch  电容点按：钢琴/竖琴模式切换
//   上电前 PWR_MASK_MS 忽略 touch（TTP223 上电抖动屏蔽窗口）
//   只认“按下上升沿”，适配 TTP223 默认的点动模式（momentary：按住输出高、
//   松手回到低）：一次点按只产生一个上升沿 → mode 翻转一次；松手是下降沿，
//   不翻转。由此：
//     · 点动模式快速点按（按下后立刻松开）：翻转一次，不再像旧版“电平触发”
//       那样因松手被当成第二次操作；
//     · 长按（手指一直按住超过 COOLDOWN_MS）：只在按下瞬间翻转一次，之后
//       不会周期性反复翻转；
//     · COOLDOWN_MS 冷却窗口内的连点（抖动/误触）不重复触发。
//   切换时同时发 all_notes_off（收掉切换前正在响的全部音符）。
//
//   注：若把 TTP223 模块的 A 焊盘短接、改成自锁(toggle)模式（摸一下保持高、
//       再摸一下回低），则“每次触摸”可能是上升沿也可能是下降沿，需要把
//       触发条件从 press_rise 改为“任意沿”（press_rise | fall）。市售模块
//       默认 A 点悬空 = 点动，本模块按点动设计。
//====================================================================
module cap_touch #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer COOLDOWN_MS = 300,
    parameter integer PWR_MASK_MS = 500
)(
    input  wire clk,
    input  wire rst_n,
    input  wire touch,           // 已消抖的干净电平（来自 c_sync_debounce.dout）
    output reg  mode,
    output reg  mode_changed,
    output reg  all_notes_off
);
    localparam integer COOLDOWN_CNT = (CLK_FREQ_HZ / 1000) * COOLDOWN_MS;
    localparam integer PWR_MASK_CNT = (CLK_FREQ_HZ / 1000) * PWR_MASK_MS;

    reg [31:0] cd_cnt, pwr_cnt;
    reg        cooling, pwr_done;
    reg        touch_d;                   // 上一拍 touch，用于做上升沿检测

    // 按下上升沿：本拍为高、上一拍为低（只在按下瞬间出现 1 拍）
    wire press_rise = touch & ~touch_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mode <= 0; mode_changed <= 0; all_notes_off <= 0;
            cd_cnt <= 0; cooling <= 0;
            pwr_cnt <= 0; pwr_done <= 0;
            touch_d <= 0;
        end else begin
            mode_changed <= 1'b0;
            all_notes_off<= 1'b0;
            // 无条件跟随：上电屏蔽窗口内也让 touch_d 跟上 touch，
            // 避免窗口结束那一刻“手指一直按着”被误判成新的上升沿。
            touch_d <= touch;

            // 上电屏蔽窗
            if (!pwr_done) begin
                if (pwr_cnt >= PWR_MASK_CNT[31:0]) pwr_done <= 1'b1;
                else pwr_cnt <= pwr_cnt + 32'd1;
            end

            if (cooling) begin
                // 冷却中：屏蔽一切触发，只数时间
                if (cd_cnt >= COOLDOWN_CNT[31:0]) cooling <= 1'b0;
                else cd_cnt <= cd_cnt + 32'd1;
            end else if (press_rise & pwr_done) begin
                // 同时满足：① 上电屏蔽已过 ② 不在冷却 ③ 出现按下上升沿
                // 才翻转一次，且翻转后立即进入冷却
                mode <= ~mode;
                mode_changed <= 1'b1;
                all_notes_off<= 1'b1;
                cooling <= 1'b1;
                cd_cnt  <= 32'd0;
            end
        end
    end
endmodule

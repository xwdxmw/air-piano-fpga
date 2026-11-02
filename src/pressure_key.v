`timescale 1ns / 1ps
//====================================================================
// pressure_key  单键 FSR：按下判定 + 力度 force_map + aftertouch
//   P1: aftertouch 低通用 ms 级使能（AT_EN_MS），不每拍跑
//   P2: velocity 走 force_map 幂曲线；NOTE 参数删除（由 pressure_detect 传）
//====================================================================
module pressure_key #(
    parameter integer ADC_W       = 12,
    parameter integer THRESHOLD   = 12'd180,    // 约 0.22V（PGA=1/VREF=2.5V，校零后增量） 轻按即触发（C10/FSR 分压）
    parameter integer HYST        = 12'd70,     // 松开回差（码值），防临界点抖动
    parameter integer ATK_WIN_US  = 2700,       // 力度峰值窗口2.7ms；首音走press_now，不等待此窗口
    parameter integer AT_EN_MS    = 1,          // aftertouch 更新周期
    parameter integer CLK_FREQ_HZ = 50_000_000  // 实际跑 50MHz（上层也会显式传入）
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire [ADC_W-1:0] adc_val,
    input  wire [ADC_W-1:0] th_down,
    input  wire [ADC_W-1:0] th_up,
    input  wire             th_load,
    input  wire [ADC_W-1:0] raw_max,      // from pressure_calib
    input  wire [ADC_W-1:0] calib_dead,   // usually th_down

    output reg              key_on,
    output wire             rel_pulse,
    output wire             press_now,       // 【新增】立即起音：触发后约 8 拍发 NOTE_ON
    output wire             vel_upd,         // 【新增】力度修正：峰值窗口结束后补一次
    output wire             press_confirm,   // 兼容保留（窗口结束脉冲，不再用于发音）
    output reg  [6:0]       velocity,
    output reg  [6:0]       aftertouch
);
    localparam integer ATK_CNT = (CLK_FREQ_HZ / 1_000_000) * ATK_WIN_US;
    localparam integer AT_CNT  = (CLK_FREQ_HZ / 1000) * AT_EN_MS;
    localparam integer AKW=ATK_CNT>0?$clog2(ATK_CNT+1):1;
    localparam integer ATW=AT_CNT>0?$clog2(AT_CNT+1):1;

    wire [ADC_W-1:0] th_hi = th_load ? th_up   : THRESHOLD[ADC_W-1:0];
    wire [ADC_W-1:0] th_lo = th_load ? th_down : (THRESHOLD[ADC_W-1:0] - HYST[ADC_W-1:0]);

    reg key_on_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_on   <= 1'b0;
            key_on_d <= 1'b0;
        end else begin
            key_on_d <= key_on;
            if (key_on) key_on <= (adc_val < th_lo) ? 1'b0 : 1'b1;
            else        key_on <= (adc_val > th_hi) ? 1'b1 : 1'b0;
        end
    end
    // trigger：按压过阈值瞬间，内部用于启动力度窗口（不直接发音符，因为
    //   首音走press_now；press_confirm仅兼容保留，窗口结束补发力度修正）
    wire trigger      =  key_on & ~key_on_d;
    assign rel_pulse  = ~key_on &  key_on_d;

    // vel_done：力度窗口结束、且 settle 等满 force_map 4 级流水后置 1，
    //   下一拍拉 press_confirm（此时 velocity 已锁定为最终峰值对应力度）。
    reg vel_done;
    assign press_confirm = vel_done;

    // ---- 起振峰值 → force_map 曲线 → velocity ----
    reg [AKW-1:0]   atk_cnt;
    reg [ADC_W-1:0] atk_peak;
    reg             atk_active;
    reg             settling;      // 峰值已锁定，等 force_map 流水线排空
    reg [3:0]       settle_cnt;
    wire [6:0]      vel_mapped;
    // 最小力度保护：轻按若落在 dead 附近、force_map 算出 0，也给一个可闻的 24，
    //   避免“确实按下但力度 0 = 静音”。
    wire [6:0]      vel_for_note = (vel_mapped < 7'd24) ? 7'd24 : vel_mapped;

    force_map #(.ADC_W(ADC_W)) u_fmap (
        .clk(clk), .rst_n(rst_n),
        .raw(atk_peak),
        .dead(calib_dead),
        .raw_max(raw_max),
        .velocity(vel_mapped)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            atk_cnt    <= 32'd0;
            atk_peak   <= 0;
            atk_active <= 1'b0;
            settling   <= 1'b0;
            settle_cnt <= 4'd0;
            velocity   <= 7'd0;
            vel_done   <= 1'b0;
            now_cnt    <= 4'd0;
            now_pend   <= 1'b0;
            press_now_r<= 1'b0;
            vel_upd_r  <= 1'b0;
        end else begin
            press_now_r <= 1'b0;
            vel_upd_r   <= 1'b0;

            // ---- ① 触发：开窗，并预约一次"立即起音" ----
            if (trigger) begin
                atk_active <= 1'b1;
                atk_cnt    <= 32'd0;
                atk_peak   <= adc_val;
                settling   <= 1'b0;
                settle_cnt <= 4'd0;
                vel_done   <= 1'b0;
                now_pend   <= 1'b1;
                now_cnt    <= 4'd0;
            end else if (now_pend) begin
                // 等 force_map 的 4 级流水算出"初判力度"（约 160ns），立刻发 NOTE_ON
                if (now_cnt >= 4'd7) begin
                    now_pend    <= 1'b0;
                    velocity    <= vel_for_note;
                    press_now_r <= 1'b1;
                end else begin
                    now_cnt <= now_cnt + 4'd1;
                end
            end

            // ---- ② 峰值窗口（2.7ms）：结束后补一次力度修正 ----
            if (atk_active && !trigger) begin
                if (adc_val > atk_peak) atk_peak <= adc_val;
                if (atk_cnt >= ATK_CNT[31:0]) begin
                    atk_active <= 1'b0;
                    settling   <= 1'b1;
                    settle_cnt <= 4'd0;
                end else begin
                    atk_cnt <= atk_cnt + 32'd1;
                end
            end else if (settling) begin
                if (settle_cnt >= 4'd7) begin
                    settling <= 1'b0;
                    velocity <= vel_for_note;        // 峰值对应力度
                    vel_done <= 1'b1;                // 兼容输出
                    if (key_on) vel_upd_r <= 1'b1;   // 仍按着才修正（已松开就不发）
                end else begin
                    settle_cnt <= settle_cnt + 4'd1;
                end
            end else if (vel_done) begin
                vel_done <= 1'b0;
            end
        end
    end

    reg [3:0] now_cnt;
    reg       now_pend;
    reg       press_now_r, vel_upd_r;
    assign press_now = press_now_r;
    assign vel_upd   = vel_upd_r;

    // ---- aftertouch 低通（P1：ms 级使能）----
    reg [ATW-1:0]   at_div;
    reg [ADC_W-1:0] at_lpf;
    wire            at_tick = (at_div >= AT_CNT[31:0]);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            at_div     <= 32'd0;
            at_lpf     <= 0;
            aftertouch <= 7'd0;
        end else if (key_on) begin
            if (at_tick) begin
                at_div <= 32'd0;
                if (adc_val >= at_lpf)
                    at_lpf <= at_lpf + ((adc_val - at_lpf) >> 4);
                else
                    at_lpf <= at_lpf - ((at_lpf - adc_val) >> 4);
                aftertouch <= at_lpf[ADC_W-1:ADC_W-7];
            end else begin
                at_div <= at_div + 32'd1;
            end
        end else begin
            at_div     <= 32'd0;
            at_lpf     <= 0;
            aftertouch <= 7'd0;
        end
    end
endmodule

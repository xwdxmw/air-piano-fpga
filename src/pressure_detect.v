`timescale 1ns / 1ps
//====================================================================
// pressure_detect  8 键钢琴（低延迟版）
//
//   2026-10-24 改动：NOTE_ON 不再等 2.7ms 力度窗口，改成
//     · pressure_key 触发后约 8 拍就发 press_now  -> NOTE_ON 立即出去
//     · 2.7ms 窗口结束后再发 velupd（力度修正）-> 引擎更新包络峰值
//   事件优先级：press > release > velupd（velupd 晚几拍无所谓）
//====================================================================
module pressure_detect #(
    parameter integer WIDTH = 8,
    parameter integer ADC_W = 12,
    parameter integer CLK_FREQ_HZ = 50_000_000   // 必须与实际时钟一致，否则力度/触后窗口时长错误
)(
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire [ADC_W*WIDTH-1:0] adc,
    input  wire [ADC_W-1:0]       th_down,
    input  wire [ADC_W-1:0]       th_up,
    input  wire                   th_load,
    input  wire [ADC_W-1:0]       raw_max,
    input  wire [ADC_W-1:0]       calib_dead,

    output wire [WIDTH-1:0]       key_on,
    // 立即起音（每拍最多 1 条）
    output reg                    press_valid,
    output reg  [6:0]             press_num,
    output reg  [6:0]             press_vel,
    // 力度修正（每拍最多 1 条）
    output reg                    velupd_valid,
    output reg  [6:0]             velupd_num,
    output reg  [6:0]             velupd_vel,
    // 松开
    output reg                    rel_valid,
    output reg  [6:0]             rel_num,
    output reg  [6:0]             aftertouch
);
    reg [6:0] note_of [0:WIDTH-1];
    integer i;
    initial begin
        note_of[0]=7'd60; note_of[1]=7'd62; note_of[2]=7'd64; note_of[3]=7'd65;
        note_of[4]=7'd67; note_of[5]=7'd69; note_of[6]=7'd71; note_of[7]=7'd72;
    end

    wire [WIDTH-1:0] press_now_v, vel_upd_v, rel_pulse;
    wire [6:0] vel [0:WIDTH-1];
    wire [6:0] at  [0:WIDTH-1];

    genvar g;
    generate
        for (g = 0; g < WIDTH; g = g + 1) begin : g_key
            pressure_key #(.ADC_W(ADC_W), .CLK_FREQ_HZ(CLK_FREQ_HZ)) u_key (
                .clk(clk), .rst_n(rst_n),
                .adc_val  (adc[g*ADC_W +: ADC_W]),
                .th_down  (th_down),
                .th_up    (th_up),
                .th_load  (th_load),
                .raw_max  (raw_max),
                .calib_dead(calib_dead),
                .key_on   (key_on[g]),
                .press_now(press_now_v[g]),
                .vel_upd  (vel_upd_v[g]),
                .press_confirm(),
                .rel_pulse(rel_pulse[g]),
                .velocity (vel[g]),
                .aftertouch(at[g])
            );
        end
    endgenerate

    // ---- 三个 pending 位图：起音 / 松开 / 力度修正 ----
    reg [WIDTH-1:0] press_pend, rel_pend, vu_pend;
    reg [6:0] vel_q  [0:WIDTH-1];
    reg [6:0] vu_vel [0:WIDTH-1];

    function [3:0] f_first1;
        input [WIDTH-1:0] m;
        integer k;
        begin
            f_first1 = 4'd0;
            for (k = WIDTH-1; k >= 0; k = k - 1)
                if (m[k]) f_first1 = k[3:0];
        end
    endfunction

    wire [3:0] p_idx = f_first1(press_pend);
    wire [3:0] r_idx = f_first1(rel_pend);
    wire [3:0] u_idx = f_first1(vu_pend);
    wire p_busy = |press_pend;
    wire r_busy = |rel_pend;
    wire u_busy = |vu_pend;
    wire emit_u = u_busy && !p_busy && !r_busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            press_pend   <= 0;
            rel_pend     <= 0;
            vu_pend      <= 0;
            press_valid  <= 0;
            press_num    <= 0;
            press_vel    <= 0;
            velupd_valid <= 0;
            velupd_num   <= 0;
            velupd_vel   <= 0;
            rel_valid    <= 0;
            rel_num      <= 0;
            aftertouch   <= 0;
            for (i = 0; i < WIDTH; i = i + 1) begin
                vel_q[i]  <= 0;
                vu_vel[i] <= 0;
            end
        end else begin
            // 入队 / 出队
            //   ★ 审阅报告 #1：rel 只有在"本拍真的发出去了"（!p_busy）才出队，
            //     否则起音与松键同拍相撞时 NOTE_OFF 被清掉 → 卡音
            press_pend <= (press_pend & ~(p_busy ? (1 << p_idx) : 0)) | press_now_v;
            rel_pend   <= (rel_pend   & ~((r_busy && !p_busy) ? (1 << r_idx) : 0)) | rel_pulse;
            vu_pend    <= (vu_pend    & ~(emit_u ? (1 << u_idx) : 0)) | vel_upd_v;

            // 锁存各自的力度
            if (|press_now_v) begin
                for (i = 0; i < WIDTH; i = i + 1)
                    if (press_now_v[i]) vel_q[i] <= vel[i];
            end
            if (|vel_upd_v) begin
                for (i = 0; i < WIDTH; i = i + 1)
                    if (vel_upd_v[i]) vu_vel[i] <= vel[i];
            end

            // 输出仲裁：press > release > velupd
            press_valid  <= p_busy;
            rel_valid    <= !p_busy && r_busy;
            velupd_valid <= emit_u;

            if (p_busy) begin
                press_num <= note_of[p_idx[2:0]];
                press_vel <= vel_q[p_idx[2:0]];
            end
            if (!p_busy && r_busy) begin
                rel_num <= note_of[r_idx[2:0]];
            end
            if (emit_u) begin
                velupd_num <= note_of[u_idx[2:0]];
                velupd_vel <= vu_vel[u_idx[2:0]];
            end

            // aftertouch：任一按住键的压力
            aftertouch <= 7'd0;
            for (i = 0; i < WIDTH; i = i + 1)
                if (key_on[i]) aftertouch <= at[i];
        end
    end
endmodule

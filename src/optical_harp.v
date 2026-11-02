`timescale 1ns / 1ps
//====================================================================
// optical_harp  光电竖琴 · 拨弦逻辑检测（时序优化版）
//
// 改动（vs 旧版）：
//   1. 多弦同拍：进 pending 位图，逐拍各发一次（不再只取最高编号）
//   2. 干掉32位除法器：力度映射改 乘法+移位（speed*156 >> 20）
//   3. 力度计算加一级流水线：dt寄存一拍，切断 time_cnt→event_vel 长路径
//
//   拨弦 = 遮挡上升沿；每弦不应期
//   力度 = 扫弦时间差映射 / 默认值
//   板卡 Tang Mega 138K Pro，CLK_FREQ_HZ 由上层 c_interact_top 传入（实际 50_000_000）
//====================================================================
module optical_harp #(
    parameter integer WIDTH            = 8,
    parameter integer CLK_FREQ_HZ      = 50_000_000, // 实际跑 50MHz；力度系数随之自适应
    parameter integer REFRAC_MS        = 30,
    parameter integer STRUM_WINDOW_MS  = 60,
    parameter [6:0]   DEFAULT_VELOCITY = 7'd90
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire [WIDTH-1:0] string_blocked,

    output reg              event_valid,   // 1 拍
    output reg              event_on,      // 竖琴固定 1
    output reg  [6:0]       event_num,
    output reg  [6:0]       event_vel,

    output reg  [1:0]       strum_dir,
    output reg              strum_valid,
    output wire [WIDTH-1:0] pluck_pulse
);
    localparam integer REFRAC_CNT = (CLK_FREQ_HZ / 1000) * REFRAC_MS;
    localparam integer STRUM_CNT  = (CLK_FREQ_HZ / 1000) * STRUM_WINDOW_MS;

    // ---- 音高：C4 D4 E4 F4 G4 A4 B4 C5 ----
    reg [6:0] note_of [0:WIDTH-1];
    integer i;
    initial begin
        note_of[0]=7'd60; note_of[1]=7'd62; note_of[2]=7'd64; note_of[3]=7'd65;
        note_of[4]=7'd67; note_of[5]=7'd69; note_of[6]=7'd71; note_of[7]=7'd72;
    end

    // ---- 上升沿 = 拨弦 ----
    reg  [WIDTH-1:0] prev;
    wire [WIDTH-1:0] rise = string_blocked & ~prev;

    // ---- 每弦不应期 ----
    reg  [31:0]      refrac_cnt [0:WIDTH-1];
    reg  [WIDTH-1:0] refrac_busy;
    wire [WIDTH-1:0] pluck;

    genvar g;
    generate
        for (g = 0; g < WIDTH; g = g + 1) begin : g_str
            assign pluck[g] = rise[g] & ~refrac_busy[g];
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    refrac_busy[g] <= 1'b0;
                    refrac_cnt[g]  <= 32'd0;
                end else if (pluck[g]) begin
                    refrac_busy[g] <= 1'b1;
                    refrac_cnt[g]  <= 32'd0;
                end else if (refrac_busy[g]) begin
                    if (refrac_cnt[g] >= REFRAC_CNT[31:0]) begin
                        refrac_busy[g] <= 1'b0;
                        refrac_cnt[g]  <= 32'd0;
                    end else begin
                        refrac_cnt[g] <= refrac_cnt[g] + 32'd1;
                    end
                end
            end
        end
    endgenerate

    assign pluck_pulse = pluck;
    wire any_pluck = |pluck;

    //--------------------------------------------------------------
    // 扫弦力度：流水线阶段1 —— 本拍锁存 dt / in_win / 方向
    //--------------------------------------------------------------
    reg  [31:0] time_cnt, last_time;
    reg  [5:0]  last_idx;
    reg         has_last;

    wire [31:0] dt_now  = time_cnt - last_time;
    wire        in_win_now = has_last && (dt_now < STRUM_CNT[31:0]);

    // 多弦同拍取代表编号（仅用于本拍扫弦方向/力度基准）
    reg [5:0] idx_now;
    always @* begin
        idx_now = 0;
        for (i = 0; i < WIDTH; i = i + 1)
            if (pluck[i]) idx_now = i[5:0];
    end

    // 流水线寄存器：dt 和方向打一拍；整个pluck位图也延迟（保证多弦不丢）
    reg [31:0] dt_q;
    reg        in_win_q;
    reg [5:0]  idx_q;
    reg        dir_up_q;
    reg        pluck_q;
    reg [WIDTH-1:0] pluck_vec_q;   // 延迟一拍的完整pluck位图

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dt_q <= 32'd0; in_win_q <= 1'b0; idx_q <= 6'd0;
            dir_up_q <= 1'b0; pluck_q <= 1'b0; pluck_vec_q <= 0;
        end else begin
            pluck_q  <= any_pluck;
            pluck_vec_q <= pluck;
            if (any_pluck) begin
                dt_q     <= dt_now;
                in_win_q <= in_win_now;
                idx_q    <= idx_now;
                dir_up_q <= (idx_now > last_idx);
            end
        end
    end

    //--------------------------------------------------------------
    // 流水线阶段2：由已寄存 dt 算力度（乘法+移位，无运行时除法器）
    //   目标：扫得越快（dt 越小、speed 越大）力度越大，线性映射到 16..127。
    //   speed ∈ [0, STRUM_CNT)，归一化力度增量 = speed*111/STRUM_CNT ∈ [0,111]。
    //   用定点系数 STRUM_K 实现：力度增量 = speed*STRUM_K >> STRUM_SHIFT。
    //   STRUM_K 是 localparam，由 CLK_FREQ_HZ 在【编译期】算出来（常量除法只
    //   在综合前求值，不进硬件），因此换时钟（12.288M↔50M）系数自动跟随，
    //   不会再出现旧版写死 156 导致 50MHz 下力度溢出回绕、越快越轻的问题。
    //   末尾再做饱和钳位，保证任何速度下力度都落在 [16,127]。
    //--------------------------------------------------------------
    localparam integer STRUM_SHIFT = 20;
    localparam integer STRUM_K =
        (111 * (1 << STRUM_SHIFT) + STRUM_CNT/2) / STRUM_CNT; // 四舍五入定点系数

    wire [31:0] speed_q  = in_win_q ? (STRUM_CNT[31:0] - dt_q - 32'd1) : 32'd0;
    wire [31:0] v_linear = 32'd16 + ((speed_q * STRUM_K) >> STRUM_SHIFT);
    wire [31:0] v_clamp  = (v_linear > 32'd127) ? 32'd127 : v_linear; // 饱和钳位
    wire [6:0]  vel_final = in_win_q ? v_clamp[6:0] : DEFAULT_VELOCITY;

    //--------------------------------------------------------------
    // pending 位图：多弦事件锁存，逐拍弹出（低编号先出）
    //--------------------------------------------------------------
    reg [WIDTH-1:0] pluck_pend;
    reg [6:0]       vel_q [0:WIDTH-1];

    function [3:0] f_first1;
        input [WIDTH-1:0] m;
        integer k;
        begin
            f_first1 = 4'd0;
            // 从高到低，匹配项依次覆盖，最后留下最低编号；无break可静态展开
            for (k = WIDTH-1; k >= 0; k = k - 1)
                if (m[k]) f_first1 = k[3:0];
        end
    endfunction

    wire [3:0] pop_idx = f_first1(pluck_pend);
    wire       pend_busy = |pluck_pend;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev <= 0; time_cnt <= 0; last_time <= 0; last_idx <= 0; has_last <= 0;
            pluck_pend <= 0;
            event_valid <= 0; event_on <= 0; event_num <= 0; event_vel <= 0;
            strum_dir <= 0; strum_valid <= 0;
            for (i = 0; i < WIDTH; i = i + 1) vel_q[i] <= 0;
        end else begin
            prev     <= string_blocked;
            time_cnt <= time_cnt + 32'd1;

            pluck_pend <= (pluck_pend & ~(pend_busy ? (1 << pop_idx) : 0)) | (pluck_q ? pluck_vec_q : 0);
            // 阶段2产出的拨弦：所有同拍弦都并入pending，力度共享（同拍dt相同）
            if (pluck_q) begin
                for (i = 0; i < WIDTH; i = i + 1)
                    if (pluck_vec_q[i]) vel_q[i] <= vel_final;
            end

            // 逐拍弹出：低编号先出，一拍一条
            event_valid <= pend_busy;
            event_on    <= 1'b1;
            if (pend_busy) begin
                event_num  <= note_of[pop_idx[2:0]];
                event_vel  <= vel_q[pop_idx[2:0]];
            end

            // 扫弦方向
            strum_valid <= pluck_q & in_win_q;
            if (pluck_q & in_win_q)
                strum_dir <= dir_up_q ? 2'd1 : 2'd2;
            else
                strum_dir <= 2'd0;

            // 更新最近拨弦记录（检测拍）
            if (any_pluck) begin
                last_time <= time_cnt;
                last_idx  <= idx_now;
                has_last  <= 1'b1;
            end
        end
    end

endmodule

`timescale 1ns / 1ps
//====================================================================
// c_to_voice_adapter  C 事件 → voice
//   重构 release：不用全局 note_release 电平 + 沿检测。
//   直接发 NOTE_OFF 事件，编号跟着事件走：
//     note_on  + note_num + velocity     （NOTE_ON）
//     note_off + note_off_num            （NOTE_OFF）
//   竖琴 pluck_style：NOTE_ON 后延时自动补 NOTE_OFF（同号）。
//====================================================================
module c_to_voice_adapter #(
    parameter integer CLK_FREQ_HZ      = 12_288_000,
    parameter integer PLUCK_RELEASE_MS = 120
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       event_valid,
    input  wire       event_on,        // 1=NOTE_ON 0=NOTE_OFF
    input  wire [6:0] event_num,
    input  wire [6:0] event_vel,
    input  wire       all_notes_off,
    input  wire       pluck_style,

    output wire       note_on,
    output wire [6:0] note_num,
    output wire [6:0] velocity,
    output reg        note_off,
    output reg  [6:0] note_off_num
);
    localparam integer REL_CNT = (CLK_FREQ_HZ / 1000) * PLUCK_RELEASE_MS;

    wire is_on  = event_valid &  event_on;
    wire is_off = event_valid & ~event_on;

    assign note_on  = is_on;
    assign note_num = event_num;
    assign velocity = event_vel;

    // 竖琴：记下当前音，超时发同号 NOTE_OFF
    reg [31:0] rel_cnt;
    reg        rel_busy;
    reg [6:0]  hold_num;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            note_off     <= 1'b0;
            note_off_num <= 7'd0;
            rel_cnt      <= 32'd0;
            rel_busy     <= 1'b0;
            hold_num     <= 7'd0;
        end else begin
            note_off <= 1'b0;   // 默认 1 拍脉冲

            if (all_notes_off) begin
                // 总停：跟一条 NOTE_OFF（用 0 作通配也可；这里发 hold 号）
                note_off     <= 1'b1;
                note_off_num <= hold_num;
                rel_busy     <= 1'b0;
                rel_cnt      <= 32'd0;
            end else if (is_on) begin
                hold_num <= event_num;
                if (pluck_style) begin
                    rel_busy <= 1'b1;
                    rel_cnt  <= 32'd0;
                end else begin
                    rel_busy <= 1'b0;
                end
            end else if (is_off) begin
                // 钢琴松开：NOTE_OFF，编号在事件上
                note_off     <= 1'b1;
                note_off_num <= event_num;
                rel_busy     <= 1'b0;
                rel_cnt      <= 32'd0;
            end else if (rel_busy && pluck_style) begin
                if (rel_cnt >= REL_CNT[31:0]) begin
                    note_off     <= 1'b1;
                    note_off_num <= hold_num;
                    rel_busy     <= 1'b0;
                end else begin
                    rel_cnt <= rel_cnt + 32'd1;
                end
            end
        end
    end
endmodule

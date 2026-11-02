`timescale 1ns / 1ps
//====================================================================
// guide_seq  脱机 LED 演奏指引（拓展4）
//
//   内置一首示范曲（小星星，14 个音），设备自动演奏，同时用 8 颗
//   WS2812 逐音提示"下一个该按哪个键"：
//     当前应按键 -> 蓝色
//     玩家按对   -> 该键变绿
//     其余       -> 熄灭
//
//   进入方式：上电时按住 TTP 超过3秒，见 top_system 的 boot 采样
//   退出方式：断电重启
//
//   节奏：每个音 300ms（谱面 6 个 50ms 单位），长音 600ms，
//         一句放完停 1s 再循环
//====================================================================
module guide_seq #(
    parameter integer CLK_FREQ_HZ = 50_000_000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,          // 1=工作在指引模式
    input  wire [7:0]  key_on,          // 8 个 FSR 的按下位图（用于"按对了"检测）

    output reg         note_on,
    output reg  [6:0]  note_num,
    output reg  [6:0]  velocity,
    output reg         note_off,
    output reg  [6:0]  note_off_num,

    output reg  [2:0]  cur_key,         // 当前应该按的键（0..7）
    output reg         guiding,         // 1=正在指引（有当前音）
    output wire        led_on,          // 灯：与提示音共用音符门控，每音末留50ms暗隙
    output wire        hit              // 1=本音已被按对（LED 变绿）
);

    //----------------------------------------------------------------
    // 谱子：{音号[6:0], 时长[7:0]}，时长单位 50ms
    //   小星星：C C G G A A G | F F E E D D C
    //----------------------------------------------------------------
    localparam integer N_NOTE = 14;
    reg [14:0] song [0:N_NOTE-1];
    integer i;
    initial begin
        song[0]  = {7'd60, 8'd6};
        song[1]  = {7'd60, 8'd6};
        song[2]  = {7'd67, 8'd6};
        song[3]  = {7'd67, 8'd6};
        song[4]  = {7'd69, 8'd6};
        song[5]  = {7'd69, 8'd6};
        song[6]  = {7'd67, 8'd12};
        song[7]  = {7'd65, 8'd6};
        song[8]  = {7'd65, 8'd6};
        song[9]  = {7'd64, 8'd6};
        song[10] = {7'd64, 8'd6};
        song[11] = {7'd62, 8'd6};
        song[12] = {7'd62, 8'd6};
        song[13] = {7'd60, 8'd12};
    end

    // 音号 -> 键位（C4 D4 E4 F4 G4 A4 B4 C5）
    function [2:0] note2key;
        input [6:0] n;
        begin
            case (n)
                7'd60: note2key = 3'd0;
                7'd62: note2key = 3'd1;
                7'd64: note2key = 3'd2;
                7'd65: note2key = 3'd3;
                7'd67: note2key = 3'd4;
                7'd69: note2key = 3'd5;
                7'd71: note2key = 3'd6;
                7'd72: note2key = 3'd7;
                default: note2key = 3'd0;
            endcase
        end
    endfunction

    localparam integer MS50 = CLK_FREQ_HZ / 20;    // 50ms 的时钟数

    localparam [2:0] S_REST = 2'd0,
                     S_ON   = 2'd1,
                     S_HOLD = 2'd2,
                     S_OFF  = 3'd3, S_GAP = 3'd4;

    reg [2:0]  st;
    reg [3:0]  idx;
    reg [31:0] dly;
    reg [31:0] dur_clk;
    reg        hit_r;

    wire [6:0] cur_note = song[idx][14:8];
    wire [7:0] cur_dur  = song[idx][7:0];

    assign hit = hit_r;

    // One musical gate drives sound and target light. The final 50ms of
    // each beat is a shared rest, so repeated pitches visibly re-articulate.
    assign led_on = guiding;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_REST; idx <= 4'd0; dly <= 32'd0; dur_clk <= 32'd0;
            note_on <= 1'b0; note_num <= 7'd0; velocity <= 7'd0;
            note_off <= 1'b0; note_off_num <= 7'd0;
            cur_key <= 3'd0; guiding <= 1'b0; hit_r <= 1'b0;
        end else begin
            note_on  <= 1'b0;
            note_off <= 1'b0;

            if (!enable) begin
                if (guiding) begin note_off<=1;note_off_num<=note_num;end
                hit_r<=0;
                st <= S_REST; idx <= 4'd0; dly <= 32'd0; guiding <= 1'b0;
            end else begin
                case (st)
                S_REST: begin
                    guiding <= 1'b0;
                    if (dly >= 32'd20 * MS50[31:0]) begin
                        dly <= 32'd0;
                        idx <= 4'd0;
                        st  <= S_ON;
                    end else dly <= dly + 32'd1;
                end

                S_ON: begin
                    note_on      <= 1'b1;
                    note_num     <= cur_note;
                    velocity     <= 7'd80;
                    cur_key      <= note2key(cur_note);
                    guiding      <= 1'b1;
                    hit_r        <= 1'b0;
                    dur_clk      <= {24'd0, cur_dur} * MS50[31:0];
                    dly          <= 32'd0;
                    st           <= S_HOLD;
                end

                S_HOLD: begin
                    if (key_on[cur_key]) hit_r <= 1'b1;
                    if (dly >= dur_clk - MS50 - 1) begin
                        dly <= 32'd0;
                        st  <= S_OFF;
                    end else dly <= dly + 32'd1;
                end

                S_OFF: begin
                    note_off     <= 1'b1;
                    note_off_num <= cur_note;
                    guiding      <= 1'b0;
                    dly <= 0;
                    st <= S_GAP;
                end

                S_GAP: begin
                    if(dly >= MS50-1) begin
                        dly <= 0;
                        if(idx == N_NOTE-1) st <= S_REST;
                        else begin idx <= idx + 1'b1; st <= S_ON; end
                    end else dly <= dly + 1'b1;
                end

                default: st <= S_REST;
                endcase
            end
        end
    end

endmodule

`timescale 1ns / 1ps
//====================================================================
// event_fifo.v —— Air Piano 事件先进先出队列（队员 B，跨时钟域交接前缓冲）
//   作用：c_interact_top / demo_seq 在 50MHz 域产出的音符事件，可能在极短
//         时间内突发一批（8 键/8 弦同时触发，8 拍内 8 条），而下游 4-phase
//         握手跨时钟域消费较慢（µs 级）。FIFO 把突发事件暂存、再逐条送出，
//         避免丢音；队列满时 dropped 置位（可观测，正常情况不应发生）。
//
//   参数：DEPTH=16（覆盖整机最大突发 8 条，留 2 倍余量）；DW=17（payload）。
//
//   payload（17bit）：[16]timbre  [15:14]type  [13:7]num  [6:0]vel
//====================================================================
module event_fifo #(
    parameter integer DEPTH = 16,
    parameter integer DW    = 17,
    parameter integer AW    = 4          // 指针位宽 = log2(DEPTH)
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire             push,        // 写入请求（1 拍）
    input  wire [DW-1:0]    push_data,   // 写入数据
    input  wire             pop,         // 读出请求（1 拍）
    output wire [DW-1:0]    pop_data,    // 队头数据（组合，= mem[rd]）
    output wire             full,
    output wire             empty,
    output reg              dropped      // 满时仍 push → 置1（丢音标志）
);
    reg [DW-1:0] mem [0:DEPTH-1];
    reg [AW-1:0] wr, rd;
    reg [AW:0]   count;                  // 多 1 位，可表示 0..DEPTH

    assign full  = (count == DEPTH[AW:0]);
    assign empty = (count == 0);
    assign pop_data = mem[rd];

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr      <= {AW{1'b0}};
            rd      <= {AW{1'b0}};
            count   <= 0;
            dropped <= 1'b0;
            for (i = 0; i < DEPTH; i = i + 1) mem[i] <= {DW{1'b0}};
        end else begin
            case ({push && (!full || (pop && !empty)), pop && !empty})
                2'b10: begin                 // 只写
                    mem[wr] <= push_data;
                    wr      <= wr + 1'b1;
                    count   <= count + 1'b1;
                end
                2'b01: begin                 // 只读
                    rd      <= rd + 1'b1;
                    count   <= count - 1'b1;
                end
                2'b11: begin                 // 同时读写，计数不变
                    mem[wr] <= push_data;
                    wr      <= wr + 1'b1;
                    rd      <= rd + 1'b1;
                end
                default: ;
            endcase

            // 满时仍来写：丢弃并置标志（正常情况不应触发）
            if (push && full && !(pop && !empty)) dropped <= 1'b1;
        end
    end
endmodule

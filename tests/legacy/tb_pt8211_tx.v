`timescale 1ns / 1ps
//====================================================================
// tb_pt8211_tx.v —— PT8211 发送器 testbench
//   输入固定 left=16'h1234, right=16'h5678
//   在 BCLK 上升沿采样 dacdat，解码出串行数据
//   验证：左声道=0x1234，右声道=0x5678
//====================================================================
module tb_pt8211_tx;

    reg         clk;
    reg         rst_n;
    reg  [15:0] left_data;
    reg  [15:0] right_data;
    wire        bclk;
    wire        ws;
    wire        dacdat;
    wire        sample_tick;

    // 12.264MHz → 周期约 81.5ns，这里用 81.5ns
    localparam CLK_PERIOD = 81.5;

    // DUT
    pt8211_tx u_dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .left_data  (left_data),
        .right_data (right_data),
        .bclk       (bclk),
        .ws         (ws),
        .dacdat     (dacdat),
        .sample_tick(sample_tick)
    );

    // 时钟
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // 解码用变量
    reg [15:0] decoded_left;
    reg [15:0] decoded_right;
    integer    bit_cnt;
    reg [15:0] shift_recv;
    reg        prev_bclk;
    reg        prev_ws;

    // 在 BCLK 上升沿采样 dacdat
    always @(posedge clk) begin
        if (!rst_n) begin
            prev_bclk  <= 1'b0;
            prev_ws    <= 1'b0;
            bit_cnt    <= 0;
            shift_recv <= 16'd0;
        end else begin
            prev_bclk <= bclk;
            prev_ws   <= ws;

            // BCLK 上升沿（prev_bclk=0, bclk=1）
            if (!prev_bclk && bclk) begin
                shift_recv <= {shift_recv[14:0], dacdat};
                bit_cnt    <= bit_cnt + 1;

                // 收满16位
                if (bit_cnt == 15) begin
                    if (ws == 1'b0)  // 左声道
                        decoded_left  <= {shift_recv[14:0], dacdat};
                    else             // 右声道
                        decoded_right <= {shift_recv[14:0], dacdat};
                    bit_cnt <= 0;
                end
            end

            // WS 翻转时打印当前帧结果
            if (prev_ws != ws && bit_cnt == 0) begin
                $display("=== 新帧开始 ===");
                $display("解码左声道 = 0x%h (期望 0x1234)", decoded_left);
                $display("解码右声道 = 0x%h (期望 0x5678)", decoded_right);
                if (decoded_left == 16'h1234 && decoded_right == 16'h5678)
                    $display(">>> PASS: PT8211 格式正确!");
                else
                    $display(">>> FAIL: 数据不匹配!");
            end
        end
    end

    // 主激励
    initial begin
        // 初始化
        rst_n     = 1'b0;
        left_data = 16'h1234;
        right_data= 16'h5678;
        decoded_left  = 16'd0;
        decoded_right = 16'd0;

        // 复位
        #(CLK_PERIOD*4);
        rst_n = 1'b1;

        // 跑 3 个完整帧（每帧 256 个时钟）
        #(CLK_PERIOD*256*4);

        $display("\n=== 仿真结束 ===");
        $finish;
    end

    // 波形 dump
    initial begin
        $dumpfile("tb_pt8211_tx.vcd");
        $dumpvars(0, tb_pt8211_tx);
    end

endmodule

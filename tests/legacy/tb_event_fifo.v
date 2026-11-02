`timescale 1ns / 1ps
//====================================================================
// tb_event_fifo.v —— 验证事件队列（整机修复任务11）
//   测试1：8 拍内连续 push 8 条（模拟 8 键/8 弦突发），期间不 pop，
//          应不丢（full=0、dropped=0、计数=8）；随后慢速 pop，顺序/数据正确。
//   测试2：填满 16 条后 full=1，第 17 条 push 应被丢弃、dropped=1；
//          再逐条 pop 出 16 条，顺序正确、最终 empty。
//====================================================================
module tb_event_fifo;
    reg clk = 1'b0; always #10 clk = ~clk;   // 50MHz
    reg rst_n = 1'b0;
    reg        push = 1'b0, pop = 1'b0;
    reg [16:0] push_data = 17'd0;
    wire [16:0] pop_data;
    wire full, empty;
    reg  dropped;
    integer fail = 0;
    integer n;
    reg [16:0] captured;

    event_fifo #(.DEPTH(16), .DW(17), .AW(4)) dut (
        .clk(clk), .rst_n(rst_n),
        .push(push), .push_data(push_data),
        .pop(pop), .pop_data(pop_data),
        .full(full), .empty(empty), .dropped(dropped)
    );

    task do_push;
        input [16:0] d;
        begin
            @(negedge clk); push = 1'b1; push_data = d;
            @(posedge clk);
            @(negedge clk); push = 1'b0;
        end
    endtask

    task do_pop;
        begin
            @(negedge clk); pop = 1'b1;
            @(posedge clk);
            captured = pop_data;      // 该拍 pop_data = 队头（旧 rd）
            @(negedge clk); pop = 1'b0;
        end
    endtask

    initial begin
        $dumpfile("tb_event_fifo.vcd");
        $dumpvars(0, tb_event_fifo);

        repeat (6) @(posedge clk);
        rst_n = 1'b1;
        repeat (6) @(posedge clk);

        // ================= 测试1：突发 8 条 =================
        $display("[1] 8 拍内突发 push 8 条，期间不 pop");
        for (n = 0; n < 8; n = n + 1) do_push(17'd100 + n);

        @(posedge clk);
        if (full)       begin $display("[1] FAIL: 不该满（只8条）"); fail=fail+1; end
        if (dropped)    begin $display("[1] FAIL: 不该丢音");       fail=fail+1; end
        if (dut.count !== 5'd8) begin
            $display("[1] FAIL: count=%0d（期望8）", dut.count); fail=fail+1;
        end else $display("[1] OK: 8 条全收下，未丢");

        // 慢速消费，每 50 拍 pop 一条
        for (n = 0; n < 8; n = n + 1) begin
            repeat (50) @(posedge clk);
            do_pop();
            if (captured !== 17'd100 + n) begin
                $display("[1] FAIL: 第%0d 条读出=%0d（期望%0d）", n, captured, 100+n);
                fail = fail + 1;
            end
        end
        if (fail === 0) $display("[1] OK: 8 条顺序/数据正确，已清空");
        if (!empty) begin $display("[1] FAIL: 消费后应 empty"); fail=fail+1; end

        // ================= 测试2：填满 16 + 溢出 =================
        $display("[2] 填满 16 条，第 17 条应被丢弃");
        for (n = 0; n < 16; n = n + 1) do_push(17'd200 + n);
        @(posedge clk);
        if (!full) begin $display("[2] FAIL: 16 条应 full"); fail=fail+1; end
        do_push(17'd999);                          // 第 17 条
        if (!dropped) begin $display("[2] FAIL: 第17条应触发 dropped"); fail=fail+1;
        end else $display("[2] OK: full 后第17条被丢弃，dropped=1");

        // pop 出 16 条，检查顺序，且不含 999
        for (n = 0; n < 16; n = n + 1) begin
            do_pop();
            if (captured !== 17'd200 + n) begin
                $display("[2] FAIL: 第%0d 条读出=%0d（期望%0d）", n, captured, 200+n);
                fail = fail + 1;
            end
        end
        if (!empty) begin $display("[2] FAIL: 应 empty"); fail=fail+1;
        end else $display("[2] OK: 16 条顺序正确，999 未入队");

        if (fail == 0) $display("==== TEST PASSED ====");
        else           $display("==== TEST FAILED, fail=%0d ====", fail);
        $finish;
    end
endmodule

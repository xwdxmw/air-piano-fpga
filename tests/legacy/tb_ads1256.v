`timescale 1ns / 1ps
//====================================================================
// tb_ads1256  ADS1256 SPI 驱动仿真
//   内置一个 ADS1256 从机模型（slave）：
//     - 识别 SDATAC / WREG / SYNC / WAKEUP / SELFCAL / RDATA
//     - 记录写入的寄存器（STATUS/ADCON/DRATE/MUX）
//     - WAKEUP 后 210us 把 DRDY 拉低（手册 Table 13：30kSPS 时 t18=0.21ms）
//     - RDATA 若在 DRDY 拉低前抢读（驱动超时），返回全 1（模拟真机无效数据）
//     - RDATA 后按当前 MUX 通道返回 24bit 测试数据
//   每通道测试数据（真实单端 24bit 补码）：bit23=0(正)，有效 bit22..11 = A00 + ch*16
//     驱动取 bit22..11 后应依次为 A00 A10 ... A70；低 11 位固定 0x555 作取位干扰
//====================================================================
module tb_ads1256 #(
    // 模拟 WAKEUP→DRDY 稳定时间(us)：手册 30kSPS t18=210（默认）；
    // 调大到 300 可验证驱动超时裕量能否覆盖芯片批次/温度离散。
    parameter integer DRDY_US = 210
);

    // ---------- 时钟 / 复位 ----------
    reg clk;
    reg rst_n;
    initial clk = 1'b0;
    always #10 clk = ~clk;        // 50MHz，周期 20ns

    // ---------- DUT 物理线 ----------
    wire        ads_sclk, ads_mosi, ads_cs_n, ads_reset_n;
    wire        ads_miso;
    wire        ads_drdy;
    wire [95:0] adc_data;
    wire        adc_valid;

    // 自校准等待缩短为 50us，加快仿真（不影响时序验证）
    ads1256_driver #(
        .CLK_FREQ_HZ (50_000_000),
        .CAL_WAIT_US (50)
    ) u_dut (
        .clk(clk), .rst_n(rst_n),
        .ads_sclk(ads_sclk), .ads_mosi(ads_mosi),
        .ads_miso(ads_miso), .ads_cs_n(ads_cs_n),
        .ads_drdy(ads_drdy), .ads_reset_n(ads_reset_n),
        .adc_data(adc_data), .adc_valid(adc_valid)
    );

    //==================================================================
    // ADS1256 从机模型
    //==================================================================
    reg         miso_r;
    reg         drdy_r;
    reg [7:0]   rx_byte;
    integer     sbit;
    reg [1:0]   sub;            // 0命令 1等WREG数量 2等WREG数据
    reg [2:0]   waddr;
    reg [7:0]   regs [0:3];
    reg [2:0]   cur_ch;
    reg [5:0]   rbit;
    reg         read_mode;
    reg [23:0]  out_data;
    reg [31:0]  wake_seq, rdata_seq;   // 命令序号（parse 块写，clk块采样）
    reg [31:0]  wake_q,   rdata_q;
    reg         conv_run;
    integer     conv_cnt;

    // 真实单端 24bit 补码：正输入 bit23=0，有效数据 bit22..11 = 期望高12位 hi，
    // 低 11 位(bit10..0) 填 0x555 作干扰，验证取位不会错位。
    // ch0~6：hi=0xA00 + ch*16（均 > 0x7FF，错取 bit23..12 必然取不到）。
    // ch7：模拟未接/悬空通道被偏置成负码（0xFFFFFF，bit23=1），驱动应钳位到 0。
    function [23:0] channel_data;
        input [2:0] c;
        reg [11:0] hi;
        begin
            if (c == 3'd7) begin
                channel_data = 24'hFFFFFF;        // 负满偏（悬空），期望被钳位为 0
            end else begin
                hi = 12'hA00 + {9'd0, c}*16;
                channel_data = {1'b0, hi[11:0], 11'h555};
            end
        end
    endfunction

    // 单端取位 + 负码钳位模型（驱动应与之一致）：
    //   bit23=1(负码，悬空/异常) -> 0；bit23=0(正) -> 取 bit22..11
    function [11:0] ext12;
        input [23:0] d;
        begin
            ext12 = d[23] ? 12'h000 : d[22:11];
        end
    endfunction

    // 初始值
    initial begin
        miso_r    = 1'b1;
        drdy_r    = 1'b1;
        rx_byte   = 8'h00;
        sbit      = 0;
        sub       = 2'd0;
        cur_ch    = 3'd0;
        rbit      = 6'd0;
        read_mode = 1'b0;
        wake_seq  = 0;
        rdata_seq = 0;
        wake_q    = 0;
        rdata_q   = 0;
        conv_run  = 1'b0;
        conv_cnt  = 0;
        regs[0]=0; regs[1]=0; regs[2]=0; regs[3]=0;
    end

    // 转换计时（DRDY 唯一由本块驱动）：
    //   WAKEUP 后 210us（10500个 50MHz 时钟，=手册 t18）DRDY 拉低；RDATA 后复位为高
    always @(posedge clk or negedge ads_reset_n) begin
        if (!ads_reset_n) begin
            drdy_r   <= 1'b1;
            wake_q   <= 0;
            rdata_q  <= 0;
            conv_run <= 1'b0;
            conv_cnt <= 0;
        end else begin
            wake_q  <= wake_seq;
            rdata_q <= rdata_seq;
            if (wake_seq != wake_q) begin
                drdy_r   <= 1'b1;      // 新转换开始
                conv_run <= 1'b1;
                conv_cnt <= 0;
            end else if (rdata_seq != rdata_q) begin
                drdy_r   <= 1'b1;      // 数据被读走
                conv_run <= 1'b0;
            end else if (conv_run) begin
                if (conv_cnt >= DRDY_US*50) begin
                    drdy_r   <= 1'b0;  // 转换完成
                    conv_run <= 1'b0;
                end else conv_cnt <= conv_cnt + 1;
            end
        end
    end

    // SCLK 下降沿：采样 MOSI / （读数据时）更新 DOUT
    always @(negedge ads_sclk or posedge ads_cs_n) begin
        if (ads_cs_n) begin
            sbit      = 0;
            read_mode = 1'b0;
        end else begin
            rx_byte = {rx_byte[6:0], ads_mosi};     // 阻塞拼字节

            if (read_mode) begin
                // 读数据：每个下降沿输出下一位
                if (rbit < 24) miso_r = out_data[23 - rbit];
                rbit = rbit + 1;
                if (rbit >= 24) read_mode = 1'b0;
            end

            if (sbit == 7) begin
                // 一字节收完，解析（读数据时 dummy 字节忽略）
                if (!read_mode) parse(rx_byte);
                sbit = 0;
            end else sbit = sbit + 1;
        end
    end

    // 命令解析（阻塞任务）
    task parse;
        input [7:0] b;
        begin
            case (sub)
                2'd0: begin
                    if (b[7:4] == 4'h5) begin
                        // WREG 命令
                        sub   = 2'd1;
                        waddr = b[2:0];
                    end else if (b == 8'h00) begin
                        // WAKEUP：启动一次转换（仅发序号，clk块统一处理）
                        wake_seq = wake_seq + 1;
                    end else if (b == 8'h01) begin
                        // RDATA：仅当本通道转换完成（DRDY 已拉低，conv_run=0）时
                        // 才返回当前通道有效数据；若还在转换（驱动未等就绪就抢读），
                        // 返回全 1，模拟真实芯片“数据未就绪时读到无效值”。
                        if (conv_run) out_data = 24'hFFFFFF;
                        else          out_data = channel_data(cur_ch);
                        miso_r    = out_data[23];
                        rbit      = 6'd1;
                        read_mode = 1'b1;
                        rdata_seq = rdata_seq + 1;
                    end
                    // 0x0F SDATAC / 0xFC SYNC / 0xF0 SELFCAL：无额外动作
                end
                2'd1: begin
                    sub = 2'd2;          // 数量字节，忽略
                end
                2'd2: begin
                    regs[waddr] = b;    // 数据字节
                    if (waddr == 3'd1) cur_ch = b[6:4];
                    sub = 2'd0;
                end
                default: sub = 2'd0;
            endcase
        end
    endtask

    // CS 高时 DOUT 空闲为 1，否则从机驱动
    assign ads_miso = ads_cs_n ? 1'b1 : miso_r;
    assign ads_drdy = drdy_r;

    //==================================================================
    // 测试主流程
    //==================================================================
    integer        ch;
    integer        round;
    reg [11:0]     exp_val;
    reg [11:0]     actual;
    integer        errors;
    reg            got_valid;
    // 记录相邻两轮 adc_valid 的时间戳，用于周期级实测轮询耗时
    time           tv0, tv1;
    integer        nv = 0;
    always @(posedge adc_valid) begin
        if (nv == 0) begin tv0 = $realtime; nv = 1; end
        else if (nv == 1) begin tv1 = $realtime; nv = 2; end
    end

    initial begin
        rst_n  = 1'b0;
        errors = 0;
        $display("==== tb_ads1256 start ====");
        #200;
        rst_n  = 1'b1;

        // 跑 2 轮采集
        for (round = 0; round < 2; round = round + 1) begin
            // 等 adc_valid 脉冲（上电首轮较慢，给 5ms）
            got_valid = 1'b0;
            fork: wait_valid
                begin @(posedge adc_valid); got_valid = 1'b1; end
                begin #10_000_000; got_valid = 1'b0; end
            join_any
            disable wait_valid;

            if (!got_valid) begin
                $display("ERROR: timeout waiting adc_valid round %0d", round);
                errors = errors + 1;
            end

            #100;   // 等 adc_data 锁存稳定
            $display("---- Round %0d : adc_data = %h ----", round, adc_data);

            // 校验 8 路数据：ch0~6 为正码 A00~A60；ch7 为负码，钳位后期望 0
            for (ch = 0; ch < 8; ch = ch + 1) begin
                exp_val = (ch == 7) ? 12'h000 : (12'hA00 + ch*16);
                actual  = adc_data[ch*12 +: 12];
                if (actual !== exp_val) begin
                    $display("  FAIL ch%0d: expected %h, got %h", ch, exp_val, actual);
                    errors = errors + 1;
                end else begin
                    $display("  PASS ch%0d: %h", ch, actual);
                end
            end
        end

        // 周期级实测：一轮 8 通道耗时
        if (nv == 2) begin
            $display("---- measured round period = %0t (between two adc_valid) ----", tv1-tv0);
        end

        // 校验初始化寄存器
        $display("---- regs: STATUS=%h (exp 06) ADCON=%h (exp 00) DRATE=%h (exp F0) ----",
                 regs[0], regs[2], regs[3]);
        if (regs[0] !== 8'h06) begin $display("  FAIL STATUS"); errors=errors+1; end
        if (regs[2] !== 8'h00) begin $display("  FAIL ADCON");  errors=errors+1; end
        if (regs[3] !== 8'hF0) begin $display("  FAIL DRATE");  errors=errors+1; end

        // 取位/钳位边界自检（24bit 补码）：
        //   0V=0x000000 -> 000；+VREF=0x7FFFFF -> FFF(4095)；
        //   负码 0x800000 / 0xE00000 / 0xFFFFFF 全部钳位到 000（悬空通道）
        $display("---- span/clamp: 0->%03h,7FFFFF->%03h, 800000->%03h,E00000->%03h,FFFFFF->%03h ----",
                 ext12(24'h000000), ext12(24'h7FFFFF),
                 ext12(24'h800000), ext12(24'hE00000), ext12(24'hFFFFFF));
        if (ext12(24'h000000) !== 12'h000) begin $display("  FAIL span zero"); errors=errors+1; end
        if (ext12(24'h7FFFFF) !== 12'hFFF) begin $display("  FAIL span fullscale"); errors=errors+1; end
        if (ext12(24'h800000) !== 12'h000) begin $display("  FAIL clamp 800000"); errors=errors+1; end
        if (ext12(24'hE00000) !== 12'h000) begin $display("  FAIL clamp E00000"); errors=errors+1; end
        if (ext12(24'hFFFFFF) !== 12'h000) begin $display("  FAIL clamp FFFFFF"); errors=errors+1; end

        if (errors == 0) $display("==== ALL TESTS PASSED ====");
        else             $display("==== %0d ERRORS ====", errors);
        $finish;
    end

    // 安全看门狗（防止死循环）
    initial begin
        #40_000_000;
        $display("ERROR: global watchdog timeout");
        $finish;
    end

endmodule

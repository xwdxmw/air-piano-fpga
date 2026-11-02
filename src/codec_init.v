//====================================================================
// codec_init.v —— 板载 codec I2C 初始化（队员 B · 契约 §4.3）
//
// 功能：上电延时 >50ms → 通过 I2C 逐个写 codec 寄存器序列 →
//       完成后拉高 codec_ready（此后音频通路可用）。
//
// 目标 codec：WM8978 / ES8388 一类（I2C 从地址 0x1A 常见），
//   具体型号需从板卡原理图（Board Schematic）确认；寄存器序列为
//   WM8978 参考配置，上板前按 datasheet 与原理图核对微调。
//
// I2C 写协议（WM8978，每寄存器 3 字节）：
//   START → 设备地址<<1|W(0x34) → ACK → {reg[6:0], data[8]} → ACK
//         → {data[7:0]} → ACK → STOP
//
// 时序：SCL 约 100 kHz（12.288M / (61×2) ≈ 100.7k）；SDA 在 SCL
//   低电平期间变化、高电平期间稳定（标准 I2C）。
//====================================================================

module codec_init #(
    parameter I2C_ADDR  = 7'h1A,   // WM8978 从地址（写字节 = 0x34）
    parameter SCL_HALF  = 61,      // SCL 半周期计数（12.288M/2/100k ≈ 61）
    parameter DELAY_CNT = 614400   // >50ms @12.288M（0.05 × 12288000）
)(
    input  wire clk,               // 12.288 MHz
    input  wire rst_n,             // 低有效复位
    output reg  i2c_scl,           // I2C 时钟（外加上拉）
    inout  wire i2c_sda,           // I2C 数据（双向，外加上拉）
    output reg  codec_ready,       // 1 = 初始化完成
    output reg  ack_err            // 1 = 出现过无 ACK（调试用）
);

    //--------------------------------------------------------------
    // 寄存器序列 ROM（WM8978 参考配置；{reg[6:0], data[8:0]}）
    // 注释见 README：型号确认后按 datasheet 调整
    //--------------------------------------------------------------
    localparam REG_CNT = 9;
    reg [15:0] reg_rom [0:REG_CNT-1];
    initial begin
        reg_rom[0] = 16'h0079;  // R0  ：电源1：BIAS/VMID 使能
        reg_rom[1] = 16'h00F9;  // R1  ：电源2：DAC/输出缓冲/耳机功放使能
        reg_rom[2] = 16'h0279;  // R2  ：左耳机输出音量（参考 0x79）
        reg_rom[3] = 16'h0379;  // R3  ：右耳机输出音量
        reg_rom[4] = 16'h0508;  // R5  ：DAC 通路使能（DACMU=0）
        reg_rom[5] = 16'h0A00;  // R10 ：左输出通路：关闭输入混合（防 MIC 噪声）
        reg_rom[6] = 16'h0B00;  // R11 ：右输出通路：关闭输入混合
        reg_rom[7] = 16'h1003;  // R16 ：时钟分频：MCLK=256fs @48k
        reg_rom[8] = 16'h1100;  // R17 ：接口控制：16bit I2S 从模式
    end

    //--------------------------------------------------------------
    // SCL 产生：连续运行，相位计数器驱动（高低各 SCL_HALF 拍）
    //--------------------------------------------------------------
    reg [15:0] scl_cnt;
    wire scl_lo_mid = (scl_cnt == SCL_HALF/2);         // 低相位中点：更新 SDA
    wire scl_hi_end = (scl_cnt == SCL_HALF*2 - 1);     // 高相位结束：推进状态

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            scl_cnt <= 0;
        else if (scl_hi_end)
            scl_cnt <= 0;
        else
            scl_cnt <= scl_cnt + 1'b1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            i2c_scl <= 1'b1;
        else
            i2c_scl <= (scl_cnt >= SCL_HALF);   // 高半周期 = 1
    end

    //--------------------------------------------------------------
    // 状态机：IDLE → DELAY(>50ms) → 写 REG_CNT 个寄存器 → DONE
    //--------------------------------------------------------------
    localparam [3:0] ST_IDLE=0, ST_DELAY=1, ST_START1=2, ST_START2=3,
                     ST_BIT=4, ST_ACK=5, ST_STOP1=6, ST_STOP2=7, ST_DONE=8;

    reg [3:0]  state;
    reg [19:0] delay_cnt;          // >50ms 延时
    reg [4:0]  reg_idx;            // 当前寄存器索引
    reg [1:0]  byte_idx;           // 0=设备地址 1={reg,data8} 2=data7:0
    reg [3:0]  bit_cnt;            // 0..7
    reg [7:0]  tx_byte;            // 正在发送的字节
    reg        sda_out;            // SDA 输出寄存器
    reg        sda_en;             // 1=驱动 SDA，0=释放（上拉）
    reg        ack_r;

    assign i2c_sda = sda_en ? sda_out : 1'bz;

    // 当前帧要发送的字节
    wire [7:0] addr_byte = {I2C_ADDR, 1'b0};              // 写地址
    wire [7:0] reg_byte  = {reg_rom[reg_idx][14:8], reg_rom[reg_idx][8]};  // {reg[6:0], data[8]}
    wire [7:0] data_byte = reg_rom[reg_idx][7:0];         // data[7:0]

    // 字节 → tx_byte 选择
    always @(*) begin
        case (byte_idx)
            2'd0: tx_byte = addr_byte;
            2'd1: tx_byte = reg_byte;
            default: tx_byte = data_byte;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= ST_IDLE;
            delay_cnt   <= 0;
            reg_idx     <= 0;
            byte_idx    <= 0;
            bit_cnt     <= 0;
            sda_out     <= 1'b1;
            sda_en      <= 1'b0;
            codec_ready <= 1'b0;
            ack_r       <= 1'b0;
            ack_err     <= 1'b0;
        end
        else begin
            case (state)
                // ---------- 延时 >50ms ----------
                ST_IDLE: begin
                    state <= ST_DELAY;
                end
                ST_DELAY: begin
                    if (delay_cnt == DELAY_CNT) begin
                        delay_cnt <= 0;
                        state     <= ST_START1;      // 开始写第 0 个寄存器
                    end
                    else
                        delay_cnt <= delay_cnt + 1'b1;
                end

                // ---------- START：SCL 高时 SDA 1→0 ----------
                ST_START1: begin
                    // 等待 SCL 高相位：在 scl_lo_mid 时刻准备，在高相位拉低 SDA
                    // 简化：直接拉低 SDA 并在下一拍进入（SCL 连续运行，处于高相位）
                    sda_en  <= 1'b1;
                    sda_out <= 1'b0;                 // START 条件
                    byte_idx <= 0;
                    bit_cnt  <= 0;
                    state    <= ST_START2;
                end
                ST_START2: begin
                    sda_out <= 1'b0;                 // 保持低
                    state   <= ST_BIT;               // 开始发第一个字节
                end

                // ---------- 发送 1 字节（8 位 + ACK） ----------
                ST_BIT: begin
                    if (scl_lo_mid) begin
                        // SCL 低：更新 SDA（MSB first）
                        sda_en  <= 1'b1;
                        sda_out <= tx_byte[7 - bit_cnt[2:0]];
                    end
                    if (scl_hi_end) begin
                        if (bit_cnt == 4'd7) begin
                            bit_cnt <= 0;
                            state   <= ST_ACK;        // 8 位发完 → ACK 相位
                        end
                        else
                            bit_cnt <= bit_cnt + 1'b1;
                    end
                end

                // ---------- ACK：释放 SDA，SCL 高时采样 ----------
                ST_ACK: begin
                    if (scl_lo_mid) begin
                        sda_en <= 1'b0;               // 释放 SDA（从机应答）
                    end
                    if (scl_hi_end) begin
                        ack_r <= i2c_sda;             // 采样 ACK（0=有应答）
                        if (i2c_sda == 1'b1) ack_err <= 1'b1;  // 无应答，置位错误标志
                        if (byte_idx == 2'd2) begin
                            // 3 字节写完 → 该寄存器完成
                            byte_idx <= 0;
                            state    <= ST_STOP1;
                        end
                        else begin
                            byte_idx <= byte_idx + 1'b1;
                            state    <= ST_BIT;
                        end
                    end
                end

                // ---------- STOP：SCL 高时 SDA 0→1 ----------
                ST_STOP1: begin
                    sda_en  <= 1'b1;
                    sda_out <= 1'b0;                  // 保持低
                    state   <= ST_STOP2;
                end
                ST_STOP2: begin
                    if (scl_lo_mid) begin
                        sda_out <= 1'b1;              // 低相位先回高
                    end
                    if (scl_hi_end) begin
                        sda_out <= 1'b1;
                        sda_en  <= 1'b0;              // 释放总线
                        if (reg_idx == REG_CNT-1)
                            state <= ST_DONE;         // 全部寄存器写完
                        else begin
                            reg_idx <= reg_idx + 1'b1;
                            state   <= ST_START1;     // 写下一个寄存器
                        end
                    end
                end

                // ---------- DONE ----------
                ST_DONE: begin
                    codec_ready <= 1'b1;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule

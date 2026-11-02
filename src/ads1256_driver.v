// AP01: transaction-specific SPI waits; no threshold/data-rate/pin change.
`timescale 1ns / 1ps
//====================================================================
// ads1256_driver  ADS1256 24bit 8通道 ADC 的 SPI 主机驱动
//--------------------------------------------------------------------
// 作用：上电配置 ADS1256 后，循环轮询 AIN0~AIN7（单端，AINCOM 为负），
//       每路 24bit 转换结果取【高 12 位】，8 路凑成 96bit，
//       一轮采完给一拍 adc_valid，正好喂给 c_interact_top.adc_p。
//
// 硬件：ADS1256 成品模块（板载 7.68MHz 晶振 + REF5025 基准 2.5V）
//
// SPI 时序（ADS1256 = SPI Mode 1，CPOL=0 / CPHA=1）：
//   - SCLK 空闲为低电平
//   - DIN(主机发) 在 SCLK 下降沿被 ADS1256 锁存
//   - DOUT(从机发) 在 SCLK 上升沿更新，主机在 SCLK 高电平中点采样
//   - 数据位序：MSB first，每个字节 8 个 SCLK
//   - RDATA 后读数据前满足 t6≈6.51us（取7us）；其他等待按事务区分
//
// SCLK 频率：50MHz / 32 = 1.5625MHz（< ADS1256 上限 1.92MHz，安全）
//
// 多通道单端轮询顺序（每通道）：
//   CS低 → WREG MUX(ch) → SYNC → WAKEUP → CS高 → 等 DRDY 变低
//        → CS低 → RDATA → t6 → 连续读 3 字节(24bit) → CS高
//
// 关键参数（模块晶振 7.68MHz，tCLKIN=130ns）：
//   t6  命令间隔 = 50 tCLKIN = 6.5us   → 取 7us
//   上电硬件复位低电平保持 1ms，复位后再等 1ms
//   SELFCAL 自校准后固定等 100ms
//   DRATE=0xF0 = 30000 SPS（转换周期约 33us）。
//   注意：SYNC/WAKEUP 后数字滤波器稳定时间 t18 = 210us（手册 Table 13，30kSPS），
//   DRDY 必须等它拉低才能读；超时保护取 1000us（约 5 倍 t18，覆盖批次/温度离散，
//   正常 DRDY 约 210us 就拉低被检测到，不会真等满，故不拖慢正常采样）。
//====================================================================
module ads1256_driver #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer CH_NUM      = 8,        // 通道数
    parameter integer ADC_W       = 12,       // 每路输出位宽（24bit 取高12位）
    parameter integer SCLK_DIV    = 32,       // SCLK 分频系数（整周期）
    parameter integer FAST_TIMING = 1,       // 0 reproduces the r5q 7us-per-byte schedule for A/B simulation
    parameter integer CAL_WAIT_US = 100_000   // 自校准后等待时长(us)，默认100ms；仿真可缩短
)(
    input  wire                    clk,       // 50MHz 主时钟
    input  wire                    rst_n,     // 低电平复位

    // ---- 物理引脚（到 ADS1256 模块）----
    output reg                     ads_sclk,  // SCLK（空闲低）
    output reg                     ads_mosi,  // DIN（FPGA→ADS1256）
    input  wire                    ads_miso,  // DOUT（ADS1256→FPGA）
    output reg                     ads_cs_n,  // CS 片选（低有效）
    input  wire                    ads_drdy,  // DRDY 数据就绪（低有效；模块若复用DOUT，则把此脚接miso）
    output reg                     ads_reset_n,// RESET 复位（低有效，复位 ADS1256）

    // ---- 采样输出（到 c_interact_top）----
    output reg  [CH_NUM*ADC_W-1:0] adc_data,  // 8路×12bit，路0在最低段
    output reg                     adc_valid, // 1 拍脉冲：本轮 8 路数据已更新
    // ---- 逐通道立即输出（审阅报告 #5：避免"等整轮打包"多出的 0~2.6ms）----
    output reg                     ch_valid,  // 每采完一路给 1 拍
    output reg  [2:0]              ch_idx,    // 该路的通道号
    output reg  [ADC_W-1:0]        ch_data    // 该路数据
);

    //================================================================
    // 一、时间常量（按 50MHz 计数）
    //================================================================
    localparam integer US          = CLK_FREQ_HZ / 1_000_000;     // 每微秒时钟数 = 50
    localparam integer T6_CLKS     = 7 * US;      // 7us  = 350
    localparam integer RST_CLKS    = 1000 * US;   // 1ms  = 50000
    localparam integer CAL_CLKS    = CAL_WAIT_US * US;// 自校准等待
    localparam integer CMD_CLKS    = 1 * US;   // >=4 CLKIN at 7.68MHz
    localparam integer SYNC_CLKS   = 4 * US;   // >=24 CLKIN before WAKEUP
    localparam integer CS_CLKS     = 2 * US;   // >=8 CLKIN before CS high
    localparam integer ACAL_CLKS   = 5000 * US;      // 自动校准等待 5ms（30kSPS 只需几百 us）
    localparam integer DRDY_TIMEOUT= 1000 * US;   // 1ms recovery deadline; normal conversions finish on a real DRDY high->low.
                                                  // Timeout skips RDATA/publication; it is not a conversion-ready substitute.

    //================================================================
    // 二、ADS1256 命令与寄存器地址
    //================================================================
    localparam [7:0] CMD_WAKEUP  = 8'h00;
    localparam [7:0] CMD_RDATA   = 8'h01;  // 读一次转换数据
    localparam [7:0] CMD_SDATAC  = 8'h0F;  // 退出连续读模式
    localparam [7:0] CMD_WREG    = 8'h50;  // 写寄存器（+地址）
    localparam [7:0] CMD_SELFCAL = 8'hF0;  // 自校准
    localparam [7:0] CMD_SYNC    = 8'hFC;  // 同步转换
    localparam [7:0] CMD_RESET   = 8'hFE;  // 软复位（本驱动用硬件复位）

    localparam [2:0] REG_STATUS  = 3'h0;
    localparam [2:0] REG_MUX     = 3'h1;
    localparam [2:0] REG_ADCON   = 3'h2;
    localparam [2:0] REG_DRATE   = 3'h3;

    // 寄存器配置值
    // STATUS=0x02：bit1 BUFEN=1，bit2 ACAL=0；随后显式SELFCAL
    localparam [7:0] VAL_STATUS  = 8'h02;   // 只开 BUFEN，不启动自动校准（ACAL=0）
    // ADCON=0x00：PGA 增益=1（bit[2:0]=000），CLKOUT 关闭
    localparam [7:0] VAL_ADCON   = 8'h00;
    // DRATE=0xF0：30000 SPS（高速，保证 8 路轮询后仍能抓到 FSR 力度峰值）
    localparam [7:0] VAL_DRATE   = 8'hF0;
    // MUX：[7:4] 正输入通道，[3:0] 负输入通道=8(AINCOM) → 单端

    //================================================================
    // 三、SPI 字节收发引擎（Mode1，MSB first）
    //   主状态机给 byte_start 一个脉冲并把字节放 byte_tx，
    //   引擎用 8 个 SCLK 把它移出，同时把 miso 上的 8 位移进 byte_rx，
    //   完成后 byte_done 给一个脉冲。
    //================================================================
    localparam integer HALF = SCLK_DIV / 2;     // SCLK 半周期 = 16 个 clk

    reg        byte_start;
    reg [7:0]  byte_tx;
    reg [7:0]  byte_rx;
    reg        byte_done;

    reg [2:0]  bitcnt;       // 当前位（7→0）
    reg [5:0]  half;         // 半周期内计数（0~15，6bit 够）
    reg [1:0]  sp;           // 字节引擎小状态：0空闲 1低相 2高相 3完成
    reg [1:0]  end_cnt;      // 字节结束后的保持计数（保证 t11 ≥ 50ns）

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ads_sclk  <= 1'b0;          // 空闲低（CPOL=0）
            ads_mosi  <= 1'b1;
            byte_rx   <= 8'd0;
            byte_done <= 1'b0;
            bitcnt    <= 3'd0;
            half      <= 6'd0;
            sp        <= 2'd0;
            end_cnt   <= 2'd0;
        end else begin
            byte_done <= 1'b0;          // 默认拉低
            case (sp)
                // ---------- 空闲，等主状态机发起 ----------
                2'd0: begin
                    ads_sclk <= 1'b0;
                    if (byte_start) begin
                        ads_mosi <= byte_tx[7];   // 先把 MSB 放上（sclk低期间）
                        bitcnt   <= 3'd7;
                        half     <= 6'd0;
                        sp       <= 2'd1;
                    end else begin
                        ads_mosi <= 1'b1;         // 空闲时 DIN 保持高
                    end
                end

                // ---------- 低相位（sclk=0）：放下一位，等上升沿 ----------
                2'd1: begin
                    ads_sclk <= 1'b0;
                    // 【2026-10-26 修】ADS1256 要求 SCLK 下降沿之后 DIN 至少保持
                    //   t5=50ns。原来一进低相位就改 DIN，实测只保持了约 40ns。
                    //   这里等 3 拍（60ns）之后再更新，保证大于 50ns。
                    if (half >= 6'd3) ads_mosi <= byte_tx[bitcnt];
                    if (half == HALF-1) begin
                        half     <= 6'd0;
                        ads_sclk <= 1'b1;         // 上升沿
                        sp       <= 2'd2;
                    end else half <= half + 6'd1;
                end

                // ---------- 高相位（sclk=1）：中点采样，再下降沿 ----------
                2'd2: begin
                    ads_sclk <= 1'b1;
                    if (half == (HALF/2 - 1))
                        byte_rx[bitcnt] <= ads_miso; // 高电平中点采样 DOUT
                    if (half == HALF-1) begin
                        half     <= 6'd0;
                        ads_sclk <= 1'b0;            // 下降沿（芯片锁存DIN/更新DOUT）
                        if (bitcnt == 3'd0) sp <= 2'd3;
                        else begin
                            bitcnt <= bitcnt - 3'd1;
                            sp     <= 2'd1;
                        end
                    end else half <= half + 6'd1;
                end

                // ---------- 一字节完成 ----------
                //   【2026-10-27 修】最后一个 SCLK 下降沿之后，下一个字节会在
                //   state 0 里立刻改 MOSI，间隔只有 ~40ns，仍低于 ADS1256
                //   要求的 t5=50ns。这里先空等 3 拍（60ns）再发 byte_done。
                2'd3: begin
                    ads_sclk <= 1'b0;
                    if (end_cnt < 2'd3) begin
                        end_cnt <= end_cnt + 2'd1;
                    end else begin
                        end_cnt   <= 2'd0;
                        byte_done <= 1'b1;
                        sp        <= 2'd0;
                    end
                end
            endcase
        end
    end

    //================================================================
    // 四、主状态机
    //================================================================
    // 状态编码
    localparam [5:0]
        S_RST_LOW   = 6'd0,    // 硬件复位拉低
        S_RST_WAIT  = 6'd1,    // 复位释放后等待
        S_SDATAC    = 6'd2,    // 发 SDATAC
        S_WS_CMD    = 6'd3,    // 写 STATUS：命令字节
        S_WS_CNT    = 6'd4,    //           数量字节
        S_WS_DAT    = 6'd5,    //           数据字节
        S_WM_CMD    = 6'd6,    // 写 MUX
        S_WM_CNT    = 6'd7,
        S_WM_DAT    = 6'd8,
        S_WA_CMD    = 6'd9,    // 写 ADCON
        S_WA_CNT    = 6'd10,
        S_WA_DAT    = 6'd11,
        S_WD_CMD    = 6'd12,   // 写 DRATE
        S_WD_CNT    = 6'd13,
        S_WD_DAT    = 6'd14,
        S_CAL       = 6'd15,   // 发 SELFCAL
        S_CAL_WAIT  = 6'd16,   // 等校准
        S_CHM_CMD   = 6'd17,   // 通道：写 MUX
        S_CHM_CNT   = 6'd18,
        S_CHM_DAT   = 6'd19,
        S_CH_SYNC   = 6'd20,   // SYNC
        S_CH_WAKE   = 6'd21,   // WAKEUP
        S_CH_DRDY   = 6'd22,   // 等 DRDY
        S_CH_RDATA  = 6'd23,   // RDATA
        S_CH_T6     = 6'd24,   // RDATA 后 t6
        S_CH_RD1    = 6'd25,   // 读 24bit 字节1
        S_CH_RD2    = 6'd26,
        S_CH_RD3    = 6'd27,
        S_CH_STORE  = 6'd28,   // 存本通道
        S_EMIT      = 6'd29,   // 8 路采完，发 valid
        S_BUSY      = 6'd30,   // 等一个字节收发完成
        S_GAP       = 6'd31,   // 命令间隔 t6
        S_SWRST     = 6'd32,   // 软件复位 0xFE（兼容无 RESET 脚的模块）
        S_SWRST_WAIT= 6'd33,   // 软复位后等 t11
        S_ACAL_WAIT = 6'd34;   // 等自动校准（STATUS 写入后）

    reg        rd_ok;         // 本路数据是否真的等到 DRDY（1=可信）
    reg        drdy_high_seen;// 本轮是否见过 DRDY 高电平（防止读到上一轮的旧低电平）
    reg [5:0]  state;
    reg [5:0]  after_byte;    // 本字节完成后的下一状态
    localparam integer GAP_W = $clog2(T6_CLKS+1);
    reg [GAP_W-1:0] gap_clks;
    localparam integer DL_MAX_A=CAL_CLKS>ACAL_CLKS?CAL_CLKS:ACAL_CLKS;
    localparam integer DL_MAX_B=RST_CLKS>DRDY_TIMEOUT?RST_CLKS:DRDY_TIMEOUT;
    localparam integer DL_MAX=DL_MAX_A>DL_MAX_B?DL_MAX_A:DL_MAX_B;
    localparam integer DLY_W=DL_MAX>0?$clog2(DL_MAX+1):1;
    reg [DLY_W-1:0] dly; // Bounded timer, identical protocol intervals
    reg [2:0]  ch;            // 当前通道 0~7
    reg [7:0]  rx_b1, rx_b2, rx_b3;   // 读回的 3 字节
    reg [1:0]  rx_sel;        // 本次读字节存入哪：0不存 1→b1 2→b2 3→b3
    reg [CH_NUM*ADC_W-1:0] ch_buf;    // 8 路结果缓存

    //================================================================
    // DRDY 异步输入两级同步（ADS1256 在 7.68MHz 晶振域，FPGA 在 50MHz 域）：
    //   外部 DRDY 是异步信号，直接进状态机判断有亚稳态风险，打两拍同步。
    //   复位初值取 1（DRDY 空闲为高电平 = 未就绪）。
    //================================================================
    reg drdy_s1, drdy_s2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            drdy_s1 <= 1'b1;
            drdy_s2 <= 1'b1;
        end else begin
            drdy_s1 <= ads_drdy;
            drdy_s2 <= drdy_s1;
        end
    end

    // 当前通道的 MUX 值：bit7=0, bit[6:4]=正输入通道, bit[3:0]=8(AINCOM)
    wire [7:0] mux_val = {1'b0, ch, 4'h8};

    // ADS1256 timing is per command/transaction, not per arbitrary byte.
    // Multi-byte WREG and the three result bytes may be contiguous.
    // The byte engine still guarantees DIN hold >=50ns between all bytes.
    function [GAP_W-1:0] next_gap;
        input [5:0] target;
        begin
            case(target)
                S_WS_CNT,S_WS_DAT,S_WM_CNT,S_WM_DAT,
                S_WA_CNT,S_WA_DAT,S_WD_CNT,S_WD_DAT,
                S_CHM_CNT,S_CHM_DAT,S_CH_RD2,S_CH_RD3,S_CH_T6: next_gap=0;
                S_CH_WAKE: next_gap=SYNC_CLKS;
                S_CH_DRDY,S_CH_STORE,S_SWRST_WAIT,S_CAL_WAIT: next_gap=CS_CLKS;
                default: next_gap=CMD_CLKS;
            endcase
        end
    endfunction

    // 便捷任务式宏：在每个"发字节状态"里统一用这组信号
    // （Verilog 里用 always 显式实现）
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_RST_LOW;
            ads_cs_n    <= 1'b1;
            ads_reset_n <= 1'b0;        // 上电先保持复位
            byte_start  <= 1'b0;
            // ads_mosi / ads_sclk 由字节引擎唯一驱动，复位值在那里给
            byte_tx     <= 8'h00;
            after_byte  <= S_SDATAC;
            gap_clks   <= T6_CLKS;
            dly         <= 32'd0;
            ch          <= 3'd0;
            rx_b1       <= 8'd0;
            rx_b2       <= 8'd0;
            rx_b3       <= 8'd0;
            rx_sel      <= 2'd0;
            ch_buf      <= {(CH_NUM*ADC_W){1'b0}};
            adc_data    <= {(CH_NUM*ADC_W){1'b0}};
            adc_valid   <= 1'b0;
            ch_valid    <= 1'b0;
            ch_idx      <= 3'd0;
            ch_data     <= {ADC_W{1'b0}};
            rd_ok       <= 1'b0;
            drdy_high_seen <= 1'b0;
        end else begin
            // 默认信号
            byte_start <= 1'b0;
            adc_valid  <= 1'b0;
            ch_valid   <= 1'b0;

            case (state)
                // ============ 上电硬件复位 ============
                S_RST_LOW: begin
                    ads_reset_n <= 1'b0;
                    ads_cs_n    <= 1'b1;
                    if (dly >= RST_CLKS-1) begin dly <= 0; state <= S_RST_WAIT; end
                    else dly <= dly + 32'd1;
                end
                S_RST_WAIT: begin
                    ads_reset_n <= 1'b1;       // 释放复位
                    ads_cs_n    <= 1'b1;
                    if (dly >= RST_CLKS-1) begin dly <= 0; state <= S_SWRST; end
                    else dly <= dly + 32'd1;
                end

                // ============ 软件复位（兼容没有 RESET 脚的模块）============
                //   有些 ADS1256 模块只引出 PDWN、没有 RESET，硬件复位对它无效；
                //   发一次 0xFE 软复位，保证芯片进入默认状态再初始化。
                //   对带 RESET 脚的模块也无害（复位→软复位→同样的默认值）。
                S_SWRST: begin
                    ads_cs_n   <= 1'b0;
                    byte_tx    <= CMD_RESET;
                    byte_start <= 1'b1;
                    rx_sel     <= 2'd0;
                    after_byte <= S_SWRST_WAIT;
                    state      <= S_BUSY;
                end
                S_SWRST_WAIT: begin
                    ads_cs_n <= 1'b1;
                    // t11 = 800µs（用 1ms 留余量）
                    if (dly >= RST_CLKS-1) begin dly <= 0; state <= S_SDATAC; end
                    else dly <= dly + 32'd1;
                end

                // ============ 退出连续读模式 ============
                S_SDATAC: begin
                    ads_cs_n   <= 1'b0;
                    byte_tx    <= CMD_SDATAC;
                    byte_start <= 1'b1;
                    rx_sel     <= 2'd0;
                    after_byte <= S_WS_CMD;
                    state      <= S_BUSY;
                end

                // ============ 写 STATUS = 0x02（BUFEN=1，ACAL=0） ============
                S_WS_CMD: begin
                    ads_cs_n   <= 1'b0;
                    byte_tx    <= CMD_WREG | {5'h00, REG_STATUS};
                    byte_start <= 1'b1; after_byte <= S_WS_CNT; state <= S_BUSY;
                end
                S_WS_CNT: begin
                    ads_cs_n   <= 1'b0;
                    byte_tx    <= 8'h00;          // 写 1 个寄存器（数量-1=0）
                    byte_start <= 1'b1; after_byte <= S_WS_DAT; state <= S_BUSY;
                end
                S_WS_DAT: begin
                    ads_cs_n   <= 1'b0;
                    byte_tx    <= VAL_STATUS;
                    byte_start <= 1'b1; after_byte <= S_WM_CMD; state <= S_BUSY;
                end

                // ============ 等自动校准结束 ============
                //   【2026-10-27 修】STATUS=0x06 会启动一次自动校准（ACAL 位），
                //   校准期间写寄存器会被忽略/破坏。原来写完 STATUS 约 12µs 就继续
                //   写 MUX/ADCON/DRATE，可能整段配置没生效 → 读回来的就是错的。
                //   这里等 5ms（30kSPS 下校准只需几百 µs，留足余量）。
                S_ACAL_WAIT: begin
                    ads_cs_n <= 1'b1;
                    if (dly >= ACAL_CLKS-1) begin dly <= 0; state <= S_WM_CMD; end
                    else dly <= dly + 32'd1;
                end

                // ============ 写 MUX（初始通道0）============
                S_WM_CMD: begin
                    ads_cs_n   <= 1'b0;
                    byte_tx    <= CMD_WREG | {5'h00, REG_MUX};
                    byte_start <= 1'b1; after_byte <= S_WM_CNT; state <= S_BUSY;
                end
                S_WM_CNT: begin
                    ads_cs_n   <= 1'b0;
                    byte_tx    <= 8'h00;
                    byte_start <= 1'b1; after_byte <= S_WM_DAT; state <= S_BUSY;
                end
                S_WM_DAT: begin
                    ads_cs_n   <= 1'b0;
                    byte_tx    <= 8'h08;          // 初始 AIN0 - AINCOM
                    byte_start <= 1'b1; after_byte <= S_WA_CMD; state <= S_BUSY;
                end

                // ============ 写 ADCON = 0x00（PGA=1）============
                S_WA_CMD: begin
                    ads_cs_n   <= 1'b0;
                    byte_tx    <= CMD_WREG | {5'h00, REG_ADCON};
                    byte_start <= 1'b1; after_byte <= S_WA_CNT; state <= S_BUSY;
                end
                S_WA_CNT: begin
                    ads_cs_n   <= 1'b0;
                    byte_tx    <= 8'h00;
                    byte_start <= 1'b1; after_byte <= S_WA_DAT; state <= S_BUSY;
                end
                S_WA_DAT: begin
                    ads_cs_n   <= 1'b0;
                    byte_tx    <= VAL_ADCON;
                    byte_start <= 1'b1; after_byte <= S_WD_CMD; state <= S_BUSY;
                end

                // ============ 写 DRATE = 0xF0（30k SPS）============
                S_WD_CMD: begin
                    ads_cs_n   <= 1'b0;
                    byte_tx    <= CMD_WREG | {5'h00, REG_DRATE};
                    byte_start <= 1'b1; after_byte <= S_WD_CNT; state <= S_BUSY;
                end
                S_WD_CNT: begin
                    ads_cs_n   <= 1'b0;
                    byte_tx    <= 8'h00;
                    byte_start <= 1'b1; after_byte <= S_WD_DAT; state <= S_BUSY;
                end
                S_WD_DAT: begin
                    ads_cs_n   <= 1'b0;
                    byte_tx    <= VAL_DRATE;
                    byte_start <= 1'b1; after_byte <= S_CAL; state <= S_BUSY;
                end

                // ============ 自校准 ============
                S_CAL: begin
                    ads_cs_n   <= 1'b0;
                    byte_tx    <= CMD_SELFCAL;
                    byte_start <= 1'b1; after_byte <= S_CAL_WAIT; state <= S_BUSY;
                end
                S_CAL_WAIT: begin
                    ads_cs_n <= 1'b1;
                    if (dly >= CAL_CLKS-1) begin dly <= 0; ch <= 3'd0; state <= S_CHM_CMD; end
                    else dly <= dly + 32'd1;
                end

                // ============ 通道循环：写 MUX(ch) ============
                S_CHM_CMD: begin
                    ads_cs_n   <= 1'b0;
                    byte_tx    <= CMD_WREG | {5'h00, REG_MUX};
                    byte_start <= 1'b1; after_byte <= S_CHM_CNT; state <= S_BUSY;
                end
                S_CHM_CNT: begin
                    ads_cs_n   <= 1'b0;
                    byte_tx    <= 8'h00;
                    byte_start <= 1'b1; after_byte <= S_CHM_DAT; state <= S_BUSY;
                end
                S_CHM_DAT: begin
                    ads_cs_n   <= 1'b0;
                    byte_tx    <= mux_val;       // 选择当前通道
                    byte_start <= 1'b1; after_byte <= S_CH_SYNC; state <= S_BUSY;
                end

                // ============ SYNC / WAKEUP 启动该通道转换 ============
                S_CH_SYNC: begin
                    ads_cs_n   <= 1'b0;
                    byte_tx    <= CMD_SYNC;
                    byte_start <= 1'b1; after_byte <= S_CH_WAKE; state <= S_BUSY;
                end
                S_CH_WAKE: begin
                    ads_cs_n   <= 1'b0;
                    byte_tx    <= CMD_WAKEUP;
                    byte_start <= 1'b1; after_byte <= S_CH_DRDY;
                    rx_sel     <= 2'd0;
                    drdy_high_seen <= 1'b0;   // 本轮重新开始看 DRDY
                    state      <= S_BUSY;
                end

                // ============ 等 DRDY 拉低（带超时）============
                //   采纳第 4 轮修复版的做法：必须先见到 DRDY 高电平，
                //   再见到低电平才算"新一轮转换完成"。否则 WAKEUP 后 DRDY
                //   可能停在上一轮的残留低电平，会读到旧数据。
                S_CH_DRDY: begin
                    ads_cs_n <= 1'b1;
                    if (drdy_s2 == 1'b1) drdy_high_seen <= 1'b1;
                    if (drdy_s2 == 1'b0 && drdy_high_seen) begin
                        rd_ok <= 1'b1;                       // 真等到（且是新一轮）才认为有效
                        dly   <= 0; state <= S_CH_RDATA;
                    end else if (dly >= DRDY_TIMEOUT-1) begin
                        rd_ok <= 1'b0;                       // Timeout: skip RDATA and publication.
                        dly   <= 0; state <= S_CH_STORE;
                    end else dly <= dly + 32'd1;
                end

                // ============ RDATA：请求读一次数据 ============
                S_CH_RDATA: begin
                    ads_cs_n   <= 1'b0;
                    byte_tx    <= CMD_RDATA;
                    byte_start <= 1'b1;
                    rx_sel     <= 2'd0;
                    after_byte <= S_CH_T6;
                    state      <= S_BUSY;
                end
                S_CH_T6: begin
                    ads_cs_n <= 1'b0;                       // CS 保持，等 t6
                    if (dly >= T6_CLKS-1) begin dly <= 0; state <= S_CH_RD1; end
                    else dly <= dly + 32'd1;
                end

                // ============ 读 3 字节（主机发 0xFF 提供时钟）============
                S_CH_RD1: begin
                    ads_cs_n   <= 1'b0;
                    byte_tx    <= 8'hFF;
                    byte_start <= 1'b1; rx_sel <= 2'd1; after_byte <= S_CH_RD2; state <= S_BUSY;
                end
                S_CH_RD2: begin
                    ads_cs_n   <= 1'b0;
                    byte_tx    <= 8'hFF;
                    byte_start <= 1'b1; rx_sel <= 2'd2; after_byte <= S_CH_RD3; state <= S_BUSY;
                end
                S_CH_RD3: begin
                    ads_cs_n   <= 1'b0;
                    byte_tx    <= 8'hFF;
                    byte_start <= 1'b1; rx_sel <= 2'd3; after_byte <= S_CH_STORE; state <= S_BUSY;
                end

                // ============ 存本通道高 12 位 ============
                S_CH_STORE: begin
                    ads_cs_n <= 1'b1;
                    // 24bit = {rx_b1(bit23..16), rx_b2(bit15..8), rx_b3(bit7..0)}，补码格式。
                    // 单端测量时 bit23 是符号位、正输入恒为 0，不能把它当数据位，
                    // 否则满量程只有 0x7FF(2047)、阈值口径全错。取有效最高 12 位 = bit22..11：
                    //   rx_b1 低 7 位(bit22..16) + rx_b2 高 5 位(bit15..11)，
                    //   PGA=1、VREF=2.5V时正量程约5V，1码≈5V/4096；BUFEN另有限幅。
                    // 负码钳位：bit23(rx_b1[7])=1 表示差分输入为负。FSR 单端电压只会
                    //   是 0~正，出现负码即代表该通道悬空/未接/异常（开 BUFEN 时未接输入
                    //   常被偏置成负），强制输出 0；否则悬空通道会被取成大正值而一直触发。
                    // 【2026-10-26 修】只有真的等到 DRDY 才采信这一路数据。
                    //   原来 DRDY 超时也照发，等于把"没转换完的垃圾"当有效采样，
                    //   下游拿它判按键 → 幽灵音。超时的时候保持旧值不动。
                    if (rd_ok) begin
                        ch_buf[ch*ADC_W +: ADC_W] <= rx_b1[7] ? {ADC_W{1'b0}}
                                                              : {rx_b1[6:0], rx_b2[7:3]};
                        // 逐通道立即输出：本路数据这一刻就交给压力检测，
                        //   不必等整轮 8 路打包完（省掉 0~2.6ms 的等待）
                        ch_data  <= rx_b1[7] ? {ADC_W{1'b0}} : {rx_b1[6:0], rx_b2[7:3]};
                        ch_idx   <= ch[2:0];
                        ch_valid <= 1'b1;
                    end
                    if (ch == CH_NUM-1) begin
                        ch <= 3'd0;
                        state <= S_EMIT;
                    end else begin
                        ch <= ch + 3'd1;
                        state <= S_CHM_CMD;
                    end
                end

                // ============ 一轮完成，打包输出并给 valid ============
                S_EMIT: begin
                    adc_data  <= ch_buf;
                    adc_valid <= 1'b1;       // 1 拍脉冲
                    state     <= S_CHM_CMD;
                end

                // ============ 字节收发：等引擎完成 ============
                S_BUSY: begin
                    if (byte_done) begin
                        case (rx_sel)
                            2'd1: rx_b1 <= byte_rx;
                            2'd2: rx_b2 <= byte_rx;
                            2'd3: rx_b3 <= byte_rx;
                            default: ;
                        endcase
                        // RDATA goes directly to its single t6 wait. WREG
                        // parameter/data bytes and result bytes need no t6.
                        gap_clks <= FAST_TIMING ? next_gap(after_byte) : T6_CLKS;
                        state <= (FAST_TIMING && next_gap(after_byte)==0) ? after_byte : S_GAP;
                        dly   <= 32'd0;
                    end
                end

                // ============ 字节间 t6 延时 ============
                S_GAP: begin
                    if (dly >= gap_clks-1) begin
                        dly   <= 32'd0;
                        state <= after_byte;
                    end else dly <= dly + 32'd1;
                end

                default: state <= S_RST_LOW;
            endcase
        end
    end

endmodule

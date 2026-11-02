//====================================================================
// pll_12m288.v —— 真实 PLL 包装（50 MHz → 12.264 MHz）
//
// IP Core Generator 生成的 Gowin_rPLL（GW5AST PLL_ADV）：
//   输入 50 MHz，输出 CLKOUT0 = 12.264 MHz（目标 12.288，误差 0.2%）
//   lock 信号由 gowin_pll.v 引出。
//====================================================================

module pll_12m288 (
    input  wire clk_50m,      // 板载 50MHz 主时钟（P16）
    output wire clk_12m288,    // ~12.288 MHz → 音频域主时钟
    output wire locked        // PLL 锁定（高有效）
);

    Gowin_rPLL u_pll (
        .clkin   (clk_50m),
        .init_clk(clk_50m),
        .clkout0 (clk_12m288),
        .lock    (locked)
    );

endmodule

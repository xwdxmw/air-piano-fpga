`timescale 1ns/1ps
// tb_lfo: ?? LFO ???? ?15 ???????????
module tb_lfo;
    reg clk = 0; always #10 clk = ~clk;
    reg rst_n = 0;
    reg mode = 1;
    reg req = 0; reg [16:0] pl = 0;
    wire ack, bclk, ws, dacdat, mclk, i2c_scl, codec_ready, pll_locked;
    wire [31:0] act; wire [15:0] mixd; wire i2c_sda;

    top_board #(.USE_ENGINE(1), .LFO_DIV(8)) dut(
        .clk_50m(clk), .rst_n(rst_n),
        .event_req(req), .event_payload(pl), .event_ack(ack),
        .mode(mode), .bend(7'd64),
        .bclk(bclk), .ws(ws), .dacdat(dacdat), .mclk(mclk),
        .i2c_sda(i2c_sda), .i2c_scl(i2c_scl), .codec_ready(codec_ready),
        .active_debug(act), .pcm_mix_debug(mixd), .pll_locked_o(pll_locked),
        .audio_clk_o(), .audio_rst_o(), .audio_tick_o(), .pcm_mon_o()
    );

    integer maxv = -999, minv = 999, k;
    initial begin
        #200 rst_n = 1;
        #50_000;
        // ? 400 ??8 ?/? ? 3200 ??????? +15 ? -15
        for (k = 0; k < 4000; k = k + 1) begin
            @(posedge dut.clk_12m288);
            if (dut.lfo_val > maxv) maxv = dut.lfo_val;
            if (dut.lfo_val < minv) minv = dut.lfo_val;
        end
        $display("LFO ?????%0d .. %0d  (???? -15..+15)", minv, maxv);
        if (maxv <= 15 && minv >= -15) $display("PASS: ??????");
        else                            $display("FAIL: ??");
        $finish;
    end
endmodule

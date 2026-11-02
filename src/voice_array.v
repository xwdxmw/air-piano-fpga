// ============================================================================
// voice_array.v —— 32 个 voice 音槽阵列
// ============================================================================

module voice_array #(
    parameter N = 32, EXTERNAL_NOTE_FREQ = 0
)(
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 sample_tick,
    input wire[N-1:0]diagnostic_v,flute_v,
    input  wire [N-1:0]         timbre_v,       // 每槽音色（起音时锁存）
    input  wire [N-1:0]         note_on_v,
    input wire [N*32-1:0] note_freq_v,
    input  wire [N*7-1:0]       note_num_v,
    input  wire [N*7-1:0]       velocity_v,
    input  wire [N-1:0]         note_release_v,
    input  wire [N-1:0]         vel_update_v,    // 每槽力度修正脉冲
    input  wire [N-1:0]         freq_update_v,   // 每槽实时变调脉冲
    input  wire [N*32-1:0]      new_freq_v,      // 每槽新频率控制字
    input  wire [6:0]           bend,            // 全局弯音
    input  wire [22:0]          vib_off,         // 颤音偏移（全局共用）
    output wire [N*16-1:0]      pcm_out_v,
    output wire [N*3-1:0]       ad_state_v
);

    genvar i;
    generate
        for (i = 0; i < N; i = i + 1) begin: g_voice
            voice #(.EXTERNAL_NOTE_FREQ(EXTERNAL_NOTE_FREQ)) u_voice (
                .clk        (clk),
                .rst_n      (rst_n),
                .sample_tick(sample_tick),
                .note_on    (note_on_v[i]),
                .note_num   (note_num_v[i*7 +: 7]),
                .note_freq(note_freq_v[i*32+:32]),
                .velocity   (velocity_v[i*7 +: 7]),
                .note_release(note_release_v[i]),
                .vel_update (vel_update_v[i]),
                .timbre_sel (timbre_v[i]),.diagnostic(diagnostic_v[i]),.flute_sel(flute_v[i]),
                .freq_update(freq_update_v[i]),
                .new_freq   (new_freq_v[i*32 +: 32]),
                .bend       (bend),
                .vib_off    (vib_off),
                .pcm_out    (pcm_out_v[i*16 +: 16]),
                .ad_state   (ad_state_v[i*3 +: 3])
            );
        end
    endgenerate

endmodule

// ============================================================================
// ap03_top_synth.v —— 合成引擎顶层
// ============================================================================

module ap03_top_synth #(
    parameter N = 32
)(
    input  wire              clk,
    input  wire              rst_n,
    input  wire              sample_tick,

    // ---- 事件总线（跨域后）----
    input  wire              event_valid,
    input  wire [1:0]        event_type,   // 00=NOTE_ON, 01=NOTE_OFF, 10=ANO
    input  wire [6:0]        event_num,
    input  wire [6:0]        event_vel,
    input  wire              event_timbre,
    input wire [1:0] event_source,
    input  wire              mode,
    input  wire [6:0]        bend,
    input  wire [22:0]       vib_off,     // 颤音偏移（在 top_board 里由 5Hz LFO 统一算好）

    // ---- 输出 ----
    output wire [N*16-1:0]   pcm_out_v,
    output wire [N-1:0]      active_debug
);

    wire note_on  = event_valid && (event_type == 2'b00);
    wire note_off = event_valid && (event_type == 2'b01);
    wire all_notes_off = event_valid && (event_type == 2'b10);
    wire vel_upd  = event_valid && (event_type == 2'b11);   // 力度修正

    wire[N-1:0]diagnostic_v,flute_v;
    wire [N-1:0]      note_on_v;
    wire [N*7-1:0]    note_num_v;
    wire [N*7-1:0]    velocity_v;
    wire [N-1:0]      timbre_v;
    wire [N-1:0]      note_release_v;
    wire [N-1:0]      vel_update_v;
    wire [N*3-1:0]    ad_state_v;

    // 实时变调：暂时接0（后面接控制逻辑）
    wire [N-1:0]      freq_update_v = {N{1'b0}};
    wire [N*32-1:0]   new_freq_v = {N*32{1'b0}};

    ap03_poly_mgr #(.N(N)) u_mgr (
        .clk(clk), .rst_n(rst_n), .sample_tick(sample_tick),
        .note_on(note_on), .note_num(event_num), .velocity(event_vel),
        .timbre(event_timbre),.source(event_source),
        .vel_upd(vel_upd), .vel_upd_num(event_num), .vel_upd_vel(event_vel),
        .note_off(note_off), .all_notes_off(all_notes_off),
        .ad_state_v(ad_state_v),
        .note_on_v(note_on_v), .note_num_v(note_num_v), .velocity_v(velocity_v),
        .timbre_v(timbre_v),
        .note_release_v(note_release_v), .vel_update_v(vel_update_v), .active(active_debug),.diagnostic_v(diagnostic_v),.flute_v(flute_v)
    );

    ap03_voice_array #(.N(N)) u_arr (
        .clk(clk), .rst_n(rst_n), .sample_tick(sample_tick),
        .timbre_v(timbre_v),.diagnostic_v(diagnostic_v),.flute_v(flute_v),
        .note_on_v(note_on_v), .note_num_v(note_num_v), .velocity_v(velocity_v),
        .note_release_v(note_release_v),
        .vel_update_v(vel_update_v),
        .freq_update_v(freq_update_v),
        .new_freq_v(new_freq_v),
        .bend(bend),
        .vib_off(vib_off),
        .pcm_out_v(pcm_out_v), .ad_state_v(ad_state_v)
    );

endmodule

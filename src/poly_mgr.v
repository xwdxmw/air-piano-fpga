// ============================================================================
// poly_mgr.v —— 复音管理器：按键事件 → 自动分配空闲音槽
// ============================================================================

module poly_mgr #(
    parameter N = 32
)(
    input  wire              clk,
    input  wire              rst_n,
    input  wire              sample_tick,
    input  wire              note_on,
    input wire [31:0] note_freq,
    input  wire [6:0]        note_num,
    input  wire [6:0]        velocity,
    input wire [1:0] source,
    input  wire              timbre,          // NOTE_ON时锁存的音色
    input  wire              vel_upd,         // 力度修正事件
    input  wire [6:0]        vel_upd_num,
    input  wire [6:0]        vel_upd_vel,
    input  wire              note_off,
    input  wire              all_notes_off,
    input  wire [N*3-1:0]    ad_state_v,
    output reg  [N-1:0]      note_on_v,
    output reg [N*32-1:0] note_freq_v,
    output reg  [N*7-1:0]    note_num_v,
    output reg  [N*7-1:0]    velocity_v,
    output reg  [N-1:0]      timbre_v,         // 每槽音色（起音时锁存）
    output reg  [N-1:0]      note_release_v,
    output reg  [N-1:0]      vel_update_v,     // 该槽的力度被修正
    output reg [N-1:0] diagnostic_v,
    output reg [N-1:0] flute_v, // latched keyboard flute, source0 only
    output wire [N-1:0]      active
);

    reg [6:0] slot_note [0:N-1];
    reg [1:0] slot_source[0:N-1];
    reg [N-1:0] active_r = 0;
    reg [N-1:0] started_r = 0;   // 该槽是否已被voice消费（离开IDLE）
    integer k;
    reg found;

    reg note_on_d, note_off_d, ano_d, vel_upd_d;
    wire note_on_rise  =  note_on  & ~note_on_d;
    wire note_off_rise =  note_off & ~note_off_d;
    wire ano_rise      =  all_notes_off & ~ano_d;
    wire vel_upd_rise  =  vel_upd & ~vel_upd_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            note_on_d  <= 1'b0;
            note_off_d <= 1'b0;
            ano_d      <= 1'b0;
            vel_upd_d  <= 1'b0;
        end else begin
            note_on_d  <= note_on;
            note_off_d <= note_off;
            ano_d      <= all_notes_off;
            vel_upd_d  <= vel_upd;
        end
    end

    assign active = active_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active_r     <= {N{1'b0}};
            started_r    <= {N{1'b0}};
            note_on_v    <= {N{1'b0}};
            note_release_v <= {N{1'b0}};
            timbre_v     <= {N{1'b0}};
            diagnostic_v <= 0;flute_v<=0;
            vel_update_v <= {N{1'b0}};
            velocity_v<=0;note_num_v<=0;note_freq_v<=0;
            for (k = 0; k < N; k = k + 1) begin slot_note[k] <= 7'd0;slot_source[k]<=0;end
        end else begin
            if (sample_tick) begin
                note_on_v    <= {N{1'b0}};
                vel_update_v <= {N{1'b0}};
            end

            // 力度修正：找到正在响这个音符的槽，更新力度并通知 voice
            if (vel_upd_rise) begin
                for (k = 0; k < N; k = k + 1) begin
                    if (active_r[k] && slot_note[k] == vel_upd_num && slot_source[k]==source) begin
                        velocity_v[k*7 +: 7] <= vel_upd_vel;
                        vel_update_v[k]      <= 1'b1;
                    end
                end
            end

            // 按下：找空闲槽，锁存音符+力度+音色
            found = 0;
            if (note_on_rise && velocity!=0) begin
                for (k = 0; k < N; k = k + 1) begin
                    if (!found && !active_r[k]) begin
                        found = 1;
                        active_r[k]        <= 1'b1;
                        started_r[k]       <= 1'b0;
                        slot_note[k]       <= note_num;
                        slot_source[k]     <= source;
                        note_num_v[k*7 +: 7] <= note_num;
                        note_freq_v[k*32+:32] <= note_freq;
                        velocity_v[k*7 +: 7] <= velocity;
                        diagnostic_v[k] <= (source==2'd2);
                        flute_v[k] <= (source==2'd0 && timbre);
                        timbre_v[k]        <= timbre;   // 锁存音色
                        note_on_v[k]       <= 1'b1;
                    end
                end
            end

            // 松开：找正在响这个音符的槽
            // A zero-velocity ON is a release, never a permanently silent slot.
            if (note_off_rise || (note_on_rise && velocity==0)) begin
                for (k = 0; k < N; k = k + 1) begin
                    if (active_r[k] && slot_note[k] == note_num && slot_source[k]==source) begin
                        note_release_v[k] <= 1'b1;
                    end
                end
            end

            // 全音符关断
            if (ano_rise) begin
                for (k = 0; k < N; k = k + 1) begin
                    if (active_r[k]) note_release_v[k] <= 1'b1;
                end
            end

            // 检测voice已起音（离开IDLE）
            for (k = 0; k < N; k = k + 1) begin
                if (active_r[k] && !started_r[k] && ad_state_v[k*3 +: 3] != 3'd0)
                    started_r[k] <= 1'b1;
            end

            // Bell/harp auto-retire on natural IDLE. Source2 diagnostics
            // retain sustained voices until explicit NOTE_OFF / ALL_OFF.
            for (k = 0; k < N; k = k + 1) begin
                if (started_r[k] && (ad_state_v[k*3 +: 3] == 3'd0) &&
                    (note_release_v[k] || timbre_v[k] || !diagnostic_v[k])) begin
                    note_release_v[k] <= 1'b0;
                    active_r[k]        <= 1'b0;
                    started_r[k]       <= 1'b0;diagnostic_v[k]<=0;flute_v[k]<=0;
                end
            end
        end
    end

endmodule

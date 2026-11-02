// r5m: four-mode keyboard bell and the unchanged optical harp.
// Source2 diagnostics retain a sustained single-oscillator ADSR test voice.
module voice_r5m_reference #(
    parameter SAMPLE_RATE = 48000,   // 采样率（仅记录，逻辑不依赖）
    parameter TABLE_SIZE  = 256,     // 正弦表长度
    parameter PCM_WIDTH   = 16,      // PCM 输出位宽
    parameter PHASE_WIDTH = 32       // 相位累加器位宽
)(
    input  wire                 clk,          // 系统时钟（如 27MHz）
    input  wire                 rst_n,        // 复位，低有效
    input  wire                 sample_tick,  // 48kHz 采样脉冲
    input  wire                 note_on,      // 触发脉冲（1 拍）
    input  wire [6:0]           note_num,     // 音符编号 0~127
    input  wire [6:0]           velocity,     // 力度 0~127
    input  wire                 note_release,      // 释放电平（1 = 松开）
    input  wire                 vel_update,    // 力度修正脉冲（NOTE_ON 后补发真实力度）
    input wire diagnostic, // latched per NOTE_ON; source2 continuous test tone
    input  wire                 timbre_sel, // 0=钟琴 1=竖琴（切换音色）
    input  wire                 freq_update,   // 实时变调脉冲：更新频率不重启包络
    input  wire [PHASE_WIDTH-1:0] new_freq,    // 新的频率控制字
    input  wire [6:0]           bend,          // 全局弯音：0~127，中心64=不变调
    input  wire [22:0]          vib_off,       // 颤音偏移（有符号，单位=相位字），全局共用
    output reg  [PCM_WIDTH-1:0] pcm_out,      // 16bit 有符号 PCM（含包络）
    output wire [2:0]           ad_state      // ADSR 状态（仿真/调试用）
);

    // Normal bell has an anti-click attack, independent modal decays and
    // key-release damping. Harp and sustained diagnostic ADSR remain from r5l.
    reg voice_timbre,voice_diagnostic;
    reg[2:0]legacy_ad_state;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin voice_timbre<=0;voice_diagnostic<=0;end
        else if(sample_tick && note_on)begin voice_timbre<=timbre_sel;voice_diagnostic<=diagnostic;end
    end

    wire [3:0] atk_sh = voice_timbre ? 4'd5  : 4'd6;
    wire [3:0] dec_sh = voice_timbre ? 4'd10 : 4'd10;
    wire [3:0] rel_sh = voice_timbre ? 4'd14 : (voice_diagnostic?4'd12:4'd13);
    // sustain 电平比例（Q15 定点常数）：
    //   钢琴 10/14≈0.7143 → sus_k=23406；竖琴 0.50 → sus_k=16384
    //   （竖琴 0.92 是 bug：差值与 peak 太接近，decay_step 移位后为 0）
    wire [15:0] sus_k = voice_timbre ? 16'd16384 : 16'd23406;

    // ==================== 1. 音符 → 频率控制字 查表 ====================
    // 128 个 MIDI 音符的频率控制字（@48kHz，32bit 相位累加器）
    // 综合版：case ROM 替代 $readmemh
    wire [PHASE_WIDTH-1:0] nf_val;
    note_freq_rom #(.D_WIDTH(PHASE_WIDTH), .A_WIDTH(7)) u_nf (
        .addr (note_num),
        .dout (nf_val)
    );

    reg [PHASE_WIDTH-1:0] base_freq;   // 基础频率（弯音叠加在上面）
    // Independent manual bend, using a per-note frequency ratio.
    // Frequency-proportional bend: approximately +/-2 semitones at every note.
    // One shared-address coefficient ROM; every voice keeps its own base frequency.
    function[16:0]bend_ratio;input[6:0]value;begin case(value)
            7'd0:bend_ratio=17'd58279;
            7'd1:bend_ratio=17'd58386;
            7'd2:bend_ratio=17'd58493;
            7'd3:bend_ratio=17'd58600;
            7'd4:bend_ratio=17'd58708;
            7'd5:bend_ratio=17'd58816;
            7'd6:bend_ratio=17'd58924;
            7'd7:bend_ratio=17'd59032;
            7'd8:bend_ratio=17'd59140;
            7'd9:bend_ratio=17'd59249;
            7'd10:bend_ratio=17'd59358;
            7'd11:bend_ratio=17'd59466;
            7'd12:bend_ratio=17'd59576;
            7'd13:bend_ratio=17'd59685;
            7'd14:bend_ratio=17'd59794;
            7'd15:bend_ratio=17'd59904;
            7'd16:bend_ratio=17'd60014;
            7'd17:bend_ratio=17'd60124;
            7'd18:bend_ratio=17'd60235;
            7'd19:bend_ratio=17'd60345;
            7'd20:bend_ratio=17'd60456;
            7'd21:bend_ratio=17'd60567;
            7'd22:bend_ratio=17'd60678;
            7'd23:bend_ratio=17'd60789;
            7'd24:bend_ratio=17'd60901;
            7'd25:bend_ratio=17'd61013;
            7'd26:bend_ratio=17'd61125;
            7'd27:bend_ratio=17'd61237;
            7'd28:bend_ratio=17'd61349;
            7'd29:bend_ratio=17'd61462;
            7'd30:bend_ratio=17'd61575;
            7'd31:bend_ratio=17'd61688;
            7'd32:bend_ratio=17'd61801;
            7'd33:bend_ratio=17'd61914;
            7'd34:bend_ratio=17'd62028;
            7'd35:bend_ratio=17'd62142;
            7'd36:bend_ratio=17'd62256;
            7'd37:bend_ratio=17'd62370;
            7'd38:bend_ratio=17'd62485;
            7'd39:bend_ratio=17'd62599;
            7'd40:bend_ratio=17'd62714;
            7'd41:bend_ratio=17'd62829;
            7'd42:bend_ratio=17'd62945;
            7'd43:bend_ratio=17'd63060;
            7'd44:bend_ratio=17'd63176;
            7'd45:bend_ratio=17'd63292;
            7'd46:bend_ratio=17'd63408;
            7'd47:bend_ratio=17'd63525;
            7'd48:bend_ratio=17'd63641;
            7'd49:bend_ratio=17'd63758;
            7'd50:bend_ratio=17'd63875;
            7'd51:bend_ratio=17'd63992;
            7'd52:bend_ratio=17'd64110;
            7'd53:bend_ratio=17'd64227;
            7'd54:bend_ratio=17'd64345;
            7'd55:bend_ratio=17'd64463;
            7'd56:bend_ratio=17'd64582;
            7'd57:bend_ratio=17'd64700;
            7'd58:bend_ratio=17'd64819;
            7'd59:bend_ratio=17'd64938;
            7'd60:bend_ratio=17'd65057;
            7'd61:bend_ratio=17'd65176;
            7'd62:bend_ratio=17'd65296;
            7'd63:bend_ratio=17'd65416;
            7'd64:bend_ratio=17'd65536;
            7'd65:bend_ratio=17'd65656;
            7'd66:bend_ratio=17'd65777;
            7'd67:bend_ratio=17'd65898;
            7'd68:bend_ratio=17'd66018;
            7'd69:bend_ratio=17'd66140;
            7'd70:bend_ratio=17'd66261;
            7'd71:bend_ratio=17'd66383;
            7'd72:bend_ratio=17'd66504;
            7'd73:bend_ratio=17'd66627;
            7'd74:bend_ratio=17'd66749;
            7'd75:bend_ratio=17'd66871;
            7'd76:bend_ratio=17'd66994;
            7'd77:bend_ratio=17'd67117;
            7'd78:bend_ratio=17'd67240;
            7'd79:bend_ratio=17'd67364;
            7'd80:bend_ratio=17'd67487;
            7'd81:bend_ratio=17'd67611;
            7'd82:bend_ratio=17'd67735;
            7'd83:bend_ratio=17'd67860;
            7'd84:bend_ratio=17'd67984;
            7'd85:bend_ratio=17'd68109;
            7'd86:bend_ratio=17'd68234;
            7'd87:bend_ratio=17'd68359;
            7'd88:bend_ratio=17'd68485;
            7'd89:bend_ratio=17'd68610;
            7'd90:bend_ratio=17'd68736;
            7'd91:bend_ratio=17'd68862;
            7'd92:bend_ratio=17'd68989;
            7'd93:bend_ratio=17'd69115;
            7'd94:bend_ratio=17'd69242;
            7'd95:bend_ratio=17'd69369;
            7'd96:bend_ratio=17'd69497;
            7'd97:bend_ratio=17'd69624;
            7'd98:bend_ratio=17'd69752;
            7'd99:bend_ratio=17'd69880;
            7'd100:bend_ratio=17'd70008;
            7'd101:bend_ratio=17'd70137;
            7'd102:bend_ratio=17'd70266;
            7'd103:bend_ratio=17'd70394;
            7'd104:bend_ratio=17'd70524;
            7'd105:bend_ratio=17'd70653;
            7'd106:bend_ratio=17'd70783;
            7'd107:bend_ratio=17'd70913;
            7'd108:bend_ratio=17'd71043;
            7'd109:bend_ratio=17'd71173;
            7'd110:bend_ratio=17'd71304;
            7'd111:bend_ratio=17'd71435;
            7'd112:bend_ratio=17'd71566;
            7'd113:bend_ratio=17'd71697;
            7'd114:bend_ratio=17'd71829;
            7'd115:bend_ratio=17'd71961;
            7'd116:bend_ratio=17'd72093;
            7'd117:bend_ratio=17'd72225;
            7'd118:bend_ratio=17'd72358;
            7'd119:bend_ratio=17'd72490;
            7'd120:bend_ratio=17'd72623;
            7'd121:bend_ratio=17'd72757;
            7'd122:bend_ratio=17'd72890;
            7'd123:bend_ratio=17'd73024;
            7'd124:bend_ratio=17'd73158;
            7'd125:bend_ratio=17'd73292;
            7'd126:bend_ratio=17'd73427;
            7'd127:bend_ratio=17'd73562;
            default:bend_ratio=17'd65536;
        endcase end endfunction
    wire[16:0]ratio=voice_timbre?17'd65536:bend_ratio(bend);
    wire[48:0]scaled_freq=base_freq*ratio;
    wire signed[33:0]freq_sum=$signed({1'b0,scaled_freq[48:16]})+
                              {{11{vib_off[22]}},vib_off};
    // Clamp instead of modulo wrap at extreme custom pitches and negative offsets.
    wire[31:0]freq_with_bend=freq_sum<1?32'd1:
        freq_sum > 34'sd1932735283 ? 32'h73333333 : freq_sum[31:0];
    // ====================================================================

    // ==================== 2. 振荡器：复用 osc.v ====================
    wire [PCM_WIDTH-1:0] osc_pcm;
    osc #(
        .DATA_WIDTH (PCM_WIDTH),
        .TABLE_SIZE (TABLE_SIZE),
        .PHASE_WIDTH(PHASE_WIDTH)
    ) u_osc (
        .clk         (clk),
        .rst_n       (rst_n),
        .sample_tick (sample_tick),
        .freq_ctrl   (freq_with_bend),
        .pcm_out     (osc_pcm)
    );
    // ====================================================================

    // ==================== 3. ADSR 包络状态机 ====================
    localparam [2:0] IDLE=3'd0, ATTACK=3'd1, DECAY=3'd2, SUSTAIN=3'd3, RELEASE=3'd4;

    reg [2:0]  state;
    reg [15:0] env;           // 包络值 0~32767（定点表示 0.0 ~ 1.0）
    reg [15:0] peak;          // 本音峰值 = 力度映射（velocity × 258，最大 32766）
    reg [15:0] sustain_lvl;   // sustain 电平 ≈ peak × 0.71（钢琴）/ ×0.50（竖琴）
    reg        calc_q;        // 流水挂起：note_on 后下一拍才算 sustain_lvl（切断长组合链）

    // 各段每采样步进（常数移位替代除法，组合路径仅 1 级；时长 = 2^shift 采样）
    wire [15:0] attack_raw = peak >> atk_sh;
    wire [15:0] attack_step = attack_raw==0?16'd1:attack_raw;
    wire [15:0] decay_raw = (peak>sustain_lvl)?((peak-sustain_lvl)>>dec_sh):16'd0;
    wire [15:0] decay_step = decay_raw==0?16'd1:decay_raw;
    // 【注意】release 步进用"满幅/时长"的固定移位，不能用 env/时长：
    //   若 env 变小，步进会取整成 0，导致 Release 卡死永不归零。
    wire [15:0] release_step = 16'd32767 >> rel_sh;

    // sustain_lvl 的流水计算（peak 已在 note_on 拍锁存，此处为单个常数乘法，路径短）
    wire [31:0] sus_prod = peak * sus_k;   // Q15：结果取高半段 [30:15]

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= IDLE;
            env         <= 16'd0;
            peak        <= 16'd0;
            sustain_lvl <= 16'd0;
            base_freq   <= 32'd0;
            calc_q      <= 1'b0;
            legacy_ad_state <= IDLE;
        end else if (sample_tick) begin
            // One priority chain: do not let the old-state case override NOTE_ON.
            if(note_on)begin
                base_freq<=nf_val;peak<=velocity*16'd258;env<=0;state<=ATTACK;calc_q<=1;
            end else begin
                if(freq_update && state!=IDLE)base_freq<=new_freq;
                if(bell_normal && !bell_alive && !calc_q)begin state<=IDLE;env<=0;end
                else if(vel_update && state!=IDLE)begin peak<=velocity*16'd258;calc_q<=1;end
                else if(calc_q)begin
                    sustain_lvl<=sus_prod[30:15];calc_q<=0;
                    if(env>peak)env<=peak;
                    if(note_release && state!=IDLE)state<=RELEASE;
                end else case(state)
                    IDLE:env<=0;
                    ATTACK:begin
                        if(note_release)state<=RELEASE;
                        else if({1'b0,env}+{1'b0,attack_step}>=peak)begin env<=peak;state<=DECAY;end
                        else env<=env+attack_step;
                    end
                    DECAY:begin
                        if(note_release)state<=RELEASE;
                        else if(env<=sustain_lvl || env-sustain_lvl<=decay_step)begin
                            env<=sustain_lvl;state<=voice_timbre?RELEASE:SUSTAIN;
                        end else env<=env-decay_step;
                    end
                    SUSTAIN:begin if(note_release)state<=RELEASE;end
                    RELEASE:begin if(env<=release_step)begin env<=0;state<=IDLE;end else env<=env-release_step;end
                    default:begin env<=0;state<=IDLE;end
                endcase
            end

            legacy_ad_state <= state;                          // 状态输出（给仿真/顶层看）
        end
    end
    // ====================================================================

    // Harp uses the original rectified sine. The old clipped sine is retained
    // only for sustained diagnostic mode. Normal keyboard uses bell_bank.
    wire signed [16:0] osc_s   = $signed(osc_pcm);
    wire               clip_en = (state == ATTACK) || (state == DECAY);
    wire signed [17:0] clip_th = 18'sd3000 + {2'b00, env};      // 3000 + env
    wire signed [17:0] osc_x   = $signed(osc_pcm);

    wire signed [17:0] wave_test = (!clip_en) ? osc_x :
        (osc_x >  clip_th) ?  clip_th :
        (osc_x < -clip_th) ? -clip_th : osc_x;

    wire signed [17:0] wave_harp =
        (osc_x > 0) ? (osc_x - 18'sd10430) : -18'sd10430;

    wire bell_normal=!voice_timbre && !voice_diagnostic;
    wire signed[17:0]wave_bell;wire bell_alive;
    bell_bank u_bell(.clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),
      .start(note_on && velocity!=0 && !timbre_sel && !diagnostic),
      .clear((note_on && (timbre_sel || diagnostic || velocity==0)) || (bell_normal && state==IDLE && !note_on)),
      .freq_ctrl(freq_with_bend),.wave(wave_bell),.alive(bell_alive));
    assign ad_state=(bell_normal && !bell_alive)?3'd0:legacy_ad_state;
    wire signed [17:0] wave = voice_timbre ? wave_harp : (voice_diagnostic?wave_test:wave_bell);

    // wave(有符号) × env(0~32767 = 0.0~1.0)，右移 15 位回到 16bit 幅度
    wire signed [34:0] prod = wave * $signed({1'b0, env});

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)      pcm_out <= 16'd0;
        else if (sample_tick) pcm_out <= (bell_normal && !bell_alive)?16'd0:prod[30:15];
    end

endmodule


# Clock constraint: onboard 50 MHz oscillator, period = 20 ns
create_clock -name clk_50m -period 20.000 [get_ports {clk_50m}]

# 跨时钟域(CDC)约束：50MHz 交互域(clk_50m：事件产生/队列/握手)与
# PLL 12.264MHz 音频域(PLL_inst/CLKOUT0.default_gen_clk：引擎/混音/I2S)是两个独立时钟域。
# 说明：PLL 自动生成时钟(.default_gen_clk)在 SDC 解析期尚未注册，无法用
# set_clock_groups 按名字引用；因此改为在跨域“第一级同步触发器”的 D 端直接
# set_false_path（同时切断 setup/hold，功能等价于异步时钟组）。
# 跨域路径（已与 P&R 报告逐条核对）：
#   50M→音频：ev_payload → u_board/pl1、ev_req → u_board/req1（双 DFF 第一级）
#   50M→音频：bend(弯音) → u_board/bend1（弯音双 DFF 第一级，共 7 bit）
#   50M→音频：mode(TTP 颤音开关) → u_board/mode_s1_s0（双 DFF 第一级，综合后自动重命名）
#   音频→50M：u_board/ack_r → ack1（top_system 内双 DFF 第一级）
# 不写反斜杠续行(Gowin SDC 不支持)。
set_false_path -to [get_pins {u_board/pl1_*/D}]
set_false_path -to [get_pins {u_board/req1_s0/D}]
set_false_path -to [get_pins {u_board/bend1_*/D}]
set_false_path -to [get_pins {u_board/mode_s1_s0/D}]
set_false_path -to [get_pins {ack1_s0/D}]

# Frozen scope snapshot toggle synchronizers, first stage only.
set_false_path -to [get_pins {u_lcd/u_scope/req_meta_s0/D}]
set_false_path -to [get_pins {u_lcd/u_scope/ack_meta_s0/D}]

# Spectrum snapshot request/ack synchronizers, first stage only.
set_false_path -to [get_pins {u_lcd/u_spectrum/req_meta_s0/D}]
set_false_path -to [get_pins {u_lcd/u_spectrum/ack_meta_s0/D}]
# Only the FIRST data synchronizer is asynchronous. Subsequent data_sync/bars
# paths retain normal 50MHz timing checks; source snapshot held until next req.
set_false_path -to [get_pins {u_lcd/u_spectrum/data_meta_*/D}]

# PLL lock is asynchronous to the audio clock. These TWO FFs are the
# async-assert/sync-deassert reset synchronizer, not functional data endpoints.
# Exempt only their asynchronous CLEAR inputs. Their D chain and every
# downstream reset recovery/removal path remain timed. See SUG940 section5.4.1.
set_false_path -to [get_pins {u_board/audio_rst_sync_0_s0/CLEAR}]
set_false_path -to [get_pins {u_board/audio_rst_sync_1_s0/CLEAR}]

# Coherent voice-activity snapshot: first synchronizer stages only.
# Source holds the full mask until request/acknowledge completes.
set_false_path -to [get_pins {u_lcd/u_voices/req_meta_s0/D}]
set_false_path -to [get_pins {u_lcd/u_voices/ack_meta_s0/D}]
set_false_path -to [get_pins {u_lcd/u_voices/alive_meta_s0/D}]
set_false_path -to [get_pins {u_lcd/u_voices/data_meta_*/D}]

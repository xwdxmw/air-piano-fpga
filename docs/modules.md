# 当前、可选与历史模块

## AP04 默认调用链

```text
top_system
 ├─ ads1256_driver → c_interact_top
 │                    ├─ pressure_zero / pressure_detect → pressure_key → force_map
 │                    ├─ optical_harp / c_sync_debounce
 │                    └─ cap_touch / c_to_voice_adapter
 ├─ boot_select / ttp_gestures / performance_controls / note_transpose
 ├─ guide_seq / poly32_seq / event_queue_multi
 ├─ top_board
 │   ├─ pll_12m288 → gowin_pll/ 厂商 IP
 │   ├─ top_synth → note_freq_rom / poly_mgr / voice_array → voice
 │   │                                            └─ bell_bank / flute_bank / sine_rom
 │   └─ mixer → delay_fx → pt8211_tx
 └─ lcd_panel / scope_cap / spectrum16 / voice_status_snapshot
     live_led_follow / guide_led_map / led_startup_test / ws2812_tx
```

`voice` 定义在 voice_synth.v。图示为主要功能关系，不替代完整网表；同名文件存在并不意味着其全部参数分支都在默认硬件中实例化。

## 保留的可选分支

| 模块 | 默认 AP04 状态 |
|---|---|
| standard_i2s_tx | STANDARD_I2S=0，默认不启用；外接标准 I2S DAC 分支，不可直接改开后仍接板载 PT8211 |
| codec_init | USE_PT8211=1，默认不启用外接 Codec 的 I2C 配置 |
| optical_calib / optical_quantize | USE_ADC=0，红外默认走 GPIO；ADC 红外分支保留 |
| demo_seq | USE_DEMO=0，默认普通演奏；演示序列分支保留 |

这些模块仍被参数分支引用，保留在 src/。当前引脚、参数和 Tcl 构建选项沿用 AP04。

## 前期分工与沿用

团队已确认前期按 A 合成引擎、B 时钟/输出/集成、C 传感/交互推进。AP04 沿用并改进了这些模块。后续加入钟琴、笛子、来源隔离、可信采样、队列、显示及等价优化；不能把初期分工直接当作每次后续修改的作者证明。

三个不在当前调用链的早期 RTL 移到 ../legacy/rtl/；20 个历史测试移到 ../tests/legacy/。`src/osc_synth.v` 定义当前仍调用的 `osc`，保留在主线。逐文件路径和哈希见 ../SOURCE_LAYOUT.json。

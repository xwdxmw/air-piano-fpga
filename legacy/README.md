# 历史 RTL

此处保存已不在 AP04 当前主线调用链中的模块。文件内容保留，不列入 `air_piano.gprj`，不与当前发送器拼接使用。

| 文件 | 当前状态与替代 |
|---|---|
| rtl/clk_div.v | 早期音频时钟分频；当前 PT8211 发送器自行产生位时钟、WS 和 sample_tick |
| rtl/i2s_tx.v | 早期发送器；主线使用 src/pt8211_tx.v，可选标准 I2S 使用 src/standard_i2s_tx.v |
| rtl/mixer_ref.v | 早期参考混音器；主线使用 src/mixer.v；它也不是当前 60 项回归的参考依赖 |

早期测试平台在 ../tests/legacy/；当前回归需要的参考实现留在 ../tests/，不可当作“无用文件”删除。

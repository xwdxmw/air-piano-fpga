# Air Piano — 基于 FPGA 的多维交互多音色电子乐器
面向实时音乐交互的纯硬件电子乐器：八路压力琴键、八路红外光电弦与点动电容触摸构成演奏接口，全部声音由 FPGA 内部的振荡器逐样本实时合成，不播放预录音频，音频链不含 MCU 或软核 CPU。
- 开发板：Tang Mega 138K Pro；器件 `GW5AST-LV138FPG676AC1/I0`（工程器件版本 B）
- 构建工具：Gowin V1.9.12.03；顶层 `top_system`
- 音频输出：板载 PT8211，三线 LSBJ 串行格式 → 板载 3.5 mm → 有源音箱 AUX；与标准 Philips I2S 的位对齐方式不同
- [验证状态与已知问题](docs/validation.md) · [接线](docs/wiring.md) · [操作与上板流程](docs/board_test.md) · [模块清单](docs/modules.md)
## 关键指标
| 项目 | 实测 / 统计 |
|---|---|
| 复音数 | 32 个独立声部；测试模式下 32 个目标频率均检出独立局部谱峰，最大峰位偏差 0.379 Hz |
| 采样率 | 47.9068 kHz（PLL 12.264151 MHz ÷ 256），位时钟约 1.533 MHz |
| 端到端延迟 | 典型值低于 5 ms，代表记录 4.673 ms；全部观测满足基础要求 ≤10 ms |
| 时序 | Setup / Hold 违例 0 / 0，控制域 Fmax 62.154 MHz，音频域 14.064 MHz |
| 资源占用 | Logic 116600 / 138240，Register 24455 / 139140，BSRAM 212 / 340，DSP 226.5 / 298 |
## 功能与实现
| 功能 | 实现 |
|---|---|
| 32 声部 | `poly_mgr` 分配音槽，`voice_array` 并行例化 32 个 `voice`，各自保留相位和包络；共享音符到频率 ROM |
| 三种音色 | 压力键钟琴／笛子由 S1 选择，红外竖琴独立在线；起音时锁存音色 |
| 表情 | FSR 力度、S2 约向上 2 半音弯音、约 5.3 Hz 颤音；TTP 另控制八度与模式 |
| 回声 | 7168 采样延迟、0.5 反馈，重复间隔约 149.62 ms；干声直接通过 |
| 屏幕 | 160×128 横屏配置；输出 PCM 波形／延迟相图、16 个选定频点的频谱、模式及真实活跃音槽快照 |
| 灯带 | 30 颗 WS2812B，前 8 颗演奏／曲目提示，第 9–30 颗每帧清黑；实物不亮问题尚待排查 |
| 模式 | 普通 N、《小星星》指引 G、32 声部诊断 T |
声音在 FPGA 内实时合成，不播放预录整段 PCM。音频链无 MCU 或软核 CPU。仓库内的网页工具仅用于设计阶段的音色试听与交互比较，不参与板上发声。
控制域为 50 MHz；PLL 音频时钟 `50 MHz × 13 / 53 ≈ 12.264151 MHz`，采样率约 47.906840 kHz，位时钟约 1.533019 MHz。事件以 19 位来源／音色／类型／音符／力度编码，通过 64 深队列和四阶段握手跨域。时序约束仅对指定异步入口设置例外，CDC 协议本身仍由回归测试覆盖。
## 目录
```text
air_piano.gprj        Gowin 工程：只列综合源与约束，顶层由 Tcl 指定
run_gowin.tcl         器件专用引脚选项与构建入口
run_build.py          可配置 Gowin 路径的构建包装脚本
run_tests.py          可配置 Icarus 路径的回归脚本
src/                  主线 RTL 及保留的可选分支，不含测试平台
tests/                完整回归、行为 PLL 与参考实现
tests/legacy/         20 个早期测试平台，独立保存，不计入 60 项回归
legacy/rtl/           已被替代或未被主线调用的历史模块
docs/                 模块、接线、操作、验证边界和变更记录
reports/reference/    构建、时序和回归的原始证据
reports/checks/       回归与目录一致性检查结果
SOURCE_LAYOUT.json    源码路径映射与哈希对照表
```
## 构建
推荐将仓库放在纯英文路径下，例如 `E:/fpga/air-piano-fpga`；原工具在中文路径下曾出现 SP0002。
安装匹配器件支持与许可证的 Gowin V1.9.12.03 后，完整构建：
```powershell
python run_build.py --gowin "E:/Gowin/Gowin_V1.9.12.03_x64/IDE/bin/gw_sh.exe"
```
也可在仓库根目录直接运行 `gw_sh run_gowin.tcl`。脚本指定 `top_system`，并沿用器件专用引脚的复用设置。**不要把 tests/、legacy/ 或所有 `.v` 一起加入综合工程。** 若使用 GUI，请打开本仓库的 `.gprj`，并按 Tcl 核对顶层与复用选项。
输出通常为 `impl/pnr/air_piano.fs`，以工具实际输出为准。构建失败或挂起时应保留日志，不能仅凭文件出现判定成功。仓库未附带 `.fs`；不同环境综合得到的比特流不保证逐字节一致。
## 仿真
需要 Python 3.9+ 与支持 SystemVerilog `-g2012` 的 Icarus Verilog，加入 PATH 后：
```powershell
python run_tests.py
```
或显式指定路径：
```powershell
python run_tests.py --iverilog "E:/iverilog/bin/iverilog.exe" --vvp "E:/iverilog/bin/vvp.exe"
```
默认运行 60 项功能回归，再执行 20 组复位行为检查。输出位于 `build/test_results/` 与 `tests/results/`，摘要为 `build/TEST_SUMMARY.json`。单项重跑、参考实现与旧测试说明见 [tests/README.md](tests/README.md)。行为级 PLL 不验证真实 PLL、亚稳态或模拟音频特性。
## 构建结果与验证边界
资源占用为 Logic 116600/138240、Register 24455/139140、BSRAM 212/340、DSP 226.5/298；Setup/Hold 0/0，控制域 Fmax 62.154 MHz、音频域 14.064 MHz。原始证据见 [reports/reference](reports/reference/README.md)。
已完成两轮线路录音的频谱复核，32 个目标频率处均检出独立局部谱峰。仍待完成的部分：PR1014 布线警告、延迟上界与长期稳定性、灯带实物点亮。完整边界见 [验证记录](docs/validation.md)。仿真结果不作为实板结论使用。
## 许可
自有代码按 [LICENSE](LICENSE) 使用；Gowin 生成的 IP 保留其原始版权与许可约束。

# Air Piano — FPGA 实时多音色电子乐器

以 **AP04（2026-10-31）封存源码**为基线，纯 Verilog 实现 32 个独立声部、钟琴／笛子／红外竖琴、力度／弯音／颤音、反馈回声、屏幕和演奏指引。本次仅整理仓库、补齐构建和测试材料，不修改 RTL、引脚、时序约束或 PLL，不产生新的固件版本。

- 开发板：Tang Mega 138K Pro；器件 `GW5AST-LV138FPG676AC1/I0`，工程器件版本 B。
- 原构建工具：Gowin V1.9.12.03；顶层 **`top_system`**。
- 主线输出：板载 **PT8211，三线 LSBJ 串行音频** → 板载 3.5 mm → 有源音箱 AUX；不是标准 Philips I2S 的位对齐格式。
- [验证状态与已知问题](docs/validation.md) · [接线](docs/wiring.md) · [操作与上板流程](docs/board_test.md) · [模块清单](docs/modules.md)

## 功能与实现

| 功能 | 实现 |
|---|---|
| 32 声部 | `poly_mgr` 分配音槽，`voice_array` 并行例化 32 个 `voice`，各自保留相位和包络；共享音符到频率 ROM |
| 三种音色 | 压力键钟琴／笛子由 S1 选择，红外竖琴独立在线；起音时锁存音色 |
| 表情 | FSR 力度、S2 约向上 2 半音弯音、约 5.3 Hz 颤音；TTP 另控制八度与模式 |
| 回声 | 7168 采样延迟、0.5 反馈，重复间隔约 149.62 ms；干声直接通过 |
| 屏幕 | 160×128 横屏配置；输出 PCM 波形／延迟相图、16 个选定频点的频谱、模式及真实活跃音槽快照 |
| 灯带 | 30 颗 WS2812B，前 8 颗演奏／曲目提示，第 9–30 颗每帧清黑；实物不亮问题尚待闭合 |
| 模式 | 普通 N、《小星星》指引 G、32 声部诊断 T |

声音在 FPGA 内实时合成，不播放预录整段 PCM。音频链无 MCU 或软核 CPU。网页仅为辅助试听，不参与板上发声。

控制域为 50 MHz；PLL 音频时钟 `50 MHz × 13 / 53 ≈ 12.264151 MHz`，采样率约 47.906840 kHz，位时钟约 1.533019 MHz。事件以 19 位来源／音色／类型／音符／力度编码，通过 64 深队列和四阶段握手跨域。约束仅对指定异步入口等设置时序例外，不能据此省略 CDC 协议检查。

## 目录

```text
air_piano.gprj        Gowin 工程：只列综合源与约束，顶层由 Tcl 指定
run_gowin.tcl        与 AP04 相同的器件专用引脚选项与构建入口
run_build.py         可配置 Gowin 路径的构建包装脚本
run_tests.py         可配置 Icarus 路径的回归脚本
src/                 当前主线及保留的可选分支，不放测试平台
tests/               AP04 完整回归、行为 PLL 与参考实现
tests/legacy/        20 个早期测试平台，独立保存，不属于 60 项回归
legacy/rtl/          已被替代或未被当前主线调用的历史模块
docs/                模块、接线、操作、验证边界和变更记录
reports/reference/   原 AP04 构建、时序和回归证据
reports/checks/      本次目录整理的检查结果
SOURCE_LAYOUT.json   原路径到新路径及源码哈希的对应表
```

## 构建

推荐将仓库下载到纯英文路径，例如 `E:/fpga/air-piano-fpga`。原工具在中文路径下出现过 SP0002。

安装匹配器件支持与许可证的 Gowin V1.9.12.03。完整构建：

```powershell
python run_build.py --gowin "E:/Gowin/Gowin_V1.9.12.03_x64/IDE/bin/gw_sh.exe"
```

也可在仓库根目录运行 `gw_sh run_gowin.tcl`。脚本指定 `top_system`，保留 AP04 的 SSPI/CPU/JTAG 引脚复用设置。**不要将 tests/、legacy/ 或所有 `.v` 一起添加到综合工程。**若通过 GUI 操作，应打开本仓库 `.gprj`，并按 Tcl 核对顶层及复用选项。

输出通常为 `impl/pnr/air_piano.fs`，以工具实际输出为准。构建失败或挂起时保留日志，不只凭文件出现就判定成功。仓库没有附带 `.fs`，也不承诺不同环境产生逐字节相同的比特流。

## 仿真

需要 Python 3.9+ 与支持 SystemVerilog `-g2012` 的 Icarus Verilog。加入 PATH 后：

```powershell
python run_tests.py
```

或者显式指定：

```powershell
python run_tests.py --iverilog "E:/iverilog/bin/iverilog.exe" --vvp "E:/iverilog/bin/vvp.exe"
```

默认运行原 AP04 的 60 项回归，再运行 20 组复位行为检查。输出位于 `build/test_results/` 与 `tests/results/`；摘要是 `build/TEST_SUMMARY.json`。单项重跑、参考实现和旧测试的说明见 [tests/README.md](tests/README.md)。行为 PLL 不验证真实 PLL、亚稳态或模拟音频。

## 历史构建与实测边界

原 AP04 的 Logic 116600/138240、Register 24455/139140、BSRAM 212/340、DSP 226.5/298；Setup/Hold 0/0，控制域 Fmax 62.154 MHz、音频域 14.064 MHz。原始证据在 [reports/reference](reports/reference/README.md)，属于原封存构建，本次没有重新综合。

AP04 已有用户提供的两轮线路录音及频谱复核；这不等于所有赛题指标通过。**PR1014 尚存、延迟上界和稳定性未闭合、灯带实物不亮待查**，完整边界见 [验证记录](docs/validation.md)。本仓库不会把仿真结果写成实板结论。

## 许可

自有代码按 [LICENSE](LICENSE) 使用；Gowin 生成 IP 保留原版权及其许可约束。历史模块与参考实现保留原文件说明，不凭本次目录整理推定作者归属或贡献比例。

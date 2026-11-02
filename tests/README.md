# AP04 仿真

仓库根目录运行 `python run_tests.py`：原 60 项回归 + 单独的 20 组复位场景。无 Python 第三方库依赖；需要 Icarus Verilog 与 vvp。

```powershell
python run_tests.py --iverilog E:/iverilog/bin/iverilog.exe --vvp E:/iverilog/bin/vvp.exe
python run_tests.py queue_equiv synth_shared_equiv --skip-reset
python run_tests.py --reset-only
```

可用 `--jobs 2` 控制并行数。实际测试名由 `run_tests.py` 中 DEFAULT_TESTS 列出；不存在的测试会立即报错。

- tests/*.v 包含测试平台、参考实现、行为 PLL；不是都可以独立当作测试顶层。
- reference/ 是 AP03 等价对照所需的旧实现，不能删去或用于产品综合。
- pll_sim.v 代替厂商 PLL，不能验证真实 PLL 锁定、时钟偏斜和亚稳态。
- legacy/ 是另存的早期 tb_ 测试，不在默认回归中。
- build/test_results/ 是本次运行的编译与执行日志；tests/results/ 是测试生成的 PCM CSV 等临时数据，均不提交。

测试覆盖包括压力／红外、手势、事件队列与跨域、起音和释放、三音色、32 声部、混音、延迟线、PT8211／可选标准 I2S、LCD、频谱、音槽快照、WS2812、计时宽度及 AP03 等价。协议、像素和数字延迟测试不能代替模拟输入、3.5mm、屏幕或灯带的实测。

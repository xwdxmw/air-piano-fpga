# AP04 原封存构建与仿真记录

本目录文件逐字节复制自 2026-10-31 的 AP04 封存包，哈希见 FILE_SHA256.json；不代表目录整理后重新布局布线的结果。工具原始报告保留了当时的本机路径。

- TEST_SUMMARY.json：原 60 项回归的结果与输入哈希。
- RESET_RELEASE_CHECK.json：原 20 组行为复位检查，不是 20 次真实断电测试。
- AP04_release_status.json：发布当日状态，board_tested=false 是当时的记录；后续线路录音见 ../../docs/validation.md。
- air_piano.rpt.txt / air_piano_tr_content.html：原资源与时序报告。
- air_piano.log：保留 PR1014 原警告。

原构建输出已完成，但工具进程退出曾挂起并由清理流程结束，因此状态里保留 exit_code=-1。不能把它改写为正常退出，也不能把它等同于板上卡死。
当前整理的回归结果放在 ../checks/，以后本地运行输出放在 build/ 和 tests/results/，不覆盖这些历史证据。

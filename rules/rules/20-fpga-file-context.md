---
paths:
  - "**/*.{v,vh,sv}"
  - "**/*.{adc,sdc,al,do,tcl}"
  - "**/rtl/**/*"
  - "**/tb/**/*"
  - "**/sim/**/*"
  - "**/prj/**/*"
---

# FPGA File-Context Rules

当对话已触达 HDL / 约束 / 仿真 / TD 工程相关文件时，按以下规则增强执行稳定性：

1. 请求涉及修改 RTL 设计意图：优先 `fpga-rtl-build`；编译失败再转 `fpga-compile-and-repair`。
2. 请求涉及编译/语法问题：优先 `fpga-compile-and-repair`，以工具输出（iverilog / vlog / TD 日志）为准。
3. 请求只涉及生成 TB 源码：`fpga-tb-write`。
4. 请求涉及 `.adc` / `.sdc`：`fpga-adc-gen`；涉及 `.al` / `build.tcl` / TD 报告：`fpga-td-build`。
5. 触达 `rtl/al_ip/*.v`（TD IP Generator 产物）时只读不改；需要改参数应在 TD 的 IP Generator 里重新生成。
6. 任何结论必须可回指到文件路径、日志或仿真/综合结果；缺少证据就明确指出需要的输入，而不是臆测。

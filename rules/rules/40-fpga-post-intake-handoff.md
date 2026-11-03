# FPGA Post-Intake Handoff

如果本回合已经调用过 `fpga-intake`：
- 不要在主对话直接生成/修改 RTL 或 TB 文件，也不要直接跑仿真/综合命令。
- 必须根据 `doc/intake/summary.md` 的 `## Handoff and Next Step` 选择下一步 skill：
  - 依赖模块拆分、顶层边界、协议初始化时序、CDC/复位策略、板级接口封装、IP 黑盒包装或存储架构选择：优先 `fpga-architecture`
  - 需要板级引脚/时钟/电气事实：`fpga-hw-manual-extraction`
  - RTL 实现或改动：仅当接口边界、模块职责、初始化/CDC/缓存策略已稳定时，调用 `fpga-rtl-build`
  - TB 源码：`fpga-tb-write`
  - 编译检查：`fpga-compile-and-repair`
  - 仿真 / 波形：`fpga-sim-run`
  - 约束：`fpga-adc-gen`
  - 综合 / 布局布线 / 位流 / 资源时序报告：`fpga-td-build`
- 若 RTL 阶段的结果暴露出命中 `rules/00-skill-routing.md`"协议时序敏感模块判定标准"的上游契约未冻结问题（端口/参数语义漂移、边沿语义不明、阶段顺序自相矛盾、片选生命周期或命令/响应边界靠猜），不要在同层盲重试 `fpga-rtl-build`；回退到 `fpga-architecture` 或补行为规格后再交接。
- 不要把 handoff 里推荐的阶段全部自动执行。只执行用户本轮明确要求的阶段；其它阶段在总结里作为可选下一步列出。
- 若 handoff 不足以确定下一步：补充最少澄清问题或再次调用 `fpga-intake` 更新 summary。

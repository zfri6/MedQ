# 架构交接文档

## Stable Contracts

- Interface contract: `doc/arch/interface_contract.yaml`
- Clock/reset/CDC plan: `doc/arch/clock_reset_cdc.md`
- Module partition: `doc/arch/module_partition.md`
- Connection matrix: `doc/arch/connection_matrix.md`
- Top skeleton: `rtl/top_skeleton.v`
- Risks and assumptions: `doc/arch/risks.md`

## IP wrappers the user must generate (TD IP Generator → `rtl/al_ip/`)

| Wrapper module | Type | Parameters |
| --- | --- | --- |
| (empty when the design is pure logic) | | |

## Recommended Next Steps

- 进入 RTL 实现：按接口契约一次实现一个子模块（`fpga-rtl-build`），不自动生成 TB 或跑仿真。
- 细化行为规格：补充边界条件、握手和波形检查计划（`fpga-behavior-and-wave-plan`）。
- 提取板级事实后生成 `.adc` / `.sdc`（`fpga-hw-manual-extraction` → `fpga-adc-gen`）。
- 综合 / 资源 / 时序 / 位流（`fpga-td-build`）。

## Risks

| Risk | Impact | Mitigation |
| --- | --- | --- |

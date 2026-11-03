---
name: 架构设计
description: 该 Skill 设计 FPGA 模块拆分、接口契约、时钟复位与 CDC 策略，并生成 RTL 顶层骨架。适用于多模块系统、协议/初始化时序、板级接口或顶层边界尚未稳定的复杂任务，在进入可实现架构与 top skeleton 阶段前使用。
allowed-tools: [Read, Grep, Glob, Write, Edit, AskUserQuestion]
user-invocable: true
argument-hint: "<optional: module_name>"
arguments: [module_name]
when_to_use: 当任务在进入 RTL 之前需要先稳定系统结构时使用，例如：多模块拆分、顶层端口/子模块边界未定、协议初始化或时序编排、跨时钟域/复位策略、板级接口/黑盒 IP 封装、缓存/FIFO/存储架构选择，或 intake 已判定下一步依赖架构决策而非直接编码。若命中 `rules/00-skill-routing.md` 中的“协议时序敏感模块判定标准”，且关键契约尚未冻结，也应先进入本阶段。
version: "0.1.0"
---

# FPGA Architecture

Use this skill to produce a stable implementation contract for later RTL, TB, compile, simulation, constraint and synthesis work on the HX4S20 (Anlogic EG4S20BG256).

## Boundaries

- Generate architecture artifacts and an RTL skeleton only. Do not implement business logic.
- This stage exists to freeze engineering boundaries before RTL: module partitioning, top-level interfaces, initialization ordering, CDC ownership, board wrapper, memory strategy.
- Protocol-timing-sensitive controllers (see `rules/00-skill-routing.md`「协议时序敏感模块判定标准」) are not "simple RTL"; architecture must lock edge semantics, phase order, chip-select lifetime and init sequence before RTL starts.
- Do NOT create implemented submodule RTL (`sobel.v`, `reset_sync.v`, FIFO RTL, PLL wrappers, encoders). The only RTL file from this stage is `rtl/top_skeleton.v` (Verilog-2001, black-box instances, no logic).
- Do NOT generate `rtl/top.v`; that is `fpga-rtl-build`'s job once the skeleton is accepted.
- Do not change user-confirmed ports, registers, clock domains or protocol semantics without recording a required upstream decision.
- Anlogic IP (PLL `EG_PHY_PLL`, BRAM `EG_LOGIC_BRAM`, FIFO, DDR I/O) and external chips (RTL8211E PHY, OV5640, DAC/ADC, LCD) are black boxes: define the wrapper interface, name the wrapper module (`pll_sys`, `fifo_async_8x1024` …) and record that the user must generate it in TD IP Generator into `rtl/al_ip/`.
- Keep CDC decisions explicit: control sync, data FIFO, reset sync, or same-domain proof.
- Missing hardware details → conservative assumption recorded in `doc/arch/risks.md`; ask only when a choice blocks even a safe draft.

## Context Derivation

1. Read `doc/intake/summary.md` if present; then `doc/hw/extracted_facts.json` (board clock, available signals) and `rules/05-hx4s20-target.md` facts (device, resources).
2. If the user points at existing RTL, specs or hardware files, `Glob` then read only the minimum required.
3. Never read the output paths before generating them; in a fresh workspace they do not exist.
4. Bundled templates live next to this file under `templates/`; consult them when unsure of the shape, otherwise follow the output format below.

## Input Artifacts

1. `doc/intake/summary.md`
2. `doc/hw/extracted_facts.json` — board clock (25 MHz on HX4S20 per DEMO, to be confirmed), board signal names
3. Requirement text, register table, protocol note, datasheets from `4_芯片手册`, existing RTL headers
4. Existing top/module files if this is an update
5. `references/architecture_patterns.md`, `references/clock_reset_cdc_patterns.md`

## Default Assumptions (only when no stronger fact exists)

- Board clock 25 MHz on `CLOCK`/`clk_25`; every other frequency comes from one PLL wrapper with up to 5 outputs (EG4 PLL). Plan clock domains around that.
- Resource budget EG4S20: ~20K LUT4, 64 × 9 Kbit BRAM (≈576 Kbit), 29 multipliers, 4 PLLs (verify in `6_EG4S20`). A full 640×480 RGB565 frame does not fit in BRAM → line buffers, not frame buffers, unless external SDRAM is on the board and in scope.
- Camera-to-display: 640×480@60 Hz first pass; OV5640 as 8-bit DVP RGB565 (two bytes per pixel) with SCCB init table treated as a protocol-timing-sensitive controller.
- Camera pixel clock ≠ display pixel clock → async FIFO for pixel payload + frame/line sideband; frame-level control synchronised separately.
- Ethernet: RTL8211E over RGMII, 125 MHz TX from PLL, RX clock from PHY as its own domain (DEMO 32/33 structure).
- Reset: external key `rst_n` (active-low, pulled up) → one reset synchroniser per clock domain → async-assert/sync-release internally; hold everything in reset until PLL `extlock`.
- Keep control knobs (threshold, bypass, test pattern) as ports unless a register map is requested.

## Workflow

1. Identify top module, external interfaces, internal submodules, black boxes, and ownership boundaries.
2. Capture architecture assumptions separately from confirmed requirements.
3. Create `doc/arch/interface_contract.yaml`: every external port and submodule port must include direction, width, clock domain, reset domain, protocol, and semantic notes.
4. Create `doc/arch/clock_reset_cdc.md`: list all clock domains, reset synchronizers, data CDC, control CDC, and verification evidence.
5. Create `doc/arch/module_partition.md`: module table, owner/responsibility, state/FIFO/RAM ownership, and black boxes.
6. Create `doc/arch/connection_matrix.md`: producer, signal group, consumer, protocol, clock domain, latency/backpressure notes.
7. Create `rtl/top_skeleton.v`: Verilog-2001 top-level skeleton with parameters, board-facing ports (names from `extracted_facts.json` when available), local wires, black-box submodule and IP-wrapper instances, and no business logic. Mark every IP wrapper instance with a comment `// generate with TD IP Generator -> rtl/al_ip/<name>.v`.
8. Create `doc/arch/risks.md`: assumptions, unresolved hardware facts, timing/resource risks against the EG4S20 budget, and downstream evidence requirements.
9. Create `doc/arch/handoff_packet.md`: concise handoff pointing to the generated artifacts, the list of IP wrappers to generate, and next stages.

## Output Artifacts

- `doc/arch/interface_contract.yaml`
- `doc/arch/clock_reset_cdc.md`
- `doc/arch/module_partition.md`
- `doc/arch/connection_matrix.md`
- `rtl/top_skeleton.v`
- `doc/arch/risks.md`
- `doc/arch/handoff_packet.md`

Do not use alternate filenames. Forbidden paths: `doc/arch/architecture.md`, `doc/arch/cdc_strategy.md`, `doc/arch/interface_contract.md`, `rtl/top.v`, `rtl/reset_sync.v`, any `.sv` under `rtl/`.

## Completion Gate

Architecture is complete when every external port and submodule interface has an owner, clock/reset domain, protocol rule, and downstream verification hook. Any unresolved decision must be visible as an open question, not hidden in RTL comments.

Use architecture before RTL whenever direct implementation would otherwise require guessing any of the following:
- top-level external ports or board-facing wrappers
- submodule partitioning or ownership boundaries
- protocol bring-up / initialization sequencing
- CDC method selection or reset-tree ownership
- memory buffering strategy such as line buffer vs frame buffer vs async FIFO
- black-box IP wrapper boundaries or vendor primitive encapsulation
- protocol edge semantics such as launch/sample edge, chip-select lifetime, phase ordering, or command/response boundary rules in a timing-sensitive controller

## Bundled Resources

- `references/clock_reset_cdc_patterns.md`: CDC and reset decision patterns
- `references/architecture_patterns.md`: architecture patterns from supplied FPGA requirement samples
- `templates/interface_contract.yaml`
- `templates/clock_reset_cdc.md`
- `templates/module_partition.md`
- `templates/connection_matrix.md`
- `templates/top_skeleton.v`
- `templates/risks.md`
- `templates/handoff_packet.md`

## Output Format

This skill runs inline. Write all seven files with the `Write` tool using workspace-relative paths; do not paste file contents into the chat.

Common mistakes:
- Writing implementation RTL or helper RTL in the architecture stage.
- Writing `.sv` into `rtl/` (TD needs Verilog-2001).
- Inventing board pins or signal names that are not in `extracted_facts.json` — use placeholders and list them in `risks.md`.
- Continuing to RTL, TB, compile, simulation, constraints or synthesis without the user asking for that stage.

## Final Response

Per `rules/60-fpga-artifact-manifest.md`: one sentence on the result, the module list, the IP wrappers the user must generate in TD IP Generator, open risks that need a decision, and the next stage (normally RTL generation, one module at a time).

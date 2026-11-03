# TD 6.2 Flow Notes

Everything below is taken from the contest DEMO projects (`2_Example/DEMO/*/*_Runs/{syn_1,phy_1}/*.tcl`, `*.al`) unless marked (verify).

## Flow steps and Tcl commands (from the GUI flow script)

| Step | Commands in the editable zone | Produces |
|---|---|---|
| `read_design` | `elaborate -top <top>`; then `read_adc`, `read_sdc`, `read_ip_adc` | `<prj>_elaborate.db` |
| `opt_rtl` | `optimize_rtl`; `report_area -file <prj>_rtl.area` | `<prj>_rtl.db` |
| `opt_gate` | `optimize_gate <area_option> <prj>_gate.area`; `legalize_phy_inst`; `update_timing`; `report_timing_status -file <prj>_gate.ts`; `report_timing_summary -file <prj>_gate.timing` | `<prj>_gate.db` |
| `opt_place` | `place`; `update_timing -mode manhattan`; `report_timing_summary -file <prj>_place.timing`; `report_area -io_info -file <prj>_phy.area`; `report_clock_utilization` | `<prj>_place.db` |
| `opt_route` | `route`; `report_area -io_info`; `update_timing -mode final`; `report_timing_status -file <prj>_phy.ts`; `report_timing_summary -file <prj>_pr.timing`; `report_timing_exception`; `report_clock_utilization` | `<prj>_pr.db` |
| `bitgen` | `bitgen -bit <prj>.bit` | `<prj>.bit` |

Setup commands used before the steps: `import_device <db> -package <pkg> [-speed <s>]`, `open_project <prj>.al`, `read_verilog <file>` (batch scripts), `import_db <x>.db`, `export_db <x>.db`, `set_param <group> <name> <value>`, `report_param`.

The GUI flow scripts also call `insert_debugger` (ChipWatcher) and `setup_debugger`; `build.tcl` omits them.

## Device import

- EG4S20BG256 → `import_device eagle_s20.db -package BG256` (verify the `.db` name in `<TD_HOME>/arch/`; `find_tools.py` lists what is there).
- Speed grade: DEMOs leave `<Speed>` empty; omit `-speed`.

## Project file (`.al`) essentials

- XML, `<Project Version="3" Minor="2" Path="...">`, `<TD_Encoding>GB2312</TD_Encoding>`, `<TD_Version>6.2.168116</TD_Version>`.
- `<HardWare><Family>EG4</Family><Device>EG4S20BG256</Device></HardWare>`.
- `<Source_Files>` groups: `<Verilog>`, `<ADC_FILE>`, `<SDC_FILE>`, `<IP_FILE>` (`al_ip/*.ipc`), `<CWC_FILE>` (ChipWatcher). Each `<File Path>` is relative to the `.al` directory with attributes `UsedInSyn`, `UsedInP&R`, `BelongTo`, `CompileOrder`.
- `<TOP_MODULE><MODULE>` names the top; `<CREATEINDEX>user</CREATEINDEX>` when set manually.
- Runs: `syn_1` (Synthesis) and `phy_1` (PhysicalDesign, `SynRun="syn_1"`), both bound to the constraint fileset.

## IP Generator outputs

- `al_ip/<name>.v` wrapper + `al_ip/<name>.ipc` configuration. The wrapper instantiates the primitive (`EG_PHY_PLL`, `EG_LOGIC_BRAM`, …). Add both files to the project; simulation needs `<TD_HOME>/sim_release/al` and `sim_release/eg`.
- PLL wrapper ports: `refclk`, `reset`, `extlock`, `clk0_out`..`clk4_out`; internal instance named `pll_inst`; SDC refers to `<wrapper_inst>/pll_inst.clkc[<i>]`.

## Reports (formats: verify on first run and update this section)

- `*.area`: utilisation table per resource type with used/total; `-io_info` adds an IO table with pin, IOSTANDARD, direction.
- `*.timing`: per-clock summary (setup/hold slack, Fmax), then worst paths.
- `*.ts`: one-line-per-clock timing status; negative slack or FAIL means timing not met.
- `*_exception.timing`: false paths / multicycle / clock groups applied.
- `*_clock_utilization.txt`: clocks found in the netlist and their constraints; a clock listed without a constraint means the SDC is incomplete.

`run_td.py` greps these with tolerant regexes and always embeds the last 40 lines of each report in `doc/compile/td_report.md`.

## Batch invocation

- `td.exe -f <script.tcl>` runs a Tcl script in shell mode (verify on the installed build; alternative is GUI Tools → Tcl Console → `source`).
- TD writes many temporary files into the current directory; run from the project root so they land under `prj/td/`.
- Non-ASCII paths: use `run_td.py --mirror <ascii_dir>`.

## Download

- TD → Tools → Download → Add `<prj>.bit` → Mode `JTAG` → Operation `Program` (SRAM) or `Program Flash`. Requires the board's USB downloader driver from the contest tools folder.

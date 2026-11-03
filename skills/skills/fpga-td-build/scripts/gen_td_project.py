#!/usr/bin/env python
"""Generate an Anlogic TD project (.al) and a batch flow script (build.tcl) for EG4S20BG256.

Usage:
    python gen_td_project.py --top top [--name <prj_name>] [--out prj/td]
                             [--adc prj/constr/top.adc] [--sdc prj/constr/top.sdc]
                             [--toolchain doc/hw/toolchain.json] [--no-bitgen]

Produces:
    <out>/<name>.al        open in TD GUI (Family EG4 / Device EG4S20BG256, matches the contest DEMO projects)
    <out>/build.tcl        run with  td.exe -f <out>/build.tcl  (from the project root)
    <out>/reports/         created empty; filled by build.tcl
    <out>/output/          created empty; <name>.bit lands here

Source files: rtl/*.v plus rtl/al_ip/*.v. The .al stores paths relative to its own directory; build.tcl
uses paths relative to the project root. All paths are written with forward slashes for Tcl.
"""
import argparse
import json
import os
import sys
from pathlib import Path
from xml.sax.saxutils import escape

FAMILY, DEVICE, TD_VERSION = "EG4", "EG4S20BG256", "6.2.168116"


def rel(path, start):
    return os.path.relpath(path, start).replace("\\", "/")


def file_entry(path, fileset, order, indent="            "):
    return (f'{indent}<File Path="{escape(path)}">\n'
            f'{indent}    <FileInfo>\n'
            f'{indent}        <Attr Name="UsedInSyn" Val="true"/>\n'
            f'{indent}        <Attr Name="UsedInP&amp;R" Val="true"/>\n'
            f'{indent}        <Attr Name="BelongTo" Val="{fileset}"/>\n'
            f'{indent}        <Attr Name="CompileOrder" Val="{order}"/>\n'
            f'{indent}    </FileInfo>\n'
            f'{indent}</File>\n')


def build_al(name, top, verilog, adc, sdc, out_dir):
    v_block = "".join(file_entry(rel(p, out_dir), "design_1", i + 1) for i, p in enumerate(verilog))
    adc_block = f"        <ADC_FILE>\n{file_entry(rel(adc, out_dir), 'constraint_1', 1)}        </ADC_FILE>\n" if adc else ""
    sdc_block = f"        <SDC_FILE>\n{file_entry(rel(sdc, out_dir), 'constraint_1', 2)}        </SDC_FILE>\n" if sdc else ""
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<Project Version="3" Minor="2" Path="{escape(Path(out_dir).resolve().as_posix())}">
    <Project_Created_Time></Project_Created_Time>
    <TD_Encoding>GB2312</TD_Encoding>
    <TD_Version>{TD_VERSION}</TD_Version>
    <Name>{escape(name)}</Name>
    <HardWare>
        <Family>{FAMILY}</Family>
        <Device>{DEVICE}</Device>
        <Speed></Speed>
    </HardWare>
    <Source_Files>
        <Verilog>
{v_block}        </Verilog>
{adc_block}{sdc_block}    </Source_Files>
    <FileSets>
        <FileSet Name="design_1" Type="DesignFiles">
        </FileSet>
        <FileSet Name="constraint_1" Type="ConstrainFiles">
        </FileSet>
    </FileSets>
    <TOP_MODULE>
        <LABEL>{escape(top)}</LABEL>
        <MODULE>{escape(top)}</MODULE>
        <CREATEINDEX>user</CREATEINDEX>
    </TOP_MODULE>
    <Property>
    </Property>
    <Device_Settings>
    </Device_Settings>
    <Configurations>
    </Configurations>
    <Runs>
        <Run Name="syn_1" Type="Synthesis" ConstraintSet="constraint_1" Description="" Active="true">
            <Strategy Name="Default_Synthesis_Strategy">
            </Strategy>
            <UserParams>
            </UserParams>
        </Run>
        <Run Name="phy_1" Type="PhysicalDesign" ConstraintSet="constraint_1" Description="" SynRun="syn_1" Active="true">
            <Strategy Name="Default_PhysicalDesign_Strategy">
            </Strategy>
            <UserParams>
            </UserParams>
        </Run>
    </Runs>
    <Project_Settings>
    </Project_Settings>
</Project>
"""


def build_tcl(name, top, verilog, adc, sdc, out_dir, device_db, package, bitgen):
    rep = f"{out_dir}/reports"
    lines = [f"# Anlogic TD batch flow for {name} ({DEVICE}). Run from the project root:",
             f"#   td.exe -f {out_dir}/build.tcl",
             "# Step order mirrors the editable zones of the TD GUI flow script (DEMO *_Runs/syn_1/*.tcl).",
             "",
             f"import_device {device_db} -package {package}",
             ""]
    lines += [f"read_verilog {p}" for p in verilog]
    if adc:
        lines.append(f"read_adc {adc}")
    if sdc:
        lines.append(f"read_sdc {sdc}")
    lines += ["",
              f"elaborate -top {top}",
              "optimize_rtl",
              f"report_area -file {rep}/{name}_rtl.area",
              "optimize_gate",
              "legalize_phy_inst",
              "update_timing",
              f"report_timing_status -file {rep}/{name}_gate.ts",
              f"report_timing_summary -file {rep}/{name}_gate.timing",
              "place",
              "update_timing -mode manhattan",
              f"report_timing_summary -file {rep}/{name}_place.timing",
              "route",
              f"report_area -io_info -file {rep}/{name}_phy.area",
              "update_timing -mode final",
              f"report_timing_status -file {rep}/{name}_phy.ts",
              f"report_timing_summary -file {rep}/{name}_pr.timing",
              f"report_timing_exception -file {rep}/{name}_exception.timing",
              f"report_clock_utilization -file {rep}/{name}_clock_utilization.txt",
              f"export_db {out_dir}/output/{name}_pr.db"]
    if bitgen:
        lines.append(f"bitgen -bit {out_dir}/output/{name}.bit")
    lines += ["", "puts \"TD_FLOW_DONE\"", "exit"]
    return "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--top", required=True)
    ap.add_argument("--name")
    ap.add_argument("--out", default="prj/td")
    ap.add_argument("--adc", default="prj/constr/top.adc")
    ap.add_argument("--sdc", default="prj/constr/top.sdc")
    ap.add_argument("--toolchain", default="doc/hw/toolchain.json")
    ap.add_argument("--no-bitgen", action="store_true")
    args = ap.parse_args()

    name = args.name or args.top
    out_dir = args.out.replace("\\", "/").rstrip("/")
    verilog = [p.as_posix() for p in sorted(Path("rtl").glob("*.v"))] + [p.as_posix() for p in sorted(Path("rtl/al_ip").glob("*.v"))]
    if not verilog:
        print("no rtl/*.v found", file=sys.stderr)
        return 2
    adc = args.adc if Path(args.adc).exists() else None
    sdc = args.sdc if Path(args.sdc).exists() else None
    if not adc:
        print(f"WARNING: {args.adc} not found; project has no pin constraints (fine for synthesis-only runs)")

    device_db, package = "eagle_s20.db", "BG256"
    tc_path = Path(args.toolchain)
    if tc_path.exists():
        tc = json.loads(tc_path.read_text(encoding="utf-8"))
        device_db = (tc.get("td") or {}).get("device_db", device_db)
        package = tc.get("target", {}).get("package", package)

    for sub in ("", "reports", "output"):
        Path(out_dir, sub).mkdir(parents=True, exist_ok=True)
    al = Path(out_dir, f"{name}.al")
    al.write_text(build_al(name, args.top, verilog, adc, sdc, out_dir), encoding="utf-8")
    tcl = Path(out_dir, "build.tcl")
    tcl.write_text(build_tcl(name, args.top, verilog, adc, sdc, out_dir, device_db, package, not args.no_bitgen), encoding="utf-8")

    print(f"written: {al.as_posix()}  (open in TD GUI)")
    print(f"written: {tcl.as_posix()}  (td.exe -f {tcl.as_posix()})")
    print(f"sources: {len(verilog)} verilog, adc={'yes' if adc else 'no'}, sdc={'yes' if sdc else 'no'}, top={args.top}")
    if not Path.cwd().as_posix().isascii():
        print("WARNING: project path contains non-ASCII characters; use run_td.py --mirror <ascii_dir>")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python
"""Unified simulation runner for this project (copied from fpga-tb-write/templates/run_sim.py).

Run from the project root:
  python sim/run_sim.py                       # compile only (ModelSim vlog if available, else iverilog)
  python sim/run_sim.py --run                 # compile + run, PASS/FAIL from TB $display
  python sim/run_sim.py --run --vcd           # also dump sim/wave.vcd via +define+DUMP_VARS
  python sim/run_sim.py --run --sim iverilog  # force simulator
  python sim/run_sim.py --run --anlogic-lib   # add <TD_HOME>/sim_release/{al,eg} (designs using rtl/al_ip IP); alias --with-al-ip
  python sim/run_sim.py --gui                 # open ModelSim GUI with sim/modelsim/wave.do

Tool paths come from doc/hw/toolchain.json (written by fpga-td-build/scripts/find_tools.py), env vars
(MODELSIM_HOME / IVERILOG_HOME / TD_HOME), PATH, then common install dirs.

Outputs (all under sim/): compile.log, sim.log, sim_result.json, wave.vcd (when --vcd), work/ (ModelSim lib)
Exit code: 0 PASS / compile-only success, 1 FAIL, 2 no sources, 127 simulator not found.
"""
import argparse
import glob
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SIM = ROOT / "sim"
TOOLCHAIN_JSON = ROOT / "doc" / "hw" / "toolchain.json"
TB_TOP_DEFAULT = "tb_top"


# ---------------------------------------------------------------- tool discovery
def _cache():
    if TOOLCHAIN_JSON.exists():
        try:
            return json.loads(TOOLCHAIN_JSON.read_text(encoding="utf-8"))
        except Exception:
            pass
    return {}


def _save_cache(c):
    TOOLCHAIN_JSON.parent.mkdir(parents=True, exist_ok=True)
    TOOLCHAIN_JSON.write_text(json.dumps(c, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def _exe(name):
    return name + (".exe" if os.name == "nt" else "")


def find_iverilog(c):
    cands = [c.get("iverilog_bin") and str(Path(c["iverilog_bin"]) / _exe("iverilog"))]
    if os.environ.get("IVERILOG_HOME"):
        cands.append(str(Path(os.environ["IVERILOG_HOME"]) / "bin" / _exe("iverilog")))
    cands += [shutil.which("iverilog"), r"C:\iverilog\bin\iverilog.exe"]
    for p in cands:
        if p and Path(p).exists():
            return str(Path(p))
    return None


def find_modelsim(c):
    cands = [c.get("modelsim_bin")]
    home = os.environ.get("MODELSIM_HOME")
    if home:
        cands += [home, str(Path(home) / "win64"), str(Path(home) / "win32aloem"), str(Path(home) / "bin")]
    w = shutil.which("vsim")
    if w:
        cands.append(str(Path(w).parent))
    for pat in (r"C:\modeltech64_*\win64", r"C:\modeltech*\win32", r"C:\intelFPGA*\*\modelsim_ase\win32aloem",
                r"C:\intelFPGA*\*\modelsim_ae\win64", r"D:\modeltech64_*\win64"):
        cands += sorted(glob.glob(pat), reverse=True)
    for d in cands:
        if d and (Path(d) / _exe("vsim")).exists():
            return str(Path(d))
    return None


def find_td_home(c):
    cands = [os.environ.get("TD_HOME"), c.get("td_home"), (c.get("td") or {}).get("td_home")]
    for pat in (r"C:\Anlogic\TD*", r"D:\Anlogic\TD*", r"C:\Program Files\Anlogic\TD*"):
        cands += sorted(glob.glob(pat), reverse=True)
    for d in cands:
        if d and (Path(d) / "sim_release").exists():
            return str(Path(d))
    return None


def fwd(p):
    return str(p).replace("\\", "/")


def sources():
    rtl = sorted(glob.glob(str(ROOT / "rtl" / "**" / "*.v"), recursive=True))
    tb = sorted(glob.glob(str(ROOT / "tb" / "*.v"))) + sorted(glob.glob(str(ROOT / "tb" / "*.sv")))
    return rtl, tb


def run(cmd, log_fh, header, cwd=SIM, timeout=None):
    log_fh.write(f"\n===== {header} =====\n$ {' '.join(cmd)}\n")
    log_fh.flush()
    p = subprocess.run(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                       encoding="utf-8", errors="replace", timeout=timeout)
    log_fh.write(p.stdout)
    log_fh.write(f"\n[exit code {p.returncode}]\n")
    log_fh.flush()
    return p.returncode, p.stdout


def judge(sim_text, rc):
    """PASS iff exit 0, a line 'PASS' exists, no 'FAIL'/'ERROR'/'TIMEOUT'/'Fatal' lines from TB."""
    lines = [l.strip() for l in sim_text.splitlines()]
    has_pass = any(re.match(r"^(#\s*)?PASS\b", l) for l in lines)
    bad = [l for l in lines if re.match(r"^(#\s*)?(FAIL|ERROR|TIMEOUT)\b", l) or "** Fatal" in l or "Fatal:" in l]
    if rc != 0:
        return "FAIL", bad or [f"simulator exit code {rc}"]
    if bad:
        return "FAIL", bad
    if has_pass:
        return "PASS", []
    return "FAIL", ["no PASS line printed by TB"]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--sim", choices=["auto", "modelsim", "iverilog"], default="auto")
    ap.add_argument("--run", action="store_true", help="run simulation after compile")
    ap.add_argument("--compile-only", action="store_true", help="(default behaviour) compile without running")
    ap.add_argument("--vcd", action="store_true", help="define DUMP_VARS so the TB writes sim/wave.vcd (implies --run)")
    ap.add_argument("--gui", action="store_true", help="ModelSim GUI with sim/modelsim/wave.do (implies modelsim)")
    ap.add_argument("--tb-top", default=os.environ.get("TB_TOP", TB_TOP_DEFAULT))
    ap.add_argument("--anlogic-lib", "--with-al-ip", dest="anlogic_lib", action="store_true",
                    help="compile rtl/al_ip wrappers + <TD_HOME>/sim_release models (ModelSim only)")
    ap.add_argument("--define", action="append", default=[], help="extra +define+NAME[=VAL]")
    ap.add_argument("--timeout", type=int, default=600, help="seconds before the simulator is killed")
    args = ap.parse_args()
    if args.vcd or args.gui:
        args.run = True
    if args.compile_only:
        args.run = False

    SIM.mkdir(parents=True, exist_ok=True)
    rtl, tb = sources()
    if not rtl or not tb:
        print("Need at least one file in rtl/ and tb/.", file=sys.stderr)
        return 2

    c = _cache()
    ms = find_modelsim(c)
    iv = find_iverilog(c)
    td = find_td_home(c)
    # only cache the simulator paths; TD details are owned by fpga-td-build/scripts/find_tools.py
    changed = False
    for k, v in (("modelsim_bin", ms and fwd(ms)), ("iverilog_bin", iv and fwd(Path(iv).parent))):
        if v and c.get(k) != v:
            c[k] = v
            changed = True
    if changed:
        _save_cache(c)

    sim = args.sim
    if args.gui:
        sim = "modelsim"
    if sim == "auto":
        sim = "modelsim" if ms else ("iverilog" if iv else None)
    if sim == "modelsim" and not ms:
        print("ModelSim not found (MODELSIM_HOME / PATH / C:\\modeltech64_*). Blocked.", file=sys.stderr); return 127
    if sim == "iverilog" and not iv:
        print("iverilog not found (IVERILOG_HOME / PATH / C:\\iverilog). Blocked.", file=sys.stderr); return 127
    if sim is None:
        print("No simulator found. Blocked.", file=sys.stderr); return 127
    if sim == "iverilog" and args.anlogic_lib:
        print("Anlogic primitives cannot be simulated with iverilog; use --sim modelsim.", file=sys.stderr); return 127

    defines = ["SIMULATION"] + (["DUMP_VARS"] if args.vcd else []) + args.define
    compile_log = SIM / "compile.log"
    sim_log = SIM / "sim.log"
    result = {"simulator": sim, "tb_top": args.tb_top, "rtl_files": [fwd(Path(f).relative_to(ROOT)) for f in rtl],
              "tb_files": [fwd(Path(f).relative_to(ROOT)) for f in tb], "compile_log": "sim/compile.log",
              "sim_log": None, "vcd_path": None, "status": None, "details": []}
    vcd = SIM / "wave.vcd"
    if args.vcd and vcd.exists():
        vcd.unlink()

    with compile_log.open("w", encoding="utf-8") as clog:
        if sim == "iverilog":
            out = SIM / f"{args.tb_top}.vvp"
            cmd = [iv, "-g2012", "-Wall", "-I", fwd(ROOT / "rtl"), "-I", fwd(ROOT / "tb"), "-s", args.tb_top]
            for d in defines:
                cmd += ["-D", d]
            cmd += ["-o", fwd(out)] + [fwd(f) for f in rtl + tb]
            rc, _ = run(cmd, clog, "iverilog")
        else:
            vlib, vlog = str(Path(ms) / _exe("vlib")), str(Path(ms) / _exe("vlog"))
            if not (SIM / "work").exists():
                run([vlib, "work"], clog, "vlib work")
            rc = 0
            if args.anlogic_lib:
                if not td:
                    clog.write("WARNING: --anlogic-lib requested but TD sim_release not found; skipping\n")
                else:
                    libs = []
                    for sub in ("al", "eg"):
                        libs += sorted(glob.glob(str(Path(td) / "sim_release" / sub / "*.v")))
                    rc, _ = run([vlog, "-work", "work", "-incr"] + [fwd(f) for f in libs], clog, "vlog anlogic sim_release")
            if rc == 0:
                cmd = [vlog, "-work", "work", "+incdir+" + fwd(ROOT / "rtl"), "+incdir+" + fwd(ROOT / "tb")]
                cmd += ["+define+" + d for d in defines] + [fwd(f) for f in rtl + tb]
                rc, _ = run(cmd, clog, "vlog")

    if rc != 0:
        result.update(status="COMPILE_FAIL", details=[f"compile exit code {rc}"])
        (SIM / "sim_result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
        print("COMPILE_FAIL  (see sim/compile.log)")
        return 1
    if not args.run:
        result.update(status="COMPILE_PASS")
        (SIM / "sim_result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
        print("COMPILE_PASS")
        return 0

    with sim_log.open("w", encoding="utf-8") as slog:
        try:
            if sim == "iverilog":
                vvp = str(Path(iv).parent / _exe("vvp"))
                rc, text = run([vvp, fwd(SIM / f"{args.tb_top}.vvp")], slog, "vvp", timeout=args.timeout)
            else:
                vsim = str(Path(ms) / _exe("vsim"))
                if args.gui:
                    wave_do = SIM / "modelsim" / "wave.do"
                    do = f"do {fwd(wave_do)}; run -all" if wave_do.exists() else "add wave -r /*; run -all"
                    cmd = [vsim, "-gui", "-voptargs=+acc", f"work.{args.tb_top}", "-do", do]
                else:
                    cmd = [vsim, "-c", "-voptargs=+acc", f"work.{args.tb_top}", "-do", "run -all; quit -f"]
                rc, text = run(cmd, slog, "vsim", timeout=None if args.gui else args.timeout)
        except subprocess.TimeoutExpired:
            rc, text = 1, "TIMEOUT: simulator killed by run_sim.py"
            slog.write(text + "\n")

    status, details = judge(text, rc)
    result.update(status=status, details=details, sim_log="sim/sim.log",
                  vcd_path="sim/wave.vcd" if (args.vcd and vcd.exists()) else None)
    (SIM / "sim_result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(f"{status}  (sim/sim.log)" + (f"  vcd: sim/wave.vcd" if result["vcd_path"] else ""))
    for d in details[:10]:
        print("  " + d)
    return 0 if status == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())

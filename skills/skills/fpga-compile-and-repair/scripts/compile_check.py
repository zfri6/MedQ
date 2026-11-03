#!/usr/bin/env python
"""Syntax/elaboration check for rtl/ + tb/ using iverilog (fast) and/or ModelSim vlog (authoritative).

Usage (run from project root):
  python <skill>/scripts/compile_check.py                    # auto: iverilog if present, then vlog if present
  python <skill>/scripts/compile_check.py --tool iverilog
  python <skill>/scripts/compile_check.py --tool modelsim --tb-top tb_top
  python <skill>/scripts/compile_check.py --with-anlogic-lib # add <TD_HOME>/sim_release/{al,eg} for IP designs

Outputs:
  sim/compile.log          raw tool output (all tools appended, separated by headers)
  sim/compile_result.json  {"status": "PASS|FAIL|NO_TOOL", "tools": {...}}
Exit code: 0 on PASS, 1 on FAIL, 127 when no requested tool is available.
"""
import argparse
import glob
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path.cwd()
TOOLCHAIN_JSON = ROOT / "doc" / "hw" / "toolchain.json"


# ---------------------------------------------------------------- tool discovery
def _first_existing(paths):
    for p in paths:
        if p and Path(p).exists():
            return str(Path(p))
    return None


def load_toolchain_cache():
    if TOOLCHAIN_JSON.exists():
        try:
            return json.loads(TOOLCHAIN_JSON.read_text(encoding="utf-8"))
        except Exception:
            return {}
    return {}


def save_toolchain_cache(data):
    TOOLCHAIN_JSON.parent.mkdir(parents=True, exist_ok=True)
    TOOLCHAIN_JSON.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def find_iverilog(cache):
    exe = "iverilog.exe" if os.name == "nt" else "iverilog"
    home = os.environ.get("IVERILOG_HOME")
    cands = [
        cache.get("iverilog_bin") and str(Path(cache["iverilog_bin"]) / exe),
        home and str(Path(home) / "bin" / exe),
        shutil.which("iverilog"),
        r"C:\iverilog\bin\iverilog.exe",
    ]
    return _first_existing(cands)


def find_modelsim(cache):
    """Return directory containing vlog/vsim executables."""
    exe = "vlog.exe" if os.name == "nt" else "vlog"
    home = os.environ.get("MODELSIM_HOME")
    cands = [cache.get("modelsim_bin")]
    if home:
        cands += [home, str(Path(home) / "win64"), str(Path(home) / "win32aloem"), str(Path(home) / "bin")]
    w = shutil.which("vlog")
    if w:
        cands.append(str(Path(w).parent))
    for pat in (r"C:\modeltech64_*\win64", r"C:\modeltech*\win32", r"C:\intelFPGA*\*\modelsim_ase\win32aloem",
                r"C:\intelFPGA*\*\modelsim_ae\win64", r"D:\modeltech64_*\win64"):
        cands += sorted(glob.glob(pat), reverse=True)
    for d in cands:
        if d and (Path(d) / exe).exists():
            return str(Path(d))
    return None


def find_td_home(cache):
    cands = [os.environ.get("TD_HOME"), cache.get("td_home"), (cache.get("td") or {}).get("td_home")]
    w = shutil.which("td")
    if w:
        cands.append(str(Path(w).parent.parent))
    for pat in (r"C:\Anlogic\TD*", r"D:\Anlogic\TD*", r"C:\Program Files\Anlogic\TD*"):
        cands += sorted(glob.glob(pat), reverse=True)
    for d in cands:
        if d and (Path(d) / "sim_release").exists():
            return str(Path(d))
    return None


def anlogic_sim_files(td_home):
    files = []
    for sub in ("al", "eg"):
        files += sorted(glob.glob(str(Path(td_home) / "sim_release" / sub / "*.v")))
    return files


# ---------------------------------------------------------------- helpers
def collect_sources(rtl_dir, tb_dir):
    rtl = sorted(glob.glob(str(ROOT / rtl_dir / "**" / "*.v"), recursive=True))
    tb = sorted(glob.glob(str(ROOT / tb_dir / "*.v"))) + sorted(glob.glob(str(ROOT / tb_dir / "*.sv")))
    return [str(Path(p).relative_to(ROOT)) for p in rtl], [str(Path(p).relative_to(ROOT)) for p in tb]


def run(cmd, cwd, log_fh, header):
    log_fh.write(f"\n===== {header} =====\n$ {' '.join(cmd)}\n(cwd={cwd})\n")
    log_fh.flush()
    proc = subprocess.run(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                          encoding="utf-8", errors="replace")
    log_fh.write(proc.stdout)
    log_fh.write(f"\n[exit code {proc.returncode}]\n")
    log_fh.flush()
    return proc.returncode, proc.stdout


def fwd(p):
    return str(p).replace("\\", "/")


# ---------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--tool", choices=["auto", "iverilog", "modelsim", "both"], default="auto")
    ap.add_argument("--tb-top", default="tb_top", help="TB top module (default tb_top). Use '' to skip -s/top check")
    ap.add_argument("--rtl", default="rtl")
    ap.add_argument("--tb", default="tb")
    ap.add_argument("--out", default="sim")
    ap.add_argument("--with-anlogic-lib", "--include-al-ip", "--with-al-ip", dest="with_anlogic_lib", action="store_true",
                    help="compile <TD_HOME>/sim_release/al,eg models too (needed when rtl/al_ip is used; ModelSim only)")
    ap.add_argument("--rtl-only", action="store_true", help="compile rtl/ only (no tb/, no top-module check)")
    ap.add_argument("--define", action="append", default=[], help="extra +define+NAME[=VAL] (repeatable)")
    args = ap.parse_args()

    out_dir = ROOT / args.out
    out_dir.mkdir(parents=True, exist_ok=True)
    log_path = out_dir / "compile.log"
    result_path = out_dir / "compile_result.json"

    rtl_files, tb_files = collect_sources(args.rtl, args.tb)
    if args.rtl_only:
        tb_files = []
        args.tb_top = ""
    if not rtl_files and not tb_files:
        print(f"No sources under {args.rtl}/ or {args.tb}/", file=sys.stderr)
        return 2

    cache = load_toolchain_cache()
    iverilog = find_iverilog(cache)
    modelsim = find_modelsim(cache)
    td_home = find_td_home(cache)
    # cache simulator paths only; TD details are owned by fpga-td-build/scripts/find_tools.py
    changed = False
    if iverilog and cache.get("iverilog_bin") != fwd(Path(iverilog).parent):
        cache["iverilog_bin"] = fwd(Path(iverilog).parent); changed = True
    if modelsim and cache.get("modelsim_bin") != fwd(modelsim):
        cache["modelsim_bin"] = fwd(modelsim); changed = True
    if changed:
        save_toolchain_cache(cache)

    want_iv = args.tool in ("auto", "iverilog", "both")
    want_ms = args.tool in ("auto", "modelsim", "both")
    if args.tool == "iverilog" and not iverilog:
        print("iverilog not found (IVERILOG_HOME / PATH / C:\\iverilog). Blocked.", file=sys.stderr); return 127
    if args.tool == "modelsim" and not modelsim:
        print("ModelSim vlog not found (MODELSIM_HOME / PATH / C:\\modeltech64_*). Blocked.", file=sys.stderr); return 127
    if args.tool == "both" and not (iverilog and modelsim):
        print("--tool both requires iverilog and ModelSim; at least one is missing.", file=sys.stderr); return 127
    if not iverilog and not modelsim:
        print("Neither iverilog nor ModelSim found. Blocked.", file=sys.stderr); return 127

    defines = ["SIMULATION"] + args.define
    tools = {}
    overall_fail = False

    with log_path.open("w", encoding="utf-8") as log:
        if want_iv and iverilog:
            cmd = [iverilog, "-g2012", "-Wall", "-tnull", "-I", args.rtl, "-I", args.tb]
            for d in defines:
                cmd += ["-D", d]
            if args.tb_top:
                cmd += ["-s", args.tb_top]
            cmd += rtl_files + tb_files
            if args.with_anlogic_lib:
                log.write("NOTE: --with-anlogic-lib ignored for iverilog (Anlogic primitives are not iverilog-compatible)\n")
            rc, _ = run(cmd, ROOT, log, "iverilog -tnull")
            tools["iverilog"] = {"exe": iverilog, "exit_code": rc, "status": "PASS" if rc == 0 else "FAIL"}
            overall_fail |= rc != 0

        if want_ms and modelsim:
            vlib = str(Path(modelsim) / ("vlib.exe" if os.name == "nt" else "vlib"))
            vlog = str(Path(modelsim) / ("vlog.exe" if os.name == "nt" else "vlog"))
            work = out_dir / "work"
            if not work.exists():
                run([vlib, "work"], out_dir, log, "vlib work")
            files_rel_sim = [fwd(Path("..") / f) for f in rtl_files + tb_files]
            cmd = [vlog, "-work", "work", "+incdir+../" + args.rtl, "+incdir+../" + args.tb]
            for d in defines:
                cmd.append("+define+" + d)
            if args.with_anlogic_lib:
                if not td_home:
                    log.write("WARNING: --with-anlogic-lib requested but TD_HOME/sim_release not found; skipping Anlogic models\n")
                else:
                    lib_files = anlogic_sim_files(td_home)
                    rc_lib, _ = run([vlog, "-work", "work", "-incr"] + lib_files, out_dir, log, "vlog anlogic sim_release")
                    tools["anlogic_lib"] = {"td_home": td_home, "files": len(lib_files), "exit_code": rc_lib}
            cmd += files_rel_sim
            rc, _ = run(cmd, out_dir, log, "ModelSim vlog")
            tools["modelsim"] = {"bin": modelsim, "exit_code": rc, "status": "PASS" if rc == 0 else "FAIL"}
            overall_fail |= rc != 0

    status = "FAIL" if overall_fail else "PASS"
    result = {
        "status": status,
        "tb_top": args.tb_top,
        "rtl_files": rtl_files,
        "tb_files": tb_files,
        "tools": tools,
        "compile_log": fwd(log_path.relative_to(ROOT)),
    }
    result_path.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"{status}  (log: {result['compile_log']})")
    for name, info in tools.items():
        if "status" in info:
            print(f"  {name}: {info['status']} (exit {info['exit_code']})")
    return 0 if status == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())

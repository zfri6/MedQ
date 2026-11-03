#!/usr/bin/env python
"""Unified simulation runner for this project (copied from fpga-tb-write/templates/run_sim.py).

Run from the project root:
  python sim/run_sim.py                       # compile only (ModelSim vlog if available, else iverilog)
  python sim/run_sim.py --run                 # compile + run, PASS/FAIL from TB $display
  python sim/run_sim.py --run --vcd           # also dump sim/wave.vcd via +define+DUMP_VARS
  python sim/run_sim.py --run --sim iverilog  # force simulator
  python sim/run_sim.py --run --anlogic-lib   # add <TD_HOME>/sim_release/{al,eg} (designs using rtl/al_ip IP)
  python sim/run_sim.py --gui                 # open ModelSim GUI with sim/modelsim/wave.do
  python sim/run_sim.py --tb-top TB_NAME      # specify top module (default: tb_top)
    5 个 TB: tb_rst_sync | tb_key_debounce | tb_cdc_bus_handshake | tb_sdram_arbiter | tb_hdmi_tmds_encoder

Tool paths come from doc/hw/toolchain.json, env vars (MODELSIM_HOME / IVERILOG_HOME / TD_HOME), PATH, then common install dirs.

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

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

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


def sources(tb_top=TB_TOP_DEFAULT, anlogic_lib=False):
    rtl = sorted(glob.glob(str(ROOT / "rtl" / "**" / "*.v"), recursive=True))
    # The encrypted legacy SDRAM profile has its own source-traced runner.
    # Open-source behavioral regression never parses protected vendor sources.
    rtl = [f for f in rtl if 'sdram_vendor' not in Path(f).parts]
    # The generated clk_wize wrapper requires EG primitives unavailable to iverilog.
    # Keep the generated FIFO wrapper; simulation supplies clk_wize/pll_mem stubs in tb/.
    if not anlogic_lib:
        rtl = [f for f in rtl if Path(f).name not in ("clk_wize.v", "medq_pll.v", "sys_pll.v", "sdram.v")]
    all_tb = sorted(glob.glob(str(ROOT / "tb" / "*.v"))) + sorted(glob.glob(str(ROOT / "tb" / "*.sv")))
    support = [f for f in all_tb if Path(f).name.endswith("_model.v")
               or (Path(f).name == "sim_anlogic_stubs.v" and not anlogic_lib)]
    selected = [f for f in all_tb if Path(f).stem == tb_top]
    if not selected:
        raise ValueError(f"testbench source not found: tb/{tb_top}.v")
    tb = support + selected
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
    bad = [l for l in lines if re.match(r"^(#\s*)?(FAIL|ERROR|TIMEOUT|FATAL)\b", l)
           or re.search(r"\*\*\s+(Error|Fatal)\b|Fatal:", l)]
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
    ap.add_argument("--tb-top", default=os.environ.get("TB_TOP", TB_TOP_DEFAULT),
                    help="top-level module (default: tb_top). For MedQ key modules use:\n"
                         "  tb_rst_sync | tb_key_debounce | tb_cdc_bus_handshake | tb_sdram_arbiter | tb_hdmi_tmds_encoder")
    ap.add_argument("--anlogic-lib", "--with-al-ip", dest="anlogic_lib", action="store_true",
                    help="compile rtl/al_ip wrappers + <TD_HOME>/sim_release models (ModelSim only)")
    ap.add_argument("--define", action="append", default=[], help="extra +define+NAME[=VAL]")
    ap.add_argument("--timeout", type=int, default=600, help="seconds before the simulator is killed")
    ap.add_argument("--output-dir", help="project-relative directory for this test's logs and executable")
    args = ap.parse_args()
    if args.vcd or args.gui:
        args.run = True
    if args.compile_only:
        args.run = False

    SIM.mkdir(parents=True, exist_ok=True)
    try:
        rtl, tb = sources(args.tb_top, args.anlogic_lib)
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 2
    if not rtl or not tb:
        print("Need at least one file in rtl/ and tb/.", file=sys.stderr)
        return 2

    c = _cache()
    ms = find_modelsim(c)
    iv = find_iverilog(c)
    td = find_td_home(c)
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

    # ModelSim 10.4 uses ANSI paths internally. Stage only simulation inputs to
    # an ASCII path, retain a separate work library per TB, and copy logs back.
    output = ROOT / args.output_dir if args.output_dir else SIM
    output.mkdir(parents=True, exist_ok=True)
    run_dir = output
    if sim == "modelsim":
        import hashlib
        import tempfile
        tag = hashlib.sha256(str(ROOT).encode("utf-8")).hexdigest()[:12]
        stage = Path(os.environ.get("MEDQ_SIM_ROOT", Path(tempfile.gettempdir()) / "medq_sim")) / tag
        if not str(stage).isascii():
            print("Set MEDQ_SIM_ROOT to an ASCII path for ModelSim 10.4", file=sys.stderr)
            return 2
        for f in rtl + tb:
            dest = stage / Path(f).relative_to(ROOT)
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(f, dest)
        for f in list((ROOT / "rtl").glob("*.hex")) + list((ROOT / "rtl").glob("*.vh")):
            shutil.copy2(f, stage / "rtl" / f.name)
        rtl = [str(stage / Path(f).relative_to(ROOT)) for f in rtl]
        tb = [str(stage / Path(f).relative_to(ROOT)) for f in tb]
        run_dir = stage / "sim" / args.tb_top
        run_dir.mkdir(parents=True, exist_ok=True)
        include_root = stage
    else:
        include_root = ROOT
    # ROM paths resolve from the simulation working directory in both engines.
    for f in list((ROOT / "rtl").glob("*.hex")) + list((ROOT / "tb").glob("*.hex")):
        if f.resolve() != (run_dir / f.name).resolve():
            shutil.copy2(f, run_dir / f.name)

    defines = ["SIMULATION"] + (["DUMP_VARS"] if args.vcd else []) + args.define
    compile_log = output / "compile.log"
    sim_log = output / "sim.log"
    result = {"simulator": sim, "tb_top": args.tb_top, "model_profile": "vendor" if args.anlogic_lib else "behavioral",
              "rtl_files": [fwd(Path(f).relative_to(include_root)) for f in rtl],
              "tb_files": [fwd(Path(f).relative_to(include_root)) for f in tb], "compile_log": fwd(compile_log.relative_to(ROOT)),
              "sim_log": None, "vcd_path": None, "status": None, "details": []}
    vcd = run_dir / "wave.vcd"
    if args.tb_top == "tb_top":
        (run_dir / "top_frame.ppm").unlink(missing_ok=True)
    if args.vcd and vcd.exists():
        vcd.unlink()

    with compile_log.open("w", encoding="utf-8") as clog:
        if sim == "iverilog":
            out = run_dir / f"{args.tb_top}.vvp"
            cmd = [iv, "-g2012", "-Wall", "-I", fwd(ROOT / "rtl"), "-I", fwd(ROOT / "tb"), "-s", args.tb_top]
            for d in defines:
                cmd += ["-D", d]
            cmd += ["-o", fwd(out)] + [fwd(f) for f in rtl + tb]
            rc, _ = run(cmd, clog, "iverilog", cwd=run_dir, timeout=args.timeout)
        else:
            vlib, vlog = str(Path(ms) / _exe("vlib")), str(Path(ms) / _exe("vlog"))
            if not (run_dir / "work").exists():
                run([vlib, "work"], clog, "vlib work", cwd=run_dir)
            rc = 0
            if args.anlogic_lib:
                if not td:
                    clog.write("ERROR: --anlogic-lib requested but TD sim_release not found\n")
                    rc = 127
                else:
                    libs = []
                    for sub in ("al", "eg"):
                        libs += sorted(glob.glob(str(Path(td) / "sim_release" / sub / "*.v")))
                    rc, _ = run([vlog, "-work", "work", "-incr"] + [fwd(f) for f in libs], clog, "vlog anlogic sim_release", cwd=run_dir)
            if rc == 0:
                cmd = [vlog, "-work", "work", "+incdir+" + fwd(include_root / "rtl"), "+incdir+" + fwd(include_root / "tb")]
                cmd += ["+define+" + d for d in defines] + [fwd(f) for f in rtl]
                rc, _ = run(cmd, clog, "vlog", cwd=run_dir, timeout=args.timeout)
                if rc == 0:
                    cmd = [vlog, "-sv", "-work", "work", "+incdir+" + fwd(include_root / "tb")]
                    cmd += ["+define+" + d for d in defines] + [fwd(f) for f in tb]
                    rc, _ = run(cmd, clog, "vlog testbench", cwd=run_dir, timeout=args.timeout)

    if rc != 0:
        result.update(status="COMPILE_FAIL", details=[f"compile exit code {rc}"])
        (output / "sim_result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
        print(f"COMPILE_FAIL  (see {compile_log.relative_to(ROOT).as_posix()})")
        return 1
    if not args.run:
        result.update(status="COMPILE_PASS")
        (output / "sim_result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
        print("COMPILE_PASS")
        return 0

    with sim_log.open("w", encoding="utf-8") as slog:
        try:
            if sim == "iverilog":
                vvp = str(Path(iv).parent / _exe("vvp"))
                rc, text = run([vvp, fwd(run_dir / f"{args.tb_top}.vvp")], slog, "vvp", cwd=run_dir, timeout=args.timeout)
            else:
                vsim = str(Path(ms) / _exe("vsim"))
                if args.gui:
                    wave_do = SIM / "modelsim" / "wave.do"
                    do = f"do {fwd(wave_do)}; run -all" if wave_do.exists() else "add wave -r /*; run -all"
                    cmd = [vsim, "-gui", "-voptargs=+acc", f"work.{args.tb_top}", "-do", do]
                else:
                    # Large board-pin media tests reference every required
                    # observation explicitly in Verilog. Omitting debugger-only
                    # +acc retains all self-checks and matches the native SDRAM
                    # runner, without retaining millions of unused RAM handles.
                    cmd = [vsim, "-c"]
                    if args.tb_top != "tb_media_top":cmd += ["-voptargs=+acc"]
                    cmd += [f"work.{args.tb_top}", "-do", "run -all; quit -f"]
                rc, text = run(cmd, slog, "vsim", cwd=run_dir, timeout=None if args.gui else args.timeout)
        except subprocess.TimeoutExpired:
            rc, text = 1, "TIMEOUT: simulator killed by run_sim.py"
            slog.write(text + "\n")

    status, details = judge(text, rc)
    if args.vcd and vcd.exists() and vcd.resolve() != (output / "wave.vcd").resolve():
        shutil.copy2(vcd, output / "wave.vcd")
    for artifact in run_dir.glob("*.ppm"):
        if artifact.resolve() != (output / artifact.name).resolve():
            shutil.copy2(artifact, output / artifact.name)
    result.update(status=status, details=details, sim_log=fwd(sim_log.relative_to(ROOT)),
                  vcd_path=fwd((output / "wave.vcd").relative_to(ROOT)) if (args.vcd and vcd.exists()) else None)
    (output / "sim_result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(f"{status}  ({sim_log.relative_to(ROOT).as_posix()})" + (f"  vcd: {result['vcd_path']}" if result["vcd_path"] else ""))
    for d in details[:10]:
        print("  " + d)
    return 0 if status == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())

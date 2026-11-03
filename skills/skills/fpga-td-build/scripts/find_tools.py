#!/usr/bin/env python
"""Locate Anlogic TD, ModelSim and Icarus Verilog on this machine and write doc/hw/toolchain.json.

Usage:
    python find_tools.py [--out doc/hw/toolchain.json] [--td-home DIR] [--quiet]

Exit code 0 when TD is found, 2 when TD is missing (the file is still written so
simulation-only flows can proceed), 1 on unexpected errors.
"""
import argparse
import glob
import json
import os
import shutil
import sys
from pathlib import Path

DEFAULT_DEVICE = {"family": "EG4", "device": "EG4S20BG256", "device_db": "eagle_s20.db", "package": "BG256"}

TD_CANDIDATES = [r"C:\Anlogic\TD*", r"D:\Anlogic\TD*", r"C:\Program Files\Anlogic\TD*", r"C:\TD*", r"D:\TD*"]
MODELSIM_CANDIDATES = [r"C:\modeltech64_*\win64", r"C:\modeltech_*\win32", r"C:\intelFPGA*\*\modelsim_ase\win32aloem",
                       r"C:\intelFPGA*\*\modelsim_ae\win32aloem", r"C:\questasim*\win64", r"D:\modeltech64_*\win64"]
IVERILOG_CANDIDATES = [r"C:\iverilog\bin", r"D:\iverilog\bin"]


def first_existing(patterns, must_contain):
    for pat in patterns:
        for hit in sorted(glob.glob(pat), reverse=True):
            if all((Path(hit) / f).exists() for f in must_contain):
                return Path(hit)
    return None


def from_path(exe):
    found = shutil.which(exe)
    return Path(found).parent if found else None


def locate_td(explicit):
    if explicit and (Path(explicit) / "bin" / "td.exe").exists():
        return Path(explicit)
    env = os.environ.get("TD_HOME")
    if env and (Path(env) / "bin" / "td.exe").exists():
        return Path(env)
    on_path = from_path("td.exe")
    if on_path:
        return on_path.parent
    return first_existing(TD_CANDIDATES, ["bin/td.exe"])


def locate_modelsim():
    env = os.environ.get("MODELSIM_HOME")
    if env and (Path(env) / "vsim.exe").exists():
        return Path(env)
    on_path = from_path("vsim.exe")
    if on_path:
        return on_path
    return first_existing(MODELSIM_CANDIDATES, ["vsim.exe", "vlog.exe"])


def locate_iverilog():
    env = os.environ.get("IVERILOG_HOME")
    if env and (Path(env) / "iverilog.exe").exists():
        return Path(env)
    on_path = from_path("iverilog.exe")
    if on_path:
        return on_path
    return first_existing(IVERILOG_CANDIDATES, ["iverilog.exe", "vvp.exe"])


def td_details(td_home):
    if not td_home:
        return {}
    arch = td_home / "arch"
    dbs = sorted(p.name for p in arch.glob("*.db")) if arch.exists() else []
    sim_release = td_home / "sim_release"
    sim_dirs = {d.name: str(d).replace("\\", "/") for d in sim_release.iterdir() if d.is_dir()} if sim_release.exists() else {}
    device_db = DEFAULT_DEVICE["device_db"]
    warnings = []
    if dbs and device_db not in dbs:
        eagle = [d for d in dbs if "eagle" in d.lower() and "s20" in d.lower()]
        if eagle:
            device_db = eagle[0]
            warnings.append(f"default device_db not found; using {device_db} from <TD_HOME>/arch")
        else:
            warnings.append(f"{device_db} not found in <TD_HOME>/arch; available: {', '.join(dbs[:10])}")
    return {"td_home": str(td_home).replace("\\", "/"), "td_exe": str(td_home / "bin" / "td.exe").replace("\\", "/"),
            "device_db": device_db, "arch_dbs": dbs, "sim_release": sim_dirs, "warnings": warnings}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="doc/hw/toolchain.json")
    ap.add_argument("--td-home")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    td_home = locate_td(args.td_home)
    modelsim = locate_modelsim()
    iverilog = locate_iverilog()

    info = {"target": DEFAULT_DEVICE, "td": td_details(td_home) if td_home else None,
            "modelsim_bin": str(modelsim).replace("\\", "/") if modelsim else None,
            "iverilog_bin": str(iverilog).replace("\\", "/") if iverilog else None,
            "workspace_ascii": Path.cwd().resolve().as_posix().isascii()}

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(info, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    if not args.quiet:
        print(f"TD       : {info['td']['td_exe'] if info['td'] else 'NOT FOUND'}")
        print(f"ModelSim : {info['modelsim_bin'] or 'NOT FOUND'}")
        print(f"iverilog : {info['iverilog_bin'] or 'NOT FOUND'}")
        if info["td"]:
            for w in info["td"]["warnings"]:
                print(f"WARNING  : {w}")
        if not info["workspace_ascii"]:
            print("WARNING  : workspace path contains non-ASCII characters; run TD via --mirror to an ASCII directory")
        print(f"written  : {out}")
    return 0 if td_home else 2


if __name__ == "__main__":
    sys.exit(main())

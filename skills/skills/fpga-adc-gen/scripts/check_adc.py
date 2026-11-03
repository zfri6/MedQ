#!/usr/bin/env python
"""Cross-check an Anlogic .adc file against the RTL top-level ports and doc/hw/extracted_facts.json.

Usage:
    python check_adc.py --top top [--rtl rtl/top.v] [--adc prj/constr/top.adc] [--facts doc/hw/extracted_facts.json]

Checks:
  * every RTL top port bit has a set_pin_assignment (or LOCATION = virtualIO)
  * every .adc signal exists in the RTL top
  * no LOCATION is used twice
  * every real pin has an IOSTANDARD (TODO/UNKNOWN reported)
  * every LOCATION appears in extracted_facts.json pin_map (when the file exists)
Exit 0 when clean, 1 when problems were found, 2 on usage errors.
"""
import argparse
import json
import re
import sys
from pathlib import Path

KEYWORDS = r"(?!(?:input|output|inout|wire|reg|signed|parameter)\b)"
PORT_RE = re.compile(r"\b(input|output|inout)\b\s*(?:wire|reg)?\s*(?:signed)?\s*(?:\[\s*([^:\]]+)\s*:\s*([^\]]+)\s*\])?\s*"
                     r"(" + KEYWORDS + r"[A-Za-z_]\w*(?:\s*,\s*" + KEYWORDS + r"[A-Za-z_]\w*)*)", re.S)
ADC_RE = re.compile(r"^\s*set_pin_assignment\s*\{\s*([^}]+?)\s*\}\s*\{\s*([^}]*)\}", re.M)


def find_module(text, top):
    m = re.search(r"\bmodule\s+" + re.escape(top) + r"\b(.*?)\bendmodule\b", text, re.S)
    return m.group(1) if m else None


def eval_int(expr, params):
    expr = expr.strip()
    for k, v in params.items():
        expr = re.sub(r"\b" + re.escape(k) + r"\b", str(v), expr)
    expr = re.sub(r"\d+'[dD](\d+)", r"\1", expr)
    if not re.fullmatch(r"[\d\s+\-*/()]+", expr):
        return None
    try:
        return int(eval(expr))  # constant arithmetic only, validated by the regex above
    except Exception:
        return None


def top_ports(rtl_text, top):
    body = find_module(rtl_text, top)
    if body is None:
        return None
    header = body.split(");", 1)[0]
    params = {m.group(1): int(m.group(2)) for m in re.finditer(r"parameter\s+(?:\[[^\]]*\]\s*)?(\w+)\s*=\s*(\d+)", body)}
    bits = []
    for m in PORT_RE.finditer(header):
        hi, lo, names = m.group(2), m.group(3), m.group(4)
        for name in [n.strip() for n in names.split(",")]:
            if hi is None:
                bits.append(name)
                continue
            h, l = eval_int(hi, params), eval_int(lo, params)
            if h is None or l is None:
                bits.append(f"{name}[?]")
                continue
            bits.extend(f"{name}[{i}]" for i in range(min(h, l), max(h, l) + 1))
    return bits


def parse_adc(text):
    entries = []
    for m in ADC_RE.finditer(text):
        sig = re.sub(r"\s+", "", m.group(1))
        attrs = {}
        for kv in m.group(2).split(";"):
            if "=" in kv:
                k, v = kv.split("=", 1)
                attrs[k.strip().upper()] = v.strip()
        entries.append((sig, attrs))
    return entries


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--top", required=True)
    ap.add_argument("--rtl")
    ap.add_argument("--adc", default="prj/constr/top.adc")
    ap.add_argument("--facts", default="doc/hw/extracted_facts.json")
    args = ap.parse_args()

    rtl_files = [Path(args.rtl)] if args.rtl else sorted(Path("rtl").glob("*.v"))
    ports = None
    for f in rtl_files:
        ports = top_ports(f.read_text(encoding="utf-8", errors="replace"), args.top)
        if ports is not None:
            break
    if ports is None:
        print(f"module {args.top} not found in {[str(f) for f in rtl_files]}", file=sys.stderr)
        return 2
    if not Path(args.adc).exists():
        print(f"{args.adc} not found", file=sys.stderr)
        return 2
    entries = parse_adc(Path(args.adc).read_text(encoding="utf-8", errors="replace"))

    known_pins = set()
    if Path(args.facts).exists():
        facts = json.loads(Path(args.facts).read_text(encoding="utf-8"))
        known_pins = {e.get("package_pin") for e in facts.get("pin_map", []) if e.get("package_pin")}

    problems = []
    adc_sigs = {sig for sig, _ in entries}
    for p in ports:
        if p not in adc_sigs:
            problems.append(f"RTL port without pin assignment: {p}")
    for sig, _ in entries:
        if sig not in ports:
            problems.append(f".adc signal not a top-level port bit: {sig}")
    seen = {}
    for sig, attrs in entries:
        loc = attrs.get("LOCATION")
        if not loc:
            problems.append(f"{sig}: missing LOCATION")
            continue
        if loc.lower() == "virtualio":
            continue
        if loc in seen:
            problems.append(f"duplicate LOCATION {loc}: {seen[loc]} and {sig}")
        seen[loc] = sig
        iostd = attrs.get("IOSTANDARD", "")
        if not iostd or iostd.upper() in ("TODO", "UNKNOWN"):
            problems.append(f"{sig}: IOSTANDARD not resolved ({iostd or 'missing'})")
        if known_pins and loc not in known_pins:
            problems.append(f"{sig}: LOCATION {loc} not present in {args.facts} pin_map")

    print(f"ports: {len(ports)}, adc entries: {len(entries)}, problems: {len(problems)}")
    for p in problems:
        print("  - " + p)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())

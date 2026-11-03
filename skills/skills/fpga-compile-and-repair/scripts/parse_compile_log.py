#!/usr/bin/env python
"""Parse iverilog / ModelSim (vlog, vsim) / Anlogic TD logs into JSON diagnostics.

Usage:
  python parse_compile_log.py sim/compile.log
  python parse_compile_log.py sim/compile.log --out sim/compile_diag.json
  type sim/compile.log | python parse_compile_log.py -
"""
import argparse
import json
import re
import sys
from pathlib import Path

PATTERNS = [
    # iverilog:  rtl/foo.v:12: error: ...   /  rtl/foo.v:12: syntax error
    ("iverilog", re.compile(
        r"^(?P<file>[^:\s][^:]*\.(?:s?v|vh)):(?P<line>\d+):(?:(?P<col>\d+):)?\s*(?P<severity>error|warning|syntax error|fatal|sorry)[:\s]+(?P<message>.*)$",
        re.I)),
    ("iverilog", re.compile(r"^(?P<file>[^:\s][^:]*\.(?:s?v|vh)):(?P<line>\d+):\s*(?P<message>.*syntax error.*)$", re.I)),
    # ModelSim vlog:  ** Error: (vlog-13069) C:/x/rtl/foo.v(12): near "x": syntax error ...
    #                 ** Error: C:/x/rtl/foo.v(12): (vlog-2730) Undefined variable: y.
    #                 ** Warning: C:/x/tb/tb.v(30): (vlog-2240) ...
    ("modelsim", re.compile(
        r"^\*\*\s*(?P<severity>Error|Warning|Fatal|Note)(?:\s*\((?:suppressible|vlog-\d+|vsim-\d+)\))?:\s*(?:\((?P<code>v(?:log|sim|opt)-\d+)\)\s*)?(?P<file>[^(\s][^(]*\.(?:s?v|vh|do))\((?P<line>\d+)\):\s*(?P<message>.*)$",
        re.I)),
    # ModelSim without file reference:  ** Error: (vsim-3033) ... / ** Fatal: ...
    ("modelsim", re.compile(r"^\*\*\s*(?P<severity>Error|Fatal)(?:\s*\((?P<code>v(?:log|sim|opt)-\d+)\))?:\s*(?P<message>.*)$", re.I)),
    # Anlogic TD:  ERROR: ... foo.v(12) ...  /  ERROR (EX1234): ... / WARNING: ...
    ("td", re.compile(
        r"^(?P<severity>ERROR|WARNING|CRITICAL WARNING)(?:\s*\((?P<code>[A-Z]+\d+)\))?\s*:\s*(?P<message>.*?(?P<file>[\w./\\-]+\.(?:s?v|vh|adc|sdc))\((?P<line>\d+)\).*)$")),
    ("td", re.compile(r"^(?P<severity>ERROR|CRITICAL WARNING)(?:\s*\((?P<code>[A-Z]+\d+)\))?\s*:\s*(?P<message>.*)$")),
    # Verilator (in case): %Error: file.v:12:3: msg
    ("verilator", re.compile(r"^%(?P<severity>Error|Warning|Fatal)[^:]*:\s*(?P<file>[^:]+):(?P<line>\d+):(?:(?P<col>\d+):)?\s*(?P<message>.*)$", re.I)),
]

SEVERITY_MAP = {"syntax error": "error", "sorry": "error", "fatal": "error", "critical warning": "warning", "note": "info"}


def parse(text):
    diagnostics = []
    for raw in text.splitlines():
        line = raw.rstrip()
        for tool, pattern in PATTERNS:
            m = pattern.match(line)
            if not m:
                continue
            item = {k: v for k, v in m.groupdict().items() if v is not None}
            item["tool"] = tool
            item["raw"] = line
            item["line"] = int(item["line"]) if item.get("line") else None
            item["col"] = int(item["col"]) if item.get("col") else None
            sev = (item.get("severity") or "error").lower()
            item["severity"] = SEVERITY_MAP.get(sev, sev)
            if "file" in item:
                item["file"] = item["file"].replace("\\", "/")
            diagnostics.append(item)
            break
    return diagnostics


def main():
    ap = argparse.ArgumentParser(description="Parse Verilog tool logs into JSON diagnostics.")
    ap.add_argument("log", nargs="?", default="-")
    ap.add_argument("--out", default="-")
    args = ap.parse_args()
    text = sys.stdin.read() if args.log == "-" else Path(args.log).read_text(encoding="utf-8-sig", errors="replace")
    diags = parse(text.lstrip("\ufeff"))
    data = {
        "diagnostic_count": len(diags),
        "error_count": sum(1 for d in diags if d["severity"] == "error"),
        "warning_count": sum(1 for d in diags if d["severity"] == "warning"),
        "diagnostics": diags,
    }
    output = json.dumps(data, ensure_ascii=False, indent=2)
    if args.out == "-":
        print(output)
    else:
        Path(args.out).write_text(output + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

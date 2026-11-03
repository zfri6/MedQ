#!/usr/bin/env python
"""Run the TD batch flow (prj/td/build.tcl), collect logs and summarize reports.

Usage:
    python run_td.py [--tcl prj/td/build.tcl] [--toolchain doc/hw/toolchain.json]
                     [--mirror D:/work/ascii_copy] [--report-only] [--timeout 1800]

--mirror DIR   copy rtl/, tb/, prj/, doc/hw to DIR (ASCII path), run TD there, copy prj/td/reports and
               prj/td/output back. Needed because TD 6.2 misbehaves on non-ASCII project paths.
--report-only  skip running TD; only parse existing prj/td/reports/* into doc/compile/td_report.md.

Outputs: prj/td/td_run.log, prj/td/reports/summary.json, doc/compile/td_report.md
Exit code: 0 flow finished and no ERROR lines; 1 TD reported errors or timing failure; 127 TD not found.
Report parsing is best-effort: the markdown always embeds the raw tail of every report so the agent can
read the exact TD wording when the regexes miss.
"""
import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path


def load_toolchain(path):
    p = Path(path)
    return json.loads(p.read_text(encoding="utf-8")) if p.exists() else {}


def mirror_to(dst, back=False):
    src_root, dst_root = Path.cwd(), Path(dst)
    if not back:
        for d in ("rtl", "tb", "prj", "doc/hw"):
            if (src_root / d).exists():
                shutil.copytree(src_root / d, dst_root / d, dirs_exist_ok=True)
    else:
        for d in ("prj/td/reports", "prj/td/output"):
            if (dst_root / d).exists():
                shutil.copytree(dst_root / d, src_root / d, dirs_exist_ok=True)
        log = dst_root / "prj/td/td_run.log"
        if log.exists():
            shutil.copy2(log, src_root / "prj/td/td_run.log")


def run_td(td_exe, tcl, cwd, timeout):
    log = Path(cwd, "prj/td/td_run.log")
    cmd = [td_exe, "-f", tcl]
    try:
        proc = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=timeout)
        out, rc = (proc.stdout or "") + (proc.stderr or ""), proc.returncode
    except subprocess.TimeoutExpired as e:
        out, rc = (e.stdout or "") + (e.stderr or "") + "\n[TIMEOUT]\n", 124
    log.parent.mkdir(parents=True, exist_ok=True)
    log.write_text(f"$ {' '.join(cmd)}\n{out}\n[exit {rc}]\n", encoding="utf-8")
    return rc, out


def parse_area(text):
    """Pull 'name used/total (pct%)' style rows out of a TD .area report."""
    rows = {}
    for m in re.finditer(r"^\s*([A-Za-z][\w\s/().-]*?)\s+(\d+)\s*/\s*(\d+)\s*(?:\(?\s*([\d.]+)\s*%\)?)?", text, re.M):
        name = re.sub(r"\s+", " ", m.group(1)).strip()
        used, total = int(m.group(2)), int(m.group(3))
        pct = float(m.group(4)) if m.group(4) else (round(100.0 * used / total, 2) if total else None)
        rows[name] = {"used": used, "total": total, "pct": pct}
    return rows


def parse_timing(text):
    info = {}
    for key, pat in {
        "wns": r"(?:WNS|Worst\s+Negative\s+Slack|Setup\s+Slack|worst\s+slack)[^\-\d]*(-?[\d.]+)",
        "whs": r"(?:WHS|Worst\s+Hold\s+Slack|Hold\s+Slack)[^\-\d]*(-?[\d.]+)",
        "fmax": r"(?:Fmax|Max\s+Frequency|Frequency)[^\d]*([\d.]+)\s*MHz",
        "status": r"Timing\s+Status\s*[:=]?\s*(\w+)",
        "failing_endpoints": r"(?:Failing|Violated)\s+Endpoints?[^\d]*(\d+)",
    }.items():
        m = re.search(pat, text, re.I)
        if m:
            info[key] = m.group(1)
    for k in ("wns", "whs", "fmax"):
        if k in info:
            try:
                info[k] = float(info[k])
            except ValueError:
                pass
    return info


def tail(path, n=40):
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    return "\n".join(lines[-n:])


def summarize(reports_dir, run_log, rc):
    reports = sorted(Path(reports_dir).glob("*"))
    log_text = Path(run_log).read_text(encoding="utf-8", errors="replace") if Path(run_log).exists() else ""
    errors = [l for l in log_text.splitlines() if re.match(r"\s*(ERROR|\*\*\s*Error|Error:)", l)]
    crit = [l for l in log_text.splitlines() if re.match(r"\s*CRITICAL WARNING", l)]
    summary = {"td_exit_code": rc, "flow_done": "TD_FLOW_DONE" in log_text, "error_count": len(errors),
               "errors": errors[:30], "critical_warnings": crit[:30], "area": {}, "timing": {}, "reports": [p.as_posix() for p in reports]}
    for p in reports:
        text = p.read_text(encoding="utf-8", errors="replace")
        if p.suffix == ".area":
            summary["area"][p.name] = parse_area(text)
        elif p.suffix in (".timing", ".ts"):
            summary["timing"][p.name] = parse_timing(text)
    pr = [v for k, v in summary["timing"].items() if k.endswith("_pr.timing") or k.endswith("_phy.ts")]
    wns = [v["wns"] for v in pr if isinstance(v.get("wns"), float)]
    status = [str(v.get("status", "")).upper() for v in pr]
    summary["timing_met"] = None if not pr else (all(w >= 0 for w in wns) if wns else not any("FAIL" in s for s in status))
    bit = sorted(Path(reports_dir).parent.glob("output/*.bit"))
    summary["bitstream"] = bit[0].as_posix() if bit else None
    return summary


def write_markdown(summary, out_md, reports_dir):
    lines = ["# TD 综合/实现报告", "",
             f"- TD 退出码：{summary['td_exit_code']}；流程结束标记：{'是' if summary['flow_done'] else '否'}",
             f"- 错误数：{summary['error_count']}；时序收敛：{ {True: '是', False: '否', None: '无报告'}[summary['timing_met']] }",
             f"- bit 流：{summary['bitstream'] or '未生成'}", ""]
    if summary["errors"]:
        lines += ["## 错误（td_run.log）", "```"] + summary["errors"] + ["```", ""]
    for name, rows in summary["area"].items():
        lines += [f"## 资源：{name}", "", "| 资源 | 已用 | 总量 | 占比 |", "|---|---|---|---|"]
        lines += [f"| {k} | {v['used']} | {v['total']} | {v['pct']}% |" for k, v in rows.items()]
        lines.append("")
    for name, info in summary["timing"].items():
        lines += [f"## 时序：{name}", "", "```json", json.dumps(info, ensure_ascii=False), "```", ""]
    for p in sorted(Path(reports_dir).glob("*")):
        lines += [f"## 原文尾部：{p.name}", "```", tail(p), "```", ""]
    Path(out_md).parent.mkdir(parents=True, exist_ok=True)
    Path(out_md).write_text("\n".join(lines), encoding="utf-8")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tcl", default="prj/td/build.tcl")
    ap.add_argument("--toolchain", default="doc/hw/toolchain.json")
    ap.add_argument("--mirror")
    ap.add_argument("--report-only", action="store_true")
    ap.add_argument("--timeout", type=int, default=1800)
    args = ap.parse_args()

    reports_dir, run_log, out_md = "prj/td/reports", "prj/td/td_run.log", "doc/compile/td_report.md"
    rc = 0
    if not args.report_only:
        tc = load_toolchain(args.toolchain)
        td_exe = (tc.get("td") or {}).get("td_exe")
        if not td_exe or not Path(td_exe).exists():
            print("td.exe not found; run find_tools.py after installing TD 6.2.1 (see rules/30-fpga-toolchain.md)", file=sys.stderr)
            return 127
        if not Path(args.tcl).exists():
            print(f"{args.tcl} not found; run gen_td_project.py first", file=sys.stderr)
            return 2
        cwd = Path.cwd()
        if args.mirror:
            mirror_to(args.mirror)
            cwd = Path(args.mirror)
        elif not cwd.as_posix().isascii():
            print("WARNING: non-ASCII project path; if TD fails to open files, rerun with --mirror <ascii_dir>")
        rc, out = run_td(td_exe, args.tcl, cwd, args.timeout)
        if args.mirror:
            mirror_to(args.mirror, back=True)

    Path(reports_dir).mkdir(parents=True, exist_ok=True)
    summary = summarize(reports_dir, run_log, rc)
    Path(reports_dir, "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    write_markdown(summary, out_md, reports_dir)
    print(f"reports: {len(summary['reports'])}, errors: {summary['error_count']}, timing_met: {summary['timing_met']}, bit: {summary['bitstream']}")
    print(f"written: {out_md}")
    ok = summary["error_count"] == 0 and rc == 0 and summary["timing_met"] is not False
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())

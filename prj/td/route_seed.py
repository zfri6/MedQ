"""Reroute an unchanged native synthesis DB with an explicit placement seed."""
import argparse
import hashlib
import json
import shutil
import subprocess
import tempfile
import uuid
from datetime import datetime, timezone
from pathlib import Path
import medq_td
import signoff_timing

ROOT = medq_td.ROOT


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    group = ap.add_mutually_exclusive_group(required=True)
    group.add_argument('--parent-stage', help='active calibrated build ASCII stage, read-only')
    group.add_argument('--parent-result', help='completed project-relative native result.json')
    ap.add_argument('--seed', type=int, required=True)
    ap.add_argument('--timeout', type=int, default=1800)
    a = ap.parse_args()
    if a.parent_result:
        parent = ROOT / a.parent_result
        raw = json.loads(parent.read_text(encoding='utf-8'))
        meta = raw['meta']
        base = parent.parent
    else:
        base = Path(a.parent_stage) / 'prj/td'
        meta = json.loads((ROOT / 'prj/td/MedQv03_manifest.json').read_text(encoding='utf-8'))
    assert meta['name'] == 'MedQv03' and meta['top'] == 'top'
    signoff_timing.check_hashes(meta['source_sha256'])
    gate = base / 'output/MedQv03_gate.db'
    gate_sha = medq_td.sha(gate)
    tag = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ_') + uuid.uuid4().hex[:8]
    dest = ROOT / 'prj/td/runs' / tag
    stage = Path(tempfile.mkdtemp(prefix=f'medq_seed{a.seed}_'))
    assert stage.as_posix().isascii() and not dest.exists()
    run = stage / 'prj/td'
    (run / 'output').mkdir(parents=True)
    (run / 'reports').mkdir()
    for path in meta['source_sha256']:
        target = stage / path
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / path, target)
    shutil.copy2(gate, run / 'output/MedQv03_gate.db')
    for name in ('MedQv03_gate.area', 'MedQv03_rtl.area'):
        shutil.copy2(base / 'reports' / name, run / 'reports' / name)
    assert medq_td.sha(run / 'output/MedQv03_gate.db') == gate_sha
    script = f'''# Explicit seed follows installed TD doc/scripts/MultiSeed.tcl.
import_db {{prj/td/output/MedQv03_gate.db}}
set_param place seed {a.seed}
legalize_phy_inst
update_timing
set_param route effort routability
place
export_db prj/td/output/MedQv03_place.db
route
fix_hold
report_area -io_info -file prj/td/reports/MedQv03_phy.area
update_timing -mode final
report_timing_status -file prj/td/reports/MedQv03_phy.ts
report_timing_summary -ep_num 500 -file prj/td/reports/MedQv03_pr.timing
report_timing_exception -file prj/td/reports/MedQv03_exception.timing
report_timing_ignored -ep_num 500 -file prj/td/reports/MedQv03_ignored.timing
check_timing -verbose -file prj/td/reports/MedQv03_constraint_health.rpt
export_db prj/td/output/MedQv03_pr.db
puts "MEDQ_STAGE_IMPLEMENTED"
puts "MEDQ_FLOW_DONE_IMPLEMENT"
exit
'''
    tcl = run / 'build_MedQv03.tcl'
    tcl.write_text(script, encoding='utf-8')
    command = [json.loads((ROOT / 'doc/hw/toolchain.json').read_text(encoding='utf-8'))['td']['command_exe'], tcl.as_posix()]
    seed_meta = dict(meta, mode='implement', placement_seed=a.seed, driver_sha256=medq_td.sha(Path(__file__)),
                     tcl_sha256=hashlib.sha256(script.encode('utf-8')).hexdigest())
    dest.mkdir()
    medq_td.dump(dest / 'seed_intake.json', {'meta': seed_meta, 'parent_gate': gate.as_posix(),
                   'parent_gate_sha256': gate_sha, 'stage': stage.as_posix(), 'command': command})
    print('SEED_ROUTE_START', a.seed, dest.relative_to(ROOT).as_posix(), stage.as_posix(), flush=True)
    try:
        p = subprocess.run(command, cwd=stage, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=a.timeout)
        rc, output = p.returncode, p.stdout.decode('utf-8', errors='replace')
    except subprocess.TimeoutExpired as e:
        rc, output = 124, (e.stdout or b'').decode('utf-8', errors='replace') + '\nNATIVE_TIMEOUT\n'
    for qor in stage.glob('*.qor'):
        shutil.copy2(qor, run / 'reports' / ('MedQv03_' + qor.name))
    result = medq_td.judge('implement', 'MedQv03', stage, output, rc)
    assert medq_td.sha(gate) == gate_sha, 'Parent synthesis DB was modified'
    signoff_timing.check_hashes(meta['source_sha256'])
    for path in run.rglob('*'):
        if path.is_file():
            target = dest / path.relative_to(run)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)
    (dest / 'td_run.log').write_text(output, encoding='utf-8')
    result.update(meta=seed_meta, command=command, stage_path=stage.as_posix(), timestamp_utc=tag,
                  parent_gate=gate.as_posix(), parent_gate_sha256=gate_sha,
                  artifacts={p.relative_to(dest).as_posix(): medq_td.sha(p)
                             for p in dest.rglob('*') if p.is_file()})
    medq_td.dump(dest / 'result.json', result)
    medq_td.dump(ROOT / 'prj/td/latest_MedQv03.json', {'status': result['status'], 'result': (dest / 'result.json').relative_to(ROOT).as_posix()})
    print('SEED_ROUTE_END', a.seed, result['status'], (dest / 'result.json').relative_to(ROOT).as_posix(), flush=True)
    return 0 if result['flow_done'] and not result['errors'] else 1


if __name__ == '__main__':
    raise SystemExit(main())

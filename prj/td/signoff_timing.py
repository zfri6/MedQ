"""Audit a frozen routed run, then generate a bitstream only after full checks.

The native routed DB is imported unchanged. Its reports and source hashes are
checked before use; bitgen has an additional in-process native slack gate.
"""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
import medq_td
from timing_evidence import timing_report, resources, route_qor_audit, input_boundary_audit

ROOT = medq_td.ROOT


def read(path):
    return json.loads(path.read_text(encoding='utf-8'))


def text(path):
    return path.read_text(encoding='utf-8', errors='replace')


def check_hashes(items, absolute=False):
    failures = []
    for name, expected in items.items():
        path = Path(name) if absolute else ROOT / name
        if not path.is_file() or medq_td.sha(path) != expected:
            failures.append(name)
    assert not failures, 'Evidence/source drift: ' + ', '.join(failures[:10])


def audit(run_path):
    run = ROOT / run_path
    original = read(run)
    name = original['meta']['name']
    directory = run.parent
    check_hashes(original['meta']['source_sha256'])
    check_hashes({(directory / p).relative_to(ROOT).as_posix(): sha for p, sha in original['artifacts'].items()})
    assert original['exit_code'] == 0 and original['flow_done'] and not original['errors'], 'Failed native flow'
    native_log = text(directory / 'td_run.log')
    assert not medq_td.ERROR.search(native_log), 'Error/crash in native log'
    report = directory / 'reports' / (name + '_pr.timing')
    timing = timing_report(text(report))
    assert timing['format_known'] and timing['met'] and not timing['negative_paths'], 'Native STA is unknown/negative'
    status = text(directory / 'reports' / (name + '_phy.ts'))
    for key, value in timing['values'].items():
        match = re.search(r'\b' + key + r':\s*(-?[\d.]+)ns', status)
        assert match and abs(float(match[1]) - value) < 0.0005, 'Contradictory native status'
    exceptions = text(directory / 'reports' / (name + '_exception.timing'))
    assert not re.search(r'^Slack\s*:\s*-\d', exceptions, re.M), 'Negative exception path'
    ignored = text(directory / 'reports' / (name + '_ignored.timing'))
    # TD expands -datapath_only into hold exclusions for the same exact IO
    # boundary. Enumerate every omitted check; no internal/SIP check may escape.
    inputs = {f'{prefix}[{bit}]' for prefix in ('KEY', 'SW') for bit in range(4)} | {'UART_RX', 'SD_MISO'}
    outputs = {f'{prefix}[{bit}]' for prefix, width in (('LED',4),('SEG_DATA',8),('SEG_SEL',8)) for bit in range(width)}
    outputs |= {'BUZZER','UART_TX','SD_SCLK','SD_MOSI','SD_nCS','HDMI_CLK_P','HDMI_D0_P','HDMI_D1_P','HDMI_D2_P'}
    omitted = []
    for block in re.split(r'(?=^Begin Point\s*:)', ignored, flags=re.M)[1:]:
        begin = re.search(r'^Begin Point\s*:\s*(.*)', block, re.M)[1].split('(triggered')[0].strip()
        end = re.search(r'^End Point\s*:\s*(.*)', block, re.M)[1].split('(triggered')[0].strip()
        kind = re.search(r'^Check Type\s*:\s*(.*)', block, re.M)[1].strip()
        assert kind == 'hold' and (begin in inputs or end in outputs), 'Internal/SIP path excluded: '+begin+' -> '+end
        assert 'u_device/sdram' not in begin+end, 'SIP timing must never be excluded'
        boundary = input_boundary_audit(block, begin, end) if begin in inputs else None
        omitted.append(dict(begin=begin,end=end,check=kind,input_boundary=boundary,reason='IO boundary has a maximum local latency contract, no fictitious external synchronous hold phase'))
    sdc = text(ROOT / 'prj/constr/top.sdc')
    commands = [line.strip() for line in sdc.splitlines() if line.strip() and not line.lstrip().startswith('#')]
    assert not any(re.search(r'\b(set_false_path|set_clock_groups|set_multicycle_path)\b', line) for line in commands), 'Unreviewed timing exception'
    area = resources(text(directory / 'reports' / (name + '_phy.area')))
    assert area and all(row['used'] <= row['available'] for row in area.values()), 'Resource overflow/unknown'
    qor = text(directory / 'reports' / (name + '_route.qor'))
    qor_audit = route_qor_audit(qor, native_log, timing)
    health_path = directory / 'reports' / (name + '_constraint_health.rpt')
    health = text(health_path)
    for label in ('no clock', 'clock definition', 'invalid constraint', 'combinational loops', 'no path constraints', 'shadowed/ignored timing exception constraints'):
        assert re.search(r'checking ' + re.escape(label) + r'\(0\)', health), 'Constraint health issue: ' + label
    assert 'USR-6135' not in native_log, 'Unpredictable PLL feedback compensation'
    critical = [line for line in native_log.splitlines() if 'CRITICAL-WARNING' in line]
    assert all(('PHY-7002' in line and 'u_device/sdram location' in line) or 'PHY-5079' in line for line in critical), 'Unreviewed critical warning'
    if any('PHY-5079' in line for line in critical):
        assert re.search(r'u_sys_pll/pll_inst.clkc\[2\].*0/1.*SDRAM_CLK', native_log), 'Unexpected local clock routing'
    def sip_pads(file):
        pads = {}
        for line in text(file).splitlines():
            fields = line.split()
            if len(fields) >= 8 and re.fullmatch(r'S\d+', fields[2]):
                pads[fields[0]] = fields[1:7]
        return pads
    sip = sip_pads(directory/'reports'/(name+'_phy.area'))
    baseline_sip = sip_pads(ROOT/'baseline/v02_frozen/sdram_sip_baseline.area')
    assert len(sip) == 55 and sip == baseline_sip, 'SDRAM SIP pin binding/electrical settings changed'
    db = directory / 'output' / (name + '_pr.db')
    assert db.is_file() and medq_td.sha(db) == original['artifacts']['output/' + name + '_pr.db']
    result = dict(status='PASS', scope='routed FPGA internal/SIP setup+hold in both corners plus explicitly bounded local IO; external electrical/board tests pending',
                  board_test_status='not_tested', original_result=run.relative_to(ROOT).as_posix(), original_result_sha256=medq_td.sha(run),
                  original_status=original['status'], source_sha256=original['meta']['source_sha256'],
                  timing=timing, physical_resources=area, route_db=db.relative_to(ROOT).as_posix(), route_db_sha256=medq_td.sha(db),
                  reports={p.relative_to(ROOT).as_posix(): medq_td.sha(p) for p in (directory / 'reports').iterdir() if p.is_file()},
                  io_contract='doc/compile/timing_closure/io_contract.md', io_contract_sha256=medq_td.sha(ROOT/'doc/compile/timing_closure/io_contract.md'),
                  explicit_false_path_commands=0, clock_group_exclusions=0, internal_multicycle_exceptions=0,
                  implicit_local_io_hold_exclusions=omitted, sdram_sip_pads=sip,
                  reviewed_native_warnings=critical, route_qor_audit=qor_audit)
    out = ROOT / 'doc/compile/timing_closure' / directory.name / 'signoff.json'
    medq_td.dump(out, result)
    medq_td.dump(ROOT / 'prj/td/latest_timing_signoff.json', dict(status='PASS', result=out.relative_to(ROOT).as_posix()))
    return result, out


def simulation_gate():
    sys.path.insert(0, str(ROOT / 'sim'))
    import run_regression
    regression = read(ROOT / 'sim/regression_result.json')
    expected = {p.stem for p in (ROOT / 'tb').glob('tb_*.v')}
    assert regression['status'] == 'PASS' and regression['rtl_2001_exit_code'] == 0
    assert regression['source_sha256'] == run_regression.hashes(), 'Stale functional regression'
    tests = regression['results']
    assert {r['test'] for r in tests} == expected and len(tests) == len(expected), 'Full regression required'
    assert all(r['status'] == 'PASS' and r['tool'] == 'modelsim' for r in tests)
    evidence = {'sim/regression_result.json': medq_td.sha(ROOT/'sim/regression_result.json')}
    pointers = ['sim/vendor_sdram/latest_adapter.json', 'sim/vendor_sdram/latest_adapter_real_pll.json',
                'sim/vendor_sdram/latest_bandwidth_real_pll.json', 'sim/vendor_sdram/latest_system.json',
                'sim/vendor_sdram/latest_basic.json', 'sim/vendor_sdram/latest_audio.json', 'sim/vendor_sdram/latest_media.json', 'sim/vendor_pll/latest.json', 'sim/vendor_serdes/latest.json']
    for pointer in pointers:
        p = read(ROOT / pointer)
        result = read(ROOT / p['result'])
        assert p['status'] == 'PASS' and result['status'] == 'PASS', pointer
        check_hashes(result['input_sha256'], absolute=True)
        evidence[pointer] = medq_td.sha(ROOT/pointer)
        evidence[p['result']] = medq_td.sha(ROOT/p['result'])
    return evidence


def bitgen(approved, signoff_path):
    evidence = simulation_gate()
    readiness_path = ROOT/'prj/td/hardware_readiness.json'
    readiness = read(readiness_path)
    readiness['required']['clock_and_cdc_constraints_reviewed'] = True
    readiness['required']['ram_inference_reviewed_in_td'] = True
    readiness['required']['final_resource_margin_after_sdram_reviewed'] = True
    readiness['evidence']['resource_review'] = signoff_path.relative_to(ROOT).as_posix()
    readiness['evidence']['ram_inference_reviewed_in_td'] = signoff_path.relative_to(ROOT).as_posix()
    readiness['evidence']['final_resource_margin_after_sdram_reviewed'] = signoff_path.relative_to(ROOT).as_posix()
    readiness['evidence']['clock_and_cdc_constraints_reviewed'] = signoff_path.relative_to(ROOT).as_posix()
    readiness['note'] = 'PC simulation and routed STA passed; board validation not performed.'
    assert all(v is True for v in readiness['required'].values()), 'Other hardware readiness gate remains'
    medq_td.dump(readiness_path, readiness)
    tag = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ_') + uuid.uuid4().hex[:8]
    directory = ROOT/'prj/td/runs'/('bitgen_' + tag)
    assert not directory.exists()
    stage = Path(tempfile.mkdtemp(prefix='medq_bitgen_'))
    assert stage.as_posix().isascii()
    shutil.copy2(ROOT/approved['route_db'], stage/'routed.db')
    assert medq_td.sha(stage/'routed.db') == approved['route_db_sha256']
    bit_name = 'MedQ_v0.3_MEDIA_COVER_' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '.bit'
    script = '''import_db {routed.db}
update_timing -mode final
report_timing_status -file fresh_phy.ts
report_timing_summary -ep_num 500 -file fresh_pr.timing
report_timing_exception -ep_num 100 -file fresh_exception.timing
report_timing_ignored -ep_num 100 -file fresh_ignored.timing
check_timing -verbose -file fresh_constraint_health.rpt
set stream [open fresh_phy.ts r]
set status [read $stream]
close $stream
foreach metric {SWNS HWNS} {
    set pattern [format {%s:\s*(-?[0-9.]+)ns} $metric]
    if {![regexp $pattern $status whole slack]} {error "STA_UNKNOWN"}
    if {$slack < 0} {error "STA_NEGATIVE"}
}
puts "MEDQ_BITGEN_STA_GATE_PASS"
bitgen -bit {BIT_NAME}
puts "MEDQ_VERIFIED_BITGEN_DONE"
exit
'''.replace('BIT_NAME', bit_name)
    tcl = stage/'bitgen.tcl'
    tcl.write_text(script, encoding='utf-8')
    command = [read(ROOT/'doc/hw/toolchain.json')['td']['command_exe'], tcl.as_posix()]
    start = time.time()
    proc = subprocess.run(command, cwd=stage, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
    log = proc.stdout.decode('utf-8', errors='replace')
    directory.mkdir(parents=True)
    for p in stage.iterdir():
        if p.is_file() and p.name != 'routed.db':
            shutil.copy2(p, directory/p.name)
    (directory/'td_run.log').write_text(log, encoding='utf-8')
    result = dict(status='FAIL', board_test_status='not_tested', parent_signoff=signoff_path.relative_to(ROOT).as_posix(),
                  parent_signoff_sha256=medq_td.sha(signoff_path), source_sha256=approved['source_sha256'],
                  route_db_sha256=approved['route_db_sha256'], simulation_evidence_sha256=evidence,
                  command=command, stage=stage.as_posix(), exit_code=proc.returncode)
    medq_td.dump(directory/'result.json', result)
    assert proc.returncode == 0 and 'MEDQ_VERIFIED_BITGEN_DONE' in log.splitlines() and 'MEDQ_BITGEN_STA_GATE_PASS' in log.splitlines() and not medq_td.ERROR.search(log), 'Native bitgen failed: '+log[-2000:]
    fresh = timing_report(text(directory/'fresh_pr.timing'))
    assert fresh['met'] and not fresh['negative_paths'], 'Fresh pre-bitgen STA failed'
    assert fresh['values'] == approved['timing']['values'], 'Imported DB timing changed'
    check_hashes(approved['source_sha256'])
    check_hashes(evidence)
    bit = directory/bit_name
    assert bit.stat().st_size > 1000 and bit.stat().st_mtime >= start, 'Missing/stale bitstream'
    result.update(status='PASS', bitstream=bit.relative_to(ROOT).as_posix(), bitstream_sha256=medq_td.sha(bit),
                  bitstream_bytes=bit.stat().st_size, native_timing=fresh,
                  artifacts={p.name: medq_td.sha(p) for p in directory.iterdir() if p.is_file() and p.name != 'result.json'})
    bit.with_suffix('.sha256').write_text(result['bitstream_sha256']+'  '+bit.name+'\n', encoding='ascii')
    medq_td.dump(directory/'result.json', result)
    medq_td.dump(ROOT/'prj/td/latest_timing_bitstream.json', dict(status='PASS', result=(directory/'result.json').relative_to(ROOT).as_posix()))
    return result


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--result', required=True, help='project-relative routed result.json')
    ap.add_argument('--bitgen', action='store_true')
    a = ap.parse_args()
    approved, out = audit(a.result)
    print('STA_SIGNOFF_PASS', approved['timing']['values'], out.relative_to(ROOT), flush=True)
    if a.bitgen:
        result = bitgen(approved, out)
        print('BITGEN_PASS', result['bitstream'], 'SHA256', result['bitstream_sha256'])


if __name__ == '__main__':
    main()

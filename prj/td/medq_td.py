"""MedQ TD 6.2 batch flow: source-traced preparation and fresh-run evidence.

Default is PREPARE ONLY. --run uses a new ASCII directory for every invocation.
--mode synth stops after optimize_gate. Implementation/bitgen require real bindings.
"""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
import uuid
from datetime import datetime, timezone
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parents[2]
MODES = ('analyze', 'synth', 'implement', 'bitgen')
ERROR = re.compile(r'\bERROR\b|\*\*\s*(?:Error|Fatal)|License\s+expired|\bTIMEOUT\b|coredump|crash', re.I)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def dump(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def tcl_path(path):
    value = str(path).replace('\\', '/')
    if any(c in value for c in '{}\n\r'):
        raise ValueError('Unsupported Tcl path: ' + value)
    return '{' + value + '}'


def build_project(name, top, sources, destination, constraints=False):
    files = []
    for i, p in enumerate(sources):
        # TD open_project resolves paths differently across GUI/batch contexts.
        # Regenerate absolute paths for each ASCII run rather than moving .al.
        relative = (destination.parent.parent / p).resolve().as_posix()
        files.append(f'''<File Path="{escape(relative, {'"': '&quot;'})}"><FileInfo>
<Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/>
<Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="{i+1}"/>
</FileInfo></File>''')
    constraint_xml = ''
    if constraints:
        for tag, suffix in (('ADC_FILE', 'adc'), ('SDC_FILE', 'sdc')):
            path = (destination.parent.parent / ('prj/constr/top.' + suffix)).as_posix()
            constraint_xml += f'''<{tag}><File Path="{escape(path, {'"': '&quot;'})}"><FileInfo>
<Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/>
<Attr Name="BelongTo" Val="constraint_1"/><Attr Name="CompileOrder" Val="1"/>
</FileInfo></File></{tag}>'''
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<Project Version="3" Minor="2" Path="{escape(destination.as_posix())}">
<Project_Created_Time></Project_Created_Time>
<TD_Encoding>GB2312</TD_Encoding><TD_Version>6.2.168116</TD_Version><Name>{name}</Name>
<HardWare><Family>EG4</Family><Device>EG4S20BG256</Device><Speed></Speed></HardWare>
<Source_Files><Verilog>{''.join(files)}</Verilog>{constraint_xml}</Source_Files>
<FileSets><FileSet Name="design_1" Type="DesignFiles"></FileSet>
<FileSet Name="constraint_1" Type="ConstrainFiles"></FileSet></FileSets>
<TOP_MODULE><LABEL>{top}</LABEL><MODULE>{top}</MODULE><CREATEINDEX>user</CREATEINDEX></TOP_MODULE>
<Property></Property><Device_Settings></Device_Settings><Configurations></Configurations>
<Runs><Run Name="syn_1" Type="Synthesis" ConstraintSet="constraint_1" Description="" Active="true">
<Strategy Name="Default_Synthesis_Strategy"></Strategy><UserParams></UserParams></Run>
<Run Name="phy_1" Type="PhysicalDesign" ConstraintSet="constraint_1" Description="" SynRun="syn_1" Active="true">
<Strategy Name="Default_PhysicalDesign_Strategy"></Strategy><UserParams></UserParams></Run></Runs>
<Project_Settings></Project_Settings></Project>
'''


def build_tcl(name, top, mode, constraints, sources):
    rep = 'prj/td/reports/' + name
    lines = ['# Run from the ASCII workspace root with td_commands_prompt.exe.',
             'import_device eagle_s20.db -package EG4S20BG256']
    lines += ['analyze -file ' + tcl_path(p) + ' -include_dir {rtl rtl/al_ip/sdram_vendor compat}' for p in sources]
    lines += ['elaborate -top ' + top, 'puts "MEDQ_STAGE_ELABORATED"']
    if constraints:
        lines += ['read_adc {prj/constr/top.adc}', 'read_sdc {prj/constr/top.sdc}']
    if mode != 'analyze':
        lines += ['optimize_rtl', f'report_area -file {rep}_rtl.area',
                  'set_param gate map_mode area_prior', 'set_param gate pack_effort high',
                  f'optimize_gate -packarea {rep}_gate.area',
                  f'export_db prj/td/output/{name}_gate.db', 'puts "MEDQ_STAGE_SYNTHESIZED"']
    if mode in ('implement', 'bitgen'):
        lines += ['legalize_phy_inst', 'update_timing',
                  'set_param route effort routability',
                  'place', 'route', 'fix_hold',
                  f'report_area -io_info -file {rep}_phy.area', 'update_timing -mode final',
                  f'report_timing_status -file {rep}_phy.ts',
                  f'report_timing_summary -ep_num 500 -file {rep}_pr.timing',
                  f'report_timing_exception -file {rep}_exception.timing',
                  f'report_timing_ignored -ep_num 500 -file {rep}_ignored.timing',
                  f'check_timing -verbose -file {rep}_constraint_health.rpt',
                  f'export_db prj/td/output/{name}_pr.db', 'puts "MEDQ_STAGE_IMPLEMENTED"']
    if mode == 'bitgen':
        lines += [f'bitgen -bit prj/td/output/{name}.bit']
    lines += ['puts "MEDQ_FLOW_DONE_' + mode.upper() + '"', 'exit']
    return '\n'.join(lines) + '\n'


def judge(mode, name, stage, output, rc):
    errors = [line for line in output.splitlines() if ERROR.search(line)]
    done = 'MEDQ_FLOW_DONE_' + mode.upper() in output.splitlines()
    expected = []
    if mode != 'analyze':
        expected += [f'reports/{name}_rtl.area', f'reports/{name}_gate.area', f'output/{name}_gate.db']
    if mode in ('implement', 'bitgen'):
        expected += [f'reports/{name}_phy.area', f'reports/{name}_phy.ts', f'reports/{name}_pr.timing',
                     f'reports/{name}_exception.timing', f'output/{name}_pr.db']
    if mode == 'bitgen':
        expected.append(f'output/{name}.bit')
    missing = [p for p in expected if not (stage / 'prj/td' / p).is_file() or not (stage / 'prj/td' / p).stat().st_size]
    # Never infer timing closure from empty/unknown report formats or return code.
    # TD's native timing reports remain authoritative; a first valid run must be reviewed.
    status = 'PASS' if rc == 0 and done and not errors and not missing else 'FAIL'
    resources = {}
    area_file = stage / 'prj/td/reports' / (name + '_gate.area')
    if area_file.exists():
        for row in re.finditer(r'^#(\w+)\s+(\d+)\s+out of\s+(\d+)', area_file.read_text(encoding='utf-8',errors='replace'), re.M):
            resources[row[1]]={'used':int(row[2]),'available':int(row[3])}
    overflow = [key for key,value in resources.items() if value['used']>value['available']]
    if status=='PASS' and mode!='analyze':
        if overflow: status='RESOURCE_OVERFLOW'
        elif not resources: status='REVIEW_REQUIRED'
    timing_met=None
    timing_slack={}
    if mode in ('implement','bitgen'):
        # Native EG4 status is in ns. report_clock_utilization is unsupported
        # on this device; clock inventory is already in report_timing_summary.
        path=stage/'prj/td/reports'/(name+'_phy.ts')
        if path.exists():
            report=path.read_text(encoding='utf-8',errors='replace')
            for key in ('SWNS','HWNS'):
                m=re.search(r'\b'+key+r':\s*(-?\d+(?:\.\d+)?)ns',report)
                if m:timing_slack[key]=float(m[1])
        if len(timing_slack)==2:timing_met=all(v>=0 for v in timing_slack.values())
        if status=='PASS':status='TIMING_FAIL' if timing_met is False else 'REVIEW_REQUIRED'
    return {'status': status, 'mode': mode, 'exit_code': rc, 'flow_done': done,
            'gate_resources':resources,'resource_overflow':overflow,
            'errors': errors, 'missing_artifacts': missing, 'timing_met': timing_met,'timing_slack_ns':timing_slack,
            'license_expired': any('license expired' in e.lower() for e in errors),
            'bitstream_verified': False}


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--top', default='top')
    ap.add_argument('--name', default='MedQv03')
    ap.add_argument('--mode', choices=MODES, default='synth')
    ap.add_argument('--source', action='append', help='repeatable source subset, e.g. real toolchain probe')
    ap.add_argument('--run', action='store_true')
    ap.add_argument('--timeout', type=int, default=1800)
    args = ap.parse_args()
    for identifier in (args.name, args.top):
        if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', identifier):
            ap.error('name/top must be plain identifiers')
    sources = args.source or [p.relative_to(ROOT).as_posix() for p in sorted((ROOT / 'rtl').rglob('*.v')) if p.name != 'top_skeleton.v']
    for p in sources:
        resolved = (ROOT / p).resolve()
        if not resolved.is_relative_to(ROOT) or not resolved.is_file() or resolved.suffix != '.v':
            ap.error('Sources must be existing project-relative .v files')
    constraints = args.top == 'top' and not args.source
    if args.mode in ('implement', 'bitgen'):
        ready = json.loads((ROOT / 'prj/td/hardware_readiness.json').read_text(encoding='utf-8'))
        pending = [k for k, v in ready['required'].items() if v is not True]
        # Routed timing is needed to finish the constraints review itself.
        # Diagnostic implementation may run; bit generation retains every gate.
        if args.mode=='implement':pending=[k for k in pending if k not in ('clock_and_cdc_constraints_reviewed','final_resource_margin_after_sdram_reviewed')]
        if not constraints or pending:
            print('BLOCKED: implementation/bitgen requires MedQ hardware readiness: ' + ', '.join(pending))
            return 2
    td_dir = ROOT / 'prj/td'
    (td_dir / (args.name + '.al')).write_text(build_project(args.name, args.top, sources, td_dir, constraints), encoding='utf-8')
    script = build_tcl(args.name, args.top, args.mode, constraints, sources)
    (td_dir / ('build_' + args.name + '.tcl')).write_text(script, encoding='utf-8')
    inputs = [ROOT / p for p in sources] + list((ROOT / 'rtl').rglob('*.vh')) + list((ROOT / 'rtl').rglob('*.hex')) + list((ROOT / 'rtl').rglob('*.ipc'))
    if constraints:
        inputs += [ROOT / 'prj/constr/top.adc', ROOT / 'prj/constr/top.sdc']
    manifest = {p.relative_to(ROOT).as_posix(): sha(p) for p in inputs}
    meta = {'top': args.top, 'name': args.name, 'mode': args.mode, 'sources': sources,
            'defines': [], 'source_sha256': manifest, 'status': 'PREPARED_NOT_RUN',
            'driver_sha256': sha(Path(__file__)),
            'tcl_sha256': hashlib.sha256(script.encode('utf-8')).hexdigest(),
            'al_status': 'same-format ASCII MedQ.al loaded in TD GUI on 2026-10-26; current batch uses analyze directly; implementation not verified'}
    if constraints:
        readiness=json.loads((ROOT/'prj/td/hardware_readiness.json').read_text(encoding='utf-8'))
        meta['pending_hardware_items']=[k for k,v in readiness['required'].items() if v is not True]
        meta['acceptance_scope']='Real SDRAM-active MedQ; diagnostic implementation is not timing or bitstream acceptance'
    dump(td_dir / (args.name + '_manifest.json'), meta)
    print(f'PREPARED {args.name}: {len(sources)} sources, mode={args.mode}, no SIMULATION define')
    if not args.run:
        return 0
    toolchain = json.loads((ROOT / 'doc/hw/toolchain.json').read_text(encoding='utf-8'))
    td = toolchain.get('td', {})
    command = td.get('command_exe') or str(Path(td.get('td_home', '')) / 'bin/td_commands_prompt.exe')
    if not Path(command).is_file():
        print('BLOCKED: td_commands_prompt.exe not found')
        return 127
    tag = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ_') + uuid.uuid4().hex[:8]
    stage = Path(tempfile.gettempdir()) / 'medq_td_build' / tag
    if not str(stage).isascii():
        ap.error('System TEMP must be ASCII for TD')
    stage.mkdir(parents=True)
    for p in inputs:
        dest = stage / p.relative_to(ROOT)
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(p, dest)
    # Preserve the vendor's legacy relative include without editing its bytes.
    if (stage/'rtl/al_ip/sdram_vendor/global_def.v').exists():
        (stage/'compat').mkdir()
        legacy=stage/'user_source/hdl_source/include'
        legacy.mkdir(parents=True)
        shutil.copy2(stage/'rtl/al_ip/sdram_vendor/global_def.v',legacy/'global_def.v')
    # TD searches includes/ROM data relative to CWD in some releases.
    # Copy identical bytes, never transform HDL or initialisation data.
    for p in inputs:
        if p.suffix in ('.vh', '.hex'):
            dest = stage / p.name
            if dest.exists() and sha(dest) != sha(p):
                raise ValueError('Duplicate include/data basename: ' + p.name)
            shutil.copy2(p, dest)
    run_td = stage / 'prj/td'
    for d in ('reports', 'output'):
        (run_td / d).mkdir(parents=True, exist_ok=True)
    (run_td / (args.name + '.al')).write_text(build_project(args.name, args.top, sources, run_td, constraints), encoding='utf-8')
    tcl = run_td / ('build_' + args.name + '.tcl')
    tcl.write_text(script, encoding='utf-8')
    cmd = [command, tcl.as_posix()]
    try:
        proc = subprocess.run(cmd, cwd=stage, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=args.timeout)
        output, rc = proc.stdout.decode('utf-8', errors='replace'), proc.returncode
    except subprocess.TimeoutExpired as e:
        output, rc = (e.stdout or b'').decode('utf-8', errors='replace') + '\nTIMEOUT\n', 124
    for qor in stage.glob('*.qor'):
        shutil.copy2(qor,run_td/'reports'/(args.name+'_'+qor.name))
    result = judge(args.mode, args.name, stage, output, rc)
    changed = [p for p, digest in manifest.items() if sha(ROOT / p) != digest]
    if changed:
        result.update(status='SOURCES_CHANGED', changed_inputs=changed)
    result.update(meta=meta, command=cmd, stage_path=stage.as_posix(), timestamp_utc=tag,
                  artifacts={p.relative_to(run_td).as_posix(): sha(p) for d in ('reports', 'output') for p in (run_td / d).glob('*') if p.is_file()})
    (run_td / 'td_run.log').write_text(output, encoding='utf-8')
    dump(run_td / 'result.json', result)
    destination = td_dir / 'runs' / tag
    shutil.copytree(run_td, destination)
    dump(td_dir / ('latest_' + args.name + '.json'), {'result': (destination / 'result.json').relative_to(ROOT).as_posix(), 'status': result['status']})
    print(result['status'] + ': ' + str((destination / 'result.json').relative_to(ROOT)))
    for line in result['errors'][:8]:
        print(line)
    return 0 if result['status'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())

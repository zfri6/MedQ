"""Reproducible MedQ behavioral simulation regression, with per-test evidence."""
import argparse
import hashlib
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
import run_sim

ROOT = Path(__file__).resolve().parent.parent
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')

def hashes():
    files = list((ROOT/'rtl').rglob('*.v')) + list((ROOT/'rtl').glob('*.hex')) + list((ROOT/'rtl').glob('*.vh'))
    files += list((ROOT/'tb').rglob('*.v')) + list((ROOT/'tb').glob('*.hex'))
    files += list((ROOT/'sim').glob('*.py'))
    return {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(files)}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sim', choices=('modelsim','iverilog','both'), default='modelsim')
    parser.add_argument('--tb', action='append', help='run selected TB, repeatable')
    parser.add_argument('--timeout', type=int, default=180)
    args = parser.parse_args()
    tests = args.tb or [p.stem for p in sorted((ROOT/'tb').glob('tb_*.v'))]
    engines = ['iverilog','modelsim'] if args.sim=='both' else [args.sim]
    baseline = hashes()
    summary = {'started_utc': datetime.now(timezone.utc).isoformat(), 'profile':'behavioral',
               'status':'RUNNING','source_sha256':baseline,'results':[]}
    destination = ROOT/'sim/regression_result.json'
    iv = run_sim.find_iverilog(run_sim._cache())
    if not iv:
        print('Icarus required for the Verilog-2001 syntax gate; not found.')
        return 127
    rtl, _ = run_sim.sources('tb_top')
    syntax_cmd = [iv,'-g2001','-Wall','-I',str(ROOT/'rtl'),'-DSIMULATION','-tnull','-s','top','-s','top_skeleton']
    syntax_cmd += rtl + [str(ROOT/'tb/sim_anlogic_stubs.v')]
    syntax = subprocess.run(syntax_cmd, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=args.timeout)
    (ROOT/'sim/rtl_2001_compile.log').write_bytes(syntax.stdout)
    summary['rtl_2001_exit_code'] = syntax.returncode
    if syntax.returncode:
        summary['status']='COMPILE_FAIL'
    else:
        for engine in engines:
            for tb in tests:
                output = ROOT/'sim/tests'/engine/tb
                output.mkdir(parents=True, exist_ok=True)
                result_path=output/'sim_result.json'
                result_path.unlink(missing_ok=True)
                cmd = [sys.executable,str(ROOT/'sim/run_sim.py'),'--run','--sim',engine,
                       '--tb-top',tb,'--output-dir',output.relative_to(ROOT).as_posix(),'--timeout',str(args.timeout)]
                run = subprocess.run(cmd,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
                result = json.loads(result_path.read_text(encoding='utf-8')) if result_path.exists() else {'status':'TOOL_FAIL'}
                passed=run.returncode==0 and result.get('status')=='PASS' and result.get('tb_top')==tb and result.get('simulator')==engine
                result.update(exit_code=run.returncode,tool=engine,test=tb)
                if not passed: result['driver_output']=run.stdout.decode('utf-8',errors='replace')[-4000:]
                summary['results'].append(result)
                summary['status']='RUNNING' if passed else 'FAIL'
                destination.write_text(json.dumps(summary,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
                print(f'{engine:8} {tb:28} {"PASS" if passed else "FAIL"}',flush=True)
                if not passed: break
            if summary['status']=='FAIL': break
        if summary['status']=='RUNNING': summary['status']='PASS'
    if hashes()!=baseline: summary['status']='SOURCES_CHANGED'
    summary['finished_utc']=datetime.now(timezone.utc).isoformat()
    destination.write_text(json.dumps(summary,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
    print(f"{summary['status']}: {len(summary['results'])} test runs; sim/regression_result.json")
    return 0 if summary['status']=='PASS' else 1

if __name__=='__main__':
    raise SystemExit(main())

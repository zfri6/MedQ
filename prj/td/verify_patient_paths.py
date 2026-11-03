"""Source-bound targeted ModelSim evidence beyond the frozen full regression."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'sim'))
import run_sim


def main():
    ms = Path(run_sim.find_modelsim(run_sim._cache()))
    names = sys.argv[1:] or ['tb_named_pcm']
    results = []
    for name in names:
        stage = Path(tempfile.mkdtemp(prefix='medq_patient_'))
        out = ROOT / 'doc/compile/patient_names' / (name + '_' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ'))
        out.mkdir(parents=True)
        rtl, support = run_sim.sources('tb_top')
        support = [p for p in support if Path(p).name != 'tb_top.v']
        files = [Path(p) for p in rtl + support] + [ROOT / 'doc/compile/patient_names' / (name + '.v')]
        files += list((ROOT / 'rtl').glob('*.vh')) + list((ROOT / 'rtl').glob('*.hex')) + [ROOT / 'tb/medq_sd_image.hex']
        digests = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
        for p in files:
            shutil.copy2(p, stage / p.name)
        sources = [p.name for p in files if p.suffix == '.v']
        commands = [[str(ms / 'vlib.exe'), 'work'],
                    [str(ms / 'vlog.exe'), '-sv', '+define+SIMULATION', '+incdir+.', '-work', 'work'] + sources,
                    [str(ms / 'vsim.exe'), '-c', '-t', '1ps', 'work.' + name, '-do', 'run -all; quit -f']]
        status, details = 'FAIL', []
        for i, command in enumerate(commands):
            proc = subprocess.run(command, cwd=stage, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=240)
            text = proc.stdout.decode('utf-8', errors='replace')
            (out / f'{i}.log').write_text('$ ' + ' '.join(command) + '\n' + text, encoding='utf-8')
            if proc.returncode or '** Error' in text or '** Fatal' in text:
                details = [text[-2000:]]
                break
            if i == 2:
                status, details = run_sim.judge(text, proc.returncode)
        assert all(hashlib.sha256((ROOT / p).read_bytes()).hexdigest() == d for p, d in digests.items())
        result = {'status': status, 'top': name, 'input_sha256': digests, 'details': details,
                  'stage': str(stage), 'tool': 'modelsim', 'board_test': 'not_tested'}
        (out / 'result.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
        results.append(str((out / 'result.json').relative_to(ROOT)))
        print(name, status, details, flush=True)
        assert status == 'PASS', out
    (ROOT / 'doc/compile/patient_names/targeted_latest.json').write_text(json.dumps(results, indent=2) + '\n')


if __name__ == '__main__':
    main()

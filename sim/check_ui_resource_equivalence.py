"""Compare full UI captures against the source-and-frame snapshot before resource edits."""
import argparse
import hashlib
import json
import zipfile
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--current',default='sim/tests/modelsim/tb_medq_ui')
    args=ap.parse_args()
    records={}
    with zipfile.ZipFile(ROOT/'sim/baseline/resource_20261026/before_optimization.zip') as frozen:
        names=[n for n in frozen.namelist() if n.startswith('sim/tests/modelsim/tb_medq_ui/') and n.endswith('.ppm')]
        assert len(names)==20
        for name in names:
            current=ROOT/args.current/Path(name).name
            expected=hashlib.sha256(frozen.read(name)).hexdigest()
            actual=hashlib.sha256(current.read_bytes()).hexdigest()
            records[Path(name).name]={'before':expected,'after':actual,'identical':expected==actual}
    result={'status':'PASS' if all(v['identical'] for v in records.values()) else 'FAIL',
            'scope':'20 full RTL pixel captures; no visual approximation or Python redrawing','frames':records}
    out=ROOT/'sim/resource_optimization';out.mkdir(exist_ok=True)
    (out/'ui_equivalence.json').write_text(json.dumps(result,indent=2)+'\n')
    print(result['status'],': 20 complete UI frame hashes compared')
    return 0 if result['status']=='PASS' else 1


if __name__=='__main__':raise SystemExit(main())

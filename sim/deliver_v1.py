"""Freeze the verified MedQ v0.1 source/evidence delivery, without stale bitstreams."""
from pathlib import Path
from datetime import datetime,timezone
import hashlib,json,zipfile
import run_regression

ROOT=Path(__file__).resolve().parents[1]

def main():
    regression=json.loads((ROOT/'sim/regression_result.json').read_text(encoding='utf-8'))
    if regression['status']!='PASS' or regression['source_sha256']!=run_regression.hashes():
        raise SystemExit('Refuse release: current source hashes do not match passing regression')
    files=set()
    def add(path):
        p=ROOT/path
        if p.is_file():files.add(p)
    for folder in ('rtl','tb','prj/constr','doc'):
        for p in (ROOT/folder).rglob('*'):
            if p.is_file() and p.suffix.lower() in ('.v','.sv','.vh','.hex','.ipc','.md','.json','.yaml','.yml','.adc','.sdc','.csv'):
                files.add(p)
    for pattern in ('sim/*.py','prj/td/*.py','prj/td/*.json','prj/td/*.tcl','prj/td/*.al'):
        files.update(ROOT.glob(pattern))
    for path in ('README.md','sim/regression_result.json','sim/rtl_2001_compile.log',
                 'sim/resource_optimization/ui_equivalence.json','sim/baseline/sdram_20261027/queue_reference.json',
                 'sim/baseline/resource_20261026/before_optimization.zip'):
        add(path)
    for p in (ROOT/'sim/tests/modelsim').rglob('*'):
        if p.is_file() and (p.name in ('sim.log','compile.log','sim_result.json','top_frame.ppm') or p.name.startswith('ui_frame_') and p.suffix=='.ppm'):
            files.add(p)
    pointers=['prj/td/latest_MedQ.json','sim/vendor_pll/latest.json','sim/vendor_serdes/latest.json',
              'sim/vendor_sdram/latest_adapter.json','sim/vendor_sdram/latest_system.json']
    evidence={}
    for pointer in pointers:
        j=json.loads((ROOT/pointer).read_text(encoding='utf-8'))
        if not pointer.startswith('prj/td') and j['status']!='PASS':raise SystemExit('Unverified vendor profile: '+pointer)
        add(pointer);evidence[pointer]=j
        for p in (ROOT/j['result']).parent.rglob('*'):
            if p.is_file() and p.suffix not in ('.db','.wlf'):files.add(p)
    # Preserve all three packing attempts as failures, never as timing acceptance.
    for tag in ('20261026T163253Z_6d142193','20261026T163723Z_0dd7de84','20261026T164010Z_0a8c25cf'):
        for p in (ROOT/'prj/td/runs'/tag).rglob('*'):
            if p.is_file() and p.suffix in ('.json','.log','.area','.timing','.ts','.tcl','.al'):files.add(p)
    manifest={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(files)}
    result={'name':'MedQ','version':'0.1','date_utc':datetime.now(timezone.utc).isoformat(),
            'scope':'simulation verified and real SDRAM integration; NO MedQ bitstream, STA closure or board acceptance',
            'evidence':evidence,'files':manifest,'count':len(manifest)}
    out=ROOT/'deliverables';out.mkdir(exist_ok=True)
    name='MedQ_v0.1_20261027'
    archive=out/(name+'.zip')
    if archive.exists():raise SystemExit('Refuse overwriting frozen delivery')
    with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
        for p in sorted(files):z.write(p,p.relative_to(ROOT).as_posix())
        z.writestr('DELIVERY_MANIFEST.json',json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    with zipfile.ZipFile(archive) as z:
        assert z.testzip() is None
        for name,digest in manifest.items():assert hashlib.sha256(z.read(name)).hexdigest()==digest
    digest=hashlib.sha256(archive.read_bytes()).hexdigest()
    archive.with_suffix('.sha256').write_text(digest+'  '+archive.name+'\n',encoding='ascii')
    archive.with_suffix('.manifest.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(f'FROZEN {archive.name}: {len(manifest)} files, {archive.stat().st_size} bytes, all ZIP member hashes verified')
    print('SHA256 '+digest)

if __name__=='__main__':main()

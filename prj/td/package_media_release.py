"""Seal a source-bound media release with a clean57-file TF root."""
from datetime import datetime,timezone
from pathlib import Path
import json
import tempfile
import zipfile
import medq_td
import signoff_timing
from package_seamless_release import verify_baseline

ROOT=medq_td.ROOT
def read(p):return json.loads((ROOT/p).read_text(encoding='utf-8'))
def main():
    signoff_timing.simulation_gate();protected=verify_baseline()
    delivery=read('doc/compile/media_carousel_delivery.json')
    assert delivery['status']=='PC_SIGNOFF_PASS' and delivery['revision']=='media_carousel_20261103'
    signoff_timing.check_hashes(delivery['simulation_evidence_sha256'])
    signoff_timing.check_hashes(read('doc/compile/media_carousel/tool_tests.json')['source_sha256'])
    pointer=read('prj/td/latest_timing_bitstream.json');bit=read(pointer['result'])
    assert pointer['status']==bit['status']=='PASS'
    signoff_timing.check_hashes(bit['source_sha256']);signoff_timing.check_hashes(bit['simulation_evidence_sha256'])
    signed=read(bit['parent_signoff']);assert signed['status']=='PASS'
    assert medq_td.sha(ROOT/bit['parent_signoff'])==bit['parent_signoff_sha256']
    assert medq_td.sha(ROOT/signed['route_db'])==bit['route_db_sha256']==signed['route_db_sha256']
    assert medq_td.sha(ROOT/delivery['bitstream'])==bit['bitstream_sha256']
    old=delivery['prior_release_unchanged']
    for kind in ('archive','bitstream'):assert medq_td.sha(ROOT/old[kind])==old[kind+'_sha256']
    sd=ROOT/delivery['tf_card_directory']/'SD_ROOT'
    assert len(list(sd.iterdir()))==57
    assert {p.name:medq_td.sha(p) for p in sd.iterdir()}==delivery['tf_card_root_sha256']
    files=set()
    for folder in ('rtl','tb','assets','doc','prj/constr','baseline','sim/ui','sim/baseline','rules','skills',delivery['tf_card_directory']):
        files.update(p for p in (ROOT/folder).rglob('*') if p.is_file() and p.suffix not in ('.pyc','.wlf','.vvp'))
    for pattern in ('sim/*.py','sim/*.ps1','sim/*.json','sim/*.log','prj/td/*.py','prj/td/*.json','prj/td/*MedQv03*'):
        files.update(p for p in ROOT.glob(pattern) if p.is_file())
    for folder in ('sim/tests/modelsim','sim/media_checks','sim/vendor_sdram','sim/vendor_pll','sim/vendor_serdes'):
        files.update(p for p in (ROOT/folder).rglob('*') if p.is_file() and p.suffix in ('.log','.json','.ppm','.png','.gif','.tcl','.do'))
    for folder in ((ROOT/signed['route_db']).parent.parent,(ROOT/pointer['result']).parent):
        files.update(p for p in folder.rglob('*') if p.is_file())
    files.update([ROOT/'README.md',ROOT/'HANDOFF.md',ROOT/delivery['bitstream'],(ROOT/delivery['bitstream']).with_suffix('.sha256')])
    manifest={p.relative_to(ROOT).as_posix():medq_td.sha(p) for p in sorted(files)}
    meta=dict(version='0.3',revision=delivery['revision'],created_utc=datetime.now(timezone.utc).isoformat(),board_test='not_tested',
        scope='Current RTL/media sources, ModelSim/real encrypted SDRAM, native dual-corner routed STA and fresh bitgen; no board programming or acoustic/electrical acceptance',
        protected_v02_files=protected,bitstream=delivery['bitstream'],bitstream_sha256=bit['bitstream_sha256'],
        tf_card_directory=delivery['tf_card_directory'],tf_card_files=57,signoff=bit['parent_signoff'],source_and_artifact_sha256=manifest)
    target=ROOT/'deliverables'/('MedQ_v0.3_MEDIA_'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')+'.zip')
    assert not target.exists()
    with zipfile.ZipFile(target,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for name in manifest:z.write(ROOT/name,name)
        z.writestr('DELIVERY_MANIFEST.json',json.dumps(meta,ensure_ascii=False,indent=2)+'\n')
    with tempfile.TemporaryDirectory(prefix='medq_media_extract_') as stage:
        with zipfile.ZipFile(target) as z:assert z.testzip() is None;z.extractall(stage)
        assert all(medq_td.sha(Path(stage)/name)==digest for name,digest in manifest.items())
    target.with_suffix('.manifest.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    target.with_suffix('.sha256').write_text(medq_td.sha(target)+'  '+target.name+'\n',encoding='ascii')
    medq_td.dump(ROOT/'deliverables/latest_v03.json',dict(status='PASS',revision=delivery['revision'],archive=target.relative_to(ROOT).as_posix(),
        archive_sha256=medq_td.sha(target),bitstream=meta['bitstream'],bitstream_sha256=meta['bitstream_sha256'],files=len(manifest),
        extraction_hash_check='PASS',protected_v02_files=protected,board_test='not_tested',tf_card_directory=delivery['tf_card_directory'],tf_card_files=57))
    print('MEDIA_PACKAGE_PASS',target.name,len(manifest),'files')
    print('PACKAGE_SHA256',medq_td.sha(target));print('BITSTREAM_SHA256',bit['bitstream_sha256'])

if __name__=='__main__':main()

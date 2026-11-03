"""V0.3 release: current simulation/STA/bitgen, protected baseline, ZIP hashes."""
from pathlib import Path
from datetime import datetime,timezone
import argparse,hashlib,json,zipfile,sys,shutil,tempfile
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'prj/td'))
import medq_td,signoff_timing
def read(p):return json.loads(p.read_text(encoding='utf-8'))
def verify_baseline():
 baseline=read(ROOT/'baseline/v02_frozen/manifest.json')
 original=ROOT.parent/'MedQ_v0.2'
 actual={p.relative_to(original).as_posix():medq_td.sha(p) for p in original.rglob('*') if p.is_file()}
 assert actual=={k:v['sha256'] for k,v in baseline['files'].items()},'Protected V0.2 changed'
 for name,item in read(ROOT/'baseline/v02_frozen/root_protected.json').items():
  assert medq_td.sha(ROOT.parent/name)==item['sha256'],'Protected root artifact changed: '+name
 return len(actual)
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--timing',action='store_true');ap.parse_args()
 signoff_timing.simulation_gate();protected=verify_baseline()
 delivery=read(ROOT/'doc/compile/seamless_marquee_delivery.json')
 assert delivery['status']=='PC_SIGNOFF_PASS' and delivery['revision']=='seamless_marquee_20261102'
 signoff_timing.check_hashes(delivery['simulation_evidence_sha256'])
 tools=read(ROOT/'doc/compile/seamless_marquee/tool_tests.json')
 signoff_timing.check_hashes(tools['source_sha256'])
 for clip in read(ROOT/'assets/voice_manifest.json')['clips']:
  assert medq_td.sha(ROOT/'assets/sd_root'/clip['file'])==clip['sha256']
 pointer=read(ROOT/'prj/td/latest_timing_bitstream.json');assert pointer['status']=='PASS'
 bit=read(ROOT/pointer['result']);assert bit['status']=='PASS'
 signoff_timing.check_hashes(bit['source_sha256']);signoff_timing.check_hashes(bit['simulation_evidence_sha256'])
 signed=read(ROOT/bit['parent_signoff']);assert signed['status']=='PASS'
 assert medq_td.sha(ROOT/bit['parent_signoff'])==bit['parent_signoff_sha256']
 assert medq_td.sha(ROOT/signed['route_db'])==bit['route_db_sha256']==signed['route_db_sha256']
 assert medq_td.sha(ROOT/bit['bitstream'])==bit['bitstream_sha256']
 destination=ROOT/'deliverables'/Path(bit['bitstream']).name
 if destination.exists():assert medq_td.sha(destination)==bit['bitstream_sha256']
 else:shutil.copy2(ROOT/bit['bitstream'],destination)
 destination.with_suffix('.sha256').write_text(bit['bitstream_sha256']+'  '+destination.name+'\n',encoding='ascii')
 files=set()
 files.update(p for p in (ROOT/delivery['tf_card_directory']).rglob('*') if p.is_file())
 for folder in ['rtl','tb','assets','doc','prj/constr','baseline/v02_frozen','baseline/v03_visual_intake_20261031','baseline/v03_pre_sw1_queue_fix_20261031','sim/baseline','sim/ui','rules','skills']:
  files.update(p for p in (ROOT/folder).rglob('*') if p.is_file() and p.suffix not in ('.pyc','.wlf','.vvp'))
 for snapshot in (ROOT/'baseline').glob('v03_pre_independent_switch_*'):
  files.update(p for p in snapshot.rglob('*') if p.is_file())
 for snapshot in (ROOT/'baseline').glob('v03_pre_seamless_marquee_*'):
  files.update(p for p in snapshot.rglob('*') if p.is_file())
 for snapshot in (ROOT/'baseline').glob('v03_pre_masked_smooth_*'):
  files.update(p for p in snapshot.rglob('*') if p.is_file())
 for snapshot in (ROOT/'baseline').glob('v03_pre_patient_names_*'):
  files.update(p for p in snapshot.rglob('*') if p.is_file())
 for snapshot in (ROOT/'baseline').glob('v03_pre_marquee_events_*'):
  files.update(p for p in snapshot.rglob('*') if p.is_file())
 for pattern in ['sim/*.py','sim/*.ps1','sim/*.json','sim/*.log','prj/td/*.py','prj/td/*.json','prj/td/*MedQv03*']:
  files.update(ROOT.glob(pattern))
 for folder in ['sim/tests/modelsim','sim/seamless_marquee','sim/marquee_events','sim/patient_names','sim/independent_switch','sim/v03','sim/vendor_sdram','sim/vendor_pll','sim/vendor_serdes']:
  files.update(p for p in (ROOT/folder).rglob('*') if p.is_file() and p.suffix in ('.log','.json','.ppm','.png','.gif','.tcl','.do'))
 for folder in [(ROOT/signed['route_db']).parent.parent,(ROOT/pointer['result']).parent]:
  files.update(p for p in folder.rglob('*') if p.is_file())
 files.update([ROOT/'README.md',ROOT/'HANDOFF.md',destination,destination.with_suffix('.sha256')])
 manifest={p.relative_to(ROOT).as_posix():medq_td.sha(p) for p in sorted(files)}
 meta={'version':'0.3','revision':'seamless_marquee_20261102','created_utc':datetime.now(timezone.utc).isoformat(),'board_test':'not_tested',
  'scope':'Current V0.3 ModelSim regression, actual encrypted SDRAM plus independent physical model, vendor primitives, native dual-corner routed STA, new bitstream; no board download/test',
  'protected_v02_files':protected,'bitstream':destination.relative_to(ROOT).as_posix(),'bitstream_sha256':bit['bitstream_sha256'],
  'signoff':bit['parent_signoff'],'source_and_artifact_sha256':manifest}
 target=ROOT/'deliverables'/('MedQ_v0.3_'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')+'.zip')
 assert not target.exists()
 with zipfile.ZipFile(target,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
  for name in manifest:z.write(ROOT/name,name)
  z.writestr('DELIVERY_MANIFEST.json',json.dumps(meta,ensure_ascii=False,indent=2)+'\n')
 with tempfile.TemporaryDirectory(prefix='medq_v03_extract_') as stage:
  with zipfile.ZipFile(target) as z:assert z.testzip() is None;z.extractall(stage)
  assert all(medq_td.sha(Path(stage)/name)==digest for name,digest in manifest.items())
 target.with_suffix('.manifest.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 target.with_suffix('.sha256').write_text(medq_td.sha(target)+'  '+target.name+'\n',encoding='ascii')
 medq_td.dump(ROOT/'deliverables/latest_v03.json',{'status':'PASS','archive':target.relative_to(ROOT).as_posix(),'archive_sha256':medq_td.sha(target),'bitstream':meta['bitstream'],'bitstream_sha256':bit['bitstream_sha256'],'files':len(manifest),'extraction_hash_check':'PASS','protected_v02_files':protected,'board_test':'not_tested'})
 print('V03_RELEASE_PASS',target.name,len(manifest),'files');print('PACKAGE_SHA256',medq_td.sha(target));print('BITSTREAM_SHA256',bit['bitstream_sha256'])
if __name__=='__main__':main()

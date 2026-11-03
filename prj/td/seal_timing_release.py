"""V0.3 seal verification, with immutable version-specific release names."""
from pathlib import Path
import sys,json,zipfile,hashlib
import medq_td,signoff_timing
ROOT=medq_td.ROOT
def main():
 sys.path.insert(0,str(ROOT/'sim'));import package_release
 signoff_timing.simulation_gate();package_release.verify_baseline()
 pointer=json.loads((ROOT/'deliverables/latest_v03.json').read_text(encoding='utf-8'))
 archive=ROOT/pointer['archive'];assert medq_td.sha(archive)==pointer['archive_sha256']
 with zipfile.ZipFile(archive) as z:
  assert z.testzip() is None
  manifest=json.loads(z.read('DELIVERY_MANIFEST.json'))
  for name,digest in manifest['source_and_artifact_sha256'].items():
   assert hashlib.sha256(z.read(name)).hexdigest()==digest, 'Archive bytes changed: '+name
   assert (ROOT/name).is_file() and medq_td.sha(ROOT/name)==digest, 'Working copy drift: '+name
  assert len(z.namelist())==len(manifest['source_and_artifact_sha256'])+1, 'Unexpected ZIP entries'
 assert medq_td.sha(ROOT/pointer['bitstream'])==pointer['bitstream_sha256']
 print('V03_SEAL_PASS',archive.name,'board_test: not_tested')
if __name__=='__main__':main()

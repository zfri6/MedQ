"""ModelSim check of the TD-generated MedQ PLL with original installed EG4 models."""
import hashlib
import json
import shutil
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path
import run_sim

ROOT=Path(__file__).resolve().parents[1]


def main():
    tc=json.loads((ROOT/'doc/hw/toolchain.json').read_text(encoding='utf-8'))
    ms=Path(tc['modelsim_bin']);lib=Path(tc['td']['td_home'])/'sim_release/eg4'
    vendor=[lib/'eg_logic_clk.v']
    files=[ROOT/'rtl/al_ip/medq_pll.v',ROOT/'rtl/al_ip/sys_pll.v',ROOT/'tb/vendor/tb_medq_pll_eg4.v',lib/'eg_phy_pll.v',lib/'eg_phy_glbl.v']+vendor
    digests={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
    stage=Path(tempfile.mkdtemp(prefix='medq_eg4_pll_'))
    output=ROOT/'sim/vendor_pll'/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    output.mkdir(parents=True,exist_ok=False)
    for p in files:shutil.copy2(p,stage/p.name)
    commands=[[str(ms/'vlib.exe'),'work'],
              [str(ms/'vlog.exe'),'-work','work']+[p.name for p in vendor]+['eg_phy_pll.v','eg_phy_glbl.v','medq_pll.v','sys_pll.v'],
              [str(ms/'vlog.exe'),'-sv','-work','work','tb_medq_pll_eg4.v'],
              [str(ms/'vsim.exe'),'-c','work.tb_medq_pll_eg4','work.glbl','-do','run -all; quit -f']]
    status,details='FAIL',[];last=''
    for i,cmd in enumerate(commands):
        try:
            proc=subprocess.run(cmd,cwd=stage,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=90)
            last=proc.stdout.decode('utf-8',errors='replace');rc=proc.returncode
        except subprocess.TimeoutExpired:
            last='TIMEOUT vendor PLL simulation';rc=124
        (output/f'{i}.log').write_text('$ '+' '.join(cmd)+'\n'+last,encoding='utf-8')
        if rc or '** Error' in last or '** Fatal' in last:
            details=[f'command {i} failed'];break
        if i==3:status,details=run_sim.judge(last,rc)
    if any(hashlib.sha256(p.read_bytes()).hexdigest()!=digests[str(p)] for p in files):status='SOURCES_CHANGED'
    result={'status':status,'details':details,'input_sha256':digests,'simulation_define':False,
            'scope':'real PLL functional model only; no board measurements or STA closure','stage':stage.as_posix()}
    (output/'result.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    (ROOT/'sim/vendor_pll/latest.json').write_text(json.dumps({'status':status,'result':(output/'result.json').relative_to(ROOT).as_posix()},indent=2)+'\n')
    print(f'{status}: {output.relative_to(ROOT)}')
    if status!='PASS':print(last[-4500:])
    return 0 if status=='PASS' else 1


if __name__=='__main__':raise SystemExit(main())

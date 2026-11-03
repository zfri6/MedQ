"""Exercise the REAL non-SIMULATION serializer with unmodified installed EG4 models."""
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
import run_sim

ROOT = Path(__file__).resolve().parents[1]


def main():
    tc = json.loads((ROOT/'doc/hw/toolchain.json').read_text(encoding='utf-8'))
    ms = Path(tc['modelsim_bin'])
    lib = Path(tc['td']['td_home'])/'sim_release/eg4'
    files = [ROOT/'rtl/tmds_serdes.v', ROOT/'tb/vendor/tb_tmds_serdes_eg4.v',
             lib/'eg_logic_io.v', lib/'eg_phy_glbl.v']
    hashes = {str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
    stage = Path(tempfile.mkdtemp(prefix='medq_eg4_serdes_'))
    output = ROOT/'sim/vendor_serdes'/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    output.mkdir(parents=True, exist_ok=False)
    for p in files:
        shutil.copy2(p, stage/p.name)
    commands = [[str(ms/'vlib.exe'),'work'],
                [str(ms/'vlog.exe'),'-work','work','eg_logic_io.v','eg_phy_glbl.v','tmds_serdes.v'],
                [str(ms/'vlog.exe'),'-sv','-work','work','tb_tmds_serdes_eg4.v'],
                [str(ms/'vsim.exe'),'-c','-voptargs=+acc','work.tb_tmds_serdes_eg4','work.glbl','-do','run -all; quit -f']]
    all_logs=[]
    status,details='FAIL',[]
    for i,cmd in enumerate(commands):
        try:
            p=subprocess.run(cmd,cwd=stage,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=90)
            text=p.stdout.decode('utf-8',errors='replace');rc=p.returncode
        except subprocess.TimeoutExpired:
            text='TIMEOUT vendor simulation';rc=124
        (output/f'{i}.log').write_text('$ '+' '.join(cmd)+'\n'+text,encoding='utf-8')
        all_logs.append(text)
        if rc or any('** Error' in line or '** Fatal' in line for line in text.splitlines()):
            details=[f'command {i} failed'];break
        if i==3:
            status,details=run_sim.judge(text,rc)
    current={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
    if current!=hashes:
        status='SOURCES_CHANGED'
    result={'status':status,'details':details,'profile':'EG4 vendor ODDR functional model',
            'simulation_define':False,'stage':stage.as_posix(),'input_sha256':hashes,
            'scope':'serializer only, clocks driven by TB; no PLL/SDRAM/board/timing-closure claim'}
    (output/'result.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    (ROOT/'sim/vendor_serdes/latest.json').write_text(json.dumps({'result':(output/'result.json').relative_to(ROOT).as_posix(),'status':status},indent=2)+'\n',encoding='utf-8')
    print(f'{status}: {output.relative_to(ROOT)}')
    if status!='PASS':print('\n'.join(all_logs)[-4000:])
    return 0 if status=='PASS' else 1


if __name__=='__main__':raise SystemExit(main())

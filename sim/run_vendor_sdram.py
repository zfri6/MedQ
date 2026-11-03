"""Original encrypted SDRAM controller with independent physical bus/data tests."""
from pathlib import Path
import argparse,hashlib,json,shutil,subprocess,tempfile
from datetime import datetime,timezone
import run_sim
ROOT=Path(__file__).resolve().parents[1]
def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--probe',action='store_true')
    ap.add_argument('--system',action='store_true',help='full MedQ top, real memory controller, behavioral clocks/serializer')
    ap.add_argument('--bandwidth',action='store_true',help='two VGA frames through real SDRAM and display FIFO at 50 MHz memory')
    ap.add_argument('--real-pll',action='store_true',help='drive the hardware/bandwidth TB with sys_pll and installed vendor PLL/glbl models')
    ap.add_argument('--system-tb',choices=['tb_top','tb_basic_calling','tb_v03_top_audio','tb_media_top'],default='tb_top')
    ap.add_argument('--timeout',type=int,default=180)
    a=ap.parse_args()
    if sum([a.probe,a.system,a.bandwidth])>1:ap.error('choose one profile')
    if a.real_pll and (a.probe or a.system):ap.error('--real-pll is for adapter/bandwidth profiles')
    top='tb_sdram_bandwidth' if a.bandwidth else a.system_tb if a.system else 'tb_sdram_core_probe' if a.probe else 'tb_sdram_hardware'
    tc=json.loads((ROOT/'doc/hw/toolchain.json').read_text(encoding='utf-8'))
    ms=Path(tc['modelsim_bin']);lib=Path(tc['td']['td_home'])/'sim_release/eg4'
    files=list((ROOT/'rtl/al_ip/sdram_vendor').glob('*'))
    files+=[lib/'eg_phy_sdram_2m_32.v']
    if a.system:
        rtl,tb=run_sim.sources(top)
        files+=[Path(p) for p in rtl+tb]+[ROOT/'rtl/al_ip/sdram.v',ROOT/'tb/vendor/medq_sdram_device_model.v']
        files+=list((ROOT/'rtl').glob('*.hex'))+list((ROOT/'rtl').glob('*.vh'))+list((ROOT/'tb').glob('*.hex'))
    else:
        files+=[ROOT/f'tb/vendor/{top}.v']
        if not a.probe:files+=[ROOT/'rtl/medq_sdram_adapter.v',ROOT/'rtl/al_ip/sdram.v',ROOT/'tb/vendor/medq_sdram_device_model.v']
        if a.bandwidth:files+=[ROOT/'rtl/frame_reader.v',ROOT/'rtl/medq_async_fifo.v',ROOT/'rtl/sdram_arbiter.v']
    if a.real_pll:files+=[ROOT/'rtl/al_ip/sys_pll.v',lib/'eg_logic_clk.v',lib/'eg_phy_pll.v',lib/'eg_phy_glbl.v']
    digests={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
    stage=Path(tempfile.mkdtemp(prefix='medq_sdram_'))
    out=ROOT/'sim/vendor_sdram'/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    out.mkdir(parents=True,exist_ok=False)
    for p in files:shutil.copy2(p,stage/p.name)
    # Preserve the encrypted source's original ../user_source/... include.
    # The extra search base resolves it wholly inside this fresh run directory.
    (stage/'compat').mkdir()
    legacy=stage/'user_source/hdl_source/include'
    legacy.mkdir(parents=True)
    shutil.copy2(stage/'global_def.v',legacy/'global_def.v')
    sources=[p.name for p in files if p.suffix=='.v']
    # Legacy vendor init RTL concatenates an unsized constant (vlog-2121).
    # Keep its bytes; scope this documented compatibility switch to this runner.
    commands=[[str(ms/'vlib.exe'),'work'],[str(ms/'vlog.exe'),'-sv','-suppress','2121','+incdir+.+compat','-work','work']+sources,
      [str(ms/'vsim.exe'),'-c',f'work.{top}','-do','run -all; quit -f']]
    if a.real_pll:
        commands[1].insert(1,'+define+MEDQ_VENDOR_PLL')
        commands[2].insert(3,'work.glbl')
        # The vendor PLL's Verilog port named "do" is an SV keyword. Compile
        # that unmodified library/wrapper as Verilog, separately from the TB.
        pll_names=['eg_logic_clk.v','eg_phy_pll.v','eg_phy_glbl.v','sys_pll.v']
        commands[1]=[v for v in commands[1] if v not in pll_names]
        commands.insert(1,[str(ms/'vlog.exe'),'-work','work']+pll_names)
    if a.system:
        core=[p.name for p in files if p.name.endswith('.enc.v') or p.name=='global_def.v']
        application=[p for p in sources if p not in core]
        commands=[commands[0],commands[1][:-len(sources)]+core,
          [str(ms/'vlog.exe'),'-sv','+define+SIMULATION+MEDQ_REAL_SDRAM','+incdir+.', '-work','work']+application,commands[2]]
    status='FAIL';details=[];last=''
    for i,cmd in enumerate(commands):
        try:
            p=subprocess.run(cmd,cwd=stage,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=a.timeout)
            last=p.stdout.decode('utf-8',errors='replace');rc=p.returncode
        except subprocess.TimeoutExpired:
            last='TIMEOUT SDRAM vendor run';rc=124
        (out/f'{i}.log').write_text('$ '+' '.join(cmd)+'\n'+last,encoding='utf-8')
        if rc or '** Error' in last or '** Fatal' in last:details=[f'command {i} failed'];break
        if i==len(commands)-1:status,details=run_sim.judge(last,rc)
    if any(hashlib.sha256(p.read_bytes()).hexdigest()!=digests[str(p)] for p in files):status='SOURCES_CHANGED'
    result={'status':status,'top':top,'details':details,'input_sha256':digests,'stage':stage.as_posix(),
      'core_defines':[],'application_defines':['SIMULATION','MEDQ_REAL_SDRAM'] if a.system else [],
      'simulation_define':a.system,'real_pll':a.real_pll,
      'scope':('protocol observation only; installed EG SDRAM model is an empty shell' if a.probe else
      'original encrypted controller plus independent BL4/CL3 physical SDRAM model with AC/refresh checks; optional installed PLL model; not board or routed STA evidence')}
    (out/'result.json').write_text(json.dumps(result,indent=2)+'\n')
    for artifact in stage.glob('*.ppm'):shutil.copy2(artifact,out/artifact.name)
    (ROOT/'sim/vendor_sdram/latest.json').write_text(json.dumps({'status':status,'result':(out/'result.json').relative_to(ROOT).as_posix()},indent=2)+'\n')
    profile='bandwidth' if a.bandwidth else 'probe' if a.probe else ('basic' if top=='tb_basic_calling' else 'audio' if top=='tb_v03_top_audio' else 'media' if top=='tb_media_top' else 'system') if a.system else 'adapter'
    if a.real_pll:profile+='_real_pll'
    (ROOT/f'sim/vendor_sdram/latest_{profile}.json').write_text(json.dumps({'status':status,'result':(out/'result.json').relative_to(ROOT).as_posix()},indent=2)+'\n')
    print(f'{status}: {out.relative_to(ROOT)}')
    print(last[-6000:] if a.probe or status!='PASS' else '\n'.join(l for l in last.splitlines() if 'PASS' in l or 'CHECK' in l))
    return 0 if status=='PASS' else 1
if __name__=='__main__':raise SystemExit(main())

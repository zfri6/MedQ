"""Bind the new media release to current simulations, native STA and bitgen."""
from pathlib import Path
import json
import re
import shutil
import subprocess
import sys
import medq_td
import signoff_timing

ROOT=medq_td.ROOT
REVISION='media_carousel_20261103'
EVIDENCE=ROOT/'doc/compile/media_carousel'
def read(p):return json.loads((ROOT/p).read_text(encoding='utf-8'))
def dump(p,obj):medq_td.dump(ROOT/p,obj)

def main():
    simulation=signoff_timing.simulation_gate()
    regression=read('sim/regression_result.json')
    pointer=read('prj/td/latest_timing_bitstream.json')
    bit=read(pointer['result']);signed=read(bit['parent_signoff'])
    assert bit['status']==signed['status']=='PASS' and 'MEDIA_COVER_' in bit['bitstream']
    signoff_timing.check_hashes(bit['source_sha256'])
    signoff_timing.check_hashes(bit['simulation_evidence_sha256'])
    assert medq_td.sha(ROOT/bit['parent_signoff'])==bit['parent_signoff_sha256']
    assert medq_td.sha(ROOT/bit['bitstream'])==bit['bitstream_sha256']
    intake=read('doc/compile/media_intake.json');prior=intake['prior_release']
    for kind in ('archive','bitstream'):
        assert medq_td.sha(ROOT/prior[kind])==prior[kind+'_sha256']
    snapshot=ROOT/intake['snapshot']
    for name,digest in intake['files'].items():assert medq_td.sha(snapshot/name)==digest
    allowed={'rtl/asset_loader.v','rtl/audio_mixer.v','rtl/fat32_reader.v','rtl/medq_dual_ui_scene.v',
             'rtl/osd_renderer.v','rtl/top.v','rtl/top_skeleton.v','rtl/medq_media_control.v','rtl/medq_audio_wave.v'}
    changed=[]
    for p in sorted((ROOT/'rtl').rglob('*')):
        if not p.is_file():continue
        name=p.relative_to(ROOT).as_posix()
        if name not in intake['files'] or medq_td.sha(p)!=intake['files'][name]:changed.append(name)
    assert set(changed)==allowed,changed
    for p in (ROOT/'prj/constr').glob('*'):
        if p.is_file():assert medq_td.sha(p)==intake['files'][p.relative_to(ROOT).as_posix()]
    clips=read('assets/voice_manifest.json')['clips'];assert len(clips)==54
    for item in clips:
        p=ROOT/'assets/sd_root'/item['file']
        assert medq_td.sha(p)==item['sha256']==intake['files'][p.relative_to(ROOT).as_posix()]
    media=read('assets/media_manifest.json');assert len(media['images'])==3
    for item in media['images']:
        assert medq_td.sha(ROOT/item['runtime'])==item['sha256']
        assert medq_td.sha(ROOT/item['source'])==item['source_sha256']
    targeted=read('doc/compile/patient_names/targeted_latest.json')
    assert {read(p)['top'] for p in targeted}=={'tb_named_pcm','tb_patient_pcm_path'}
    for p in targeted:
        result=read(p);assert result['status']=='PASS'
        signoff_timing.check_hashes(result['input_sha256'])
        simulation[p]=medq_td.sha(ROOT/p)
    media_pointer=read('sim/vendor_sdram/latest_media.json')
    real=read(media_pointer['result']);assert real['status']=='PASS' and real['top']=='tb_media_top'
    signoff_timing.check_hashes(real['input_sha256'],absolute=True)
    # Format conversion only; the supplied photographs have traversed the RTL.
    commands=[['sim/capture_media.py','--source','sim/tests/modelsim/tb_media_pixels'],
              ['sim/capture_media.py','--source',str(Path(media_pointer['result']).parent),'--destination','sim/ui/media_real_system']]
    for arguments in commands:subprocess.run([sys.executable]+arguments,cwd=ROOT,check=True)
    for name in ('sim/ui/media_rtl/capture_manifest.json','sim/ui/media_real_system/capture_manifest.json'):
        capture=read(name);simulation[name]=medq_td.sha(ROOT/name)
        for row in capture['frames']:
            assert medq_td.sha(ROOT/row['source'])==row['source_sha256']
            assert medq_td.sha(ROOT/row['png'])==row['png_sha256']
            simulation[row['source']]=row['source_sha256'];simulation[row['png']]=row['png_sha256']
    expected={
      'tb_cover_isolation':'PASS cover:', 'tb_named_bmp':'PASS named BMP:',
      'tb_media_invalid':'PASS invalid named native BMP:',
      'tb_media_assets':'921600 exact RGB words',
      'tb_media_pixels':'350208 independently blended photo pixels',
      'tb_audio_wave':'PASS HDMI waveform:', 'tb_audio_mixer_signed':'4105 independent integer reference checks',
      'tb_media_top':'PASS actual board-pin SD media system:',
      'tb_marquee_seamless':'14042240 exact independent raster checks'}
    for tb,needle in expected.items():
        log=ROOT/'sim/tests/modelsim'/tb/'sim.log'
        assert needle in log.read_text(encoding='utf-8')
        simulation[log.relative_to(ROOT).as_posix()]=medq_td.sha(log)
    original_defect=ROOT/'sim/media_checks/mixer_original_defect/sim.log'
    assert 'got=32767 expected=-500' in original_defect.read_text(encoding='utf-8')
    EVIDENCE.mkdir(parents=True,exist_ok=True)
    command=[sys.executable,'-m','unittest','discover','-s','prj/td','-p','test_*.py','-v']
    tests=subprocess.run(command,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,encoding='utf-8',timeout=60)
    (EVIDENCE/'tool_tests.log').write_text(tests.stdout,encoding='utf-8')
    count=re.search(r'Ran (\d+) tests',tests.stdout)
    assert tests.returncode==0 and count and int(count[1])>=36 and re.search(r'^OK\s*$',tests.stdout,re.M)
    tool_hashes={p.relative_to(ROOT).as_posix():medq_td.sha(p) for p in sorted((ROOT/'prj/td').glob('*.py'))}
    dump('doc/compile/media_carousel/tool_tests.json',dict(status='PASS',tests=int(count[1]),source_sha256=tool_hashes))
    card=ROOT/'deliverables/TF_CARD_MEDIA_20261103'
    sd=card/'SD_ROOT';sd.mkdir(parents=True,exist_ok=True)
    names=[c['file'] for c in clips]+['COVER.BMP','DOC01.BMP','DOC02.BMP']
    assert len(names)==57
    for name in names:
        source=ROOT/'assets/sd_root'/name;target=sd/name
        if target.exists():assert medq_td.sha(target)==medq_td.sha(source)
        else:shutil.copy2(source,target)
    assert {p.name for p in sd.iterdir()}==set(names)
    card_hashes={p.name:medq_td.sha(p) for p in sorted(sd.iterdir())}
    dump('deliverables/TF_CARD_MEDIA_20261103/TF_MANIFEST.json',dict(revision=REVISION,files=card_hashes,files_count=57))
    instructions='''MedQ V0.3 封面和医生轮播版 TF 卡

1. 使用 FAT32 格式的 TF 卡。将 SD_ROOT 内全部57个文件直接复制到卡的根目录，不要把 SD_ROOT 文件夹本身复制进去。
2. 根目录应有 COVER.BMP、DOC01.BMP、DOC02.BMP，以及 CLIP00.PCM 至 CLIP53.PCM。不要把 JPG、PNG、WAV 或 bit 位流当成运行素材复制进根目录。
3. 在 TD 下载配套 MEDIA_COVER 新版 bit；重新上电显示封面，K1..K4 任意键进入。进入键不会取号，全部松开后新的按键才启用诊室功能。
4. 系统内 K1=A初诊，K2=B初诊，K3=A回诊，K4=B回诊；SW1=A叫号，SW2=B叫号，SW3=A医生到位/离开，SW4=B医生到位/离开。SW1/2低有效。
5. 医生照片自动轮播。右下波形反映实际 HDMI 播报音频，静音时是平线。语音经 HDMI 输出。
6. 男医生选择较大的 PNG。运行 BMP 已离线高质量缩放并固定为640x480/24bit；替换图片请按工程 sim/build_media_assets.py 重新转换，不要直接改扩展名。
7. 本包完成本机仿真、原生时序与封包校验，尚未实板下载/验收。board_test: not_tested。
'''
    (card/'README.txt').write_text(instructions,encoding='utf-8-sig')
    previous=read('doc/compile/seamless_marquee_delivery.json')['physical_resources']
    area=signed['physical_resources'];values=signed['timing']['values']
    delta={k:dict(before=previous[k]['used'],after=area[k]['used'],change=area[k]['used']-previous[k]['used']) for k in ('lut','reg','bram','dsp')}
    implementation=read(signed['original_result'])
    parent=Path(implementation['parent_gate']).parent.parent
    saved=EVIDENCE/'native_parent'/parent.name
    if not saved.exists():shutil.copytree(parent,saved)
    attempts=[]
    for result_path in sorted((ROOT/'prj/td/runs').glob('20261103*/result.json')):
        candidate=json.loads(result_path.read_text(encoding='utf-8'))
        entry=dict(result=result_path.relative_to(ROOT).as_posix(),status=candidate['status'],
                   selected=result_path==ROOT/signed['original_result'],source_current=candidate.get('meta',{}).get('source_sha256')==signed['source_sha256'])
        attempts.append(entry)
        if result_path!=ROOT/signed['original_result'] and result_path.parent!=parent:
            dest=EVIDENCE/'native_attempts'/result_path.parent.name
            if not dest.exists():shutil.copytree(result_path.parent,dest)
    destination=ROOT/'deliverables'/Path(bit['bitstream']).name
    if destination.exists():assert medq_td.sha(destination)==bit['bitstream_sha256']
    else:shutil.copy2(ROOT/bit['bitstream'],destination)
    destination.with_suffix('.sha256').write_text(bit['bitstream_sha256']+'  '+destination.name+'\n',encoding='ascii')
    result=dict(status='PC_SIGNOFF_PASS',revision=REVISION,board_test='not_tested',
        specification='doc/spec/media_carousel_20261103.md',changed_rtl=changed,
        modelsim_regression=len(regression['results']),additional_modelsim_tests=2,tool_gate_tests=int(count[1]),
        simulation_evidence_sha256=simulation,voice_assets=54,voice_assets_unchanged=True,
        media_assets=media,tf_card_directory=card.relative_to(ROOT).as_posix(),tf_card_root_sha256=card_hashes,
        native_signoff=bit['parent_signoff'],native_setup_hold_ns=values,physical_resources=area,
        resource_change_vs_previous_sealed_release=delta,native_attempts=attempts,
        bitstream=destination.relative_to(ROOT).as_posix(),bitstream_sha256=bit['bitstream_sha256'],
        prior_release_unchanged=prior,preserved_snapshot=intake['snapshot'],preserved_native_gate_parent=saved.relative_to(ROOT).as_posix(),
        preview='sim/ui/media_real_system/media_top_clinic.png')
    dump('doc/compile/media_carousel_delivery.json',result)
    summary=f'''# MedQ V0.3 SD封面、医生轮播和音频波形版（2026-11-03）

上电从TF卡读取用户提供的封面；K1..K4任意键进入诊室系统。进入键被单独消费，全部按键稳定松开后才重新初始化诊室按键/开关，封面操作不会取号或触发医生事件。SW1/SW2独立A/B叫号、SW3/SW4医生、四路初诊/回诊取号及所有原队列规则保留。

右侧地图缩为152x100区域；下方显示一名医生，男/女两张照片自动轮播。照片显示152x128，保持约4秒，采用逐帧smoothstep淡出/淡入（每方向约0.55秒），零透明度换图，隐藏3帧等待现有读取FIFO和CDC稳定；不会同时叠放两位医生。男医生选用较大PNG，另一张男医生原图完整保留。

右下角波形取最终HDMI有符号音频，做32点帧快照、线性插值及边缘覆盖度；静音平线，封面隐藏。独立测试发现旧混音器将负采样零扩展且未正确做Q0.8缩放，负1000/音量128错误输出32767；本版修正为-500，4105项数值对照通过。全部54段PCM、全名语音提速、名单、屏幕张*民隐私遮罩、四级抗锯齿字体和居中连续循环字幕素材保持原字节。

## 直接部署

- 位流：{result['bitstream']}
- SHA256：{bit['bitstream_sha256']}
- TF卡：{result['tf_card_directory']}/SD_ROOT，共57个文件。把里面的文件直接复制到FAT32根目录。包含3张BMP和原54段PCM，按文件名定位，不依赖复制顺序。
- BMP是电脑端Lanczos缩放的640x480/24bit无压缩文件；JPG/PNG原图放assets/media_source，运行时不使用JPEG/PNG解码或片内图片ROM。
- 旧TF卡必须增加3张BMP；建议使用本包完整SD_ROOT。声音仍经HDMI屏幕/接收设备输出。

## 本机证据

ModelSim完整{len(regression['results'])}/{len(regression['results'])}通过，另2项命名PCM/396整句语音链路专项通过；Verilog-2001检查通过。SD卡多簇读取与跨时钟/反压写入对照921600个实际图片像素；独立封面307200像素、18种照片混合350208像素、4320000个原叫号/字幕区像素对照通过。原14042240点字幕全环回归继续通过。

整机使用原加密SDRAM控制器及独立物理器件模型：图片未全加载前封面已先显示；进入键不误取号；3张图片、54段PCM加载完整；A/B并发18段播放；最终307200封面像素和19456照片像素逐一一致；无显示/音频欠载。原整机业务、长语音取消/暂停、无卡降级和PLL/串行器/带宽证据也通过当前源码哈希核验。36项工具/负向签核测试通过。

实际RTL预览：sim/ui/media_real_system（整机实际SD读取）、sim/ui/media_rtl（独立像素对照）。sim/ui/media_assets是输入素材转换预览，不是RTL或实板证据。

## 时序与资源

原生slow/fast所有setup/hold组通过：WNS {values['SWNS']:+.3f}/{values['HWNS']:+.3f}ns，TNS0，违例端点0；fresh bitgen重新导入同一路由库并检查STA。
LUT {area['lut']['used']}/19600，REG {area['reg']['used']}/19600，BRAM {area['bram']['used']}/64（上一版62），DSP {area['dsp']['used']}/29（上一版20）。板级管脚、PLL频率、SDRAM相位和所有约束保持字节一致，没有增加false path或放宽时序。

签核：{bit['parent_signoff']}。版本权威为deliverables/latest_v03.json，详细结果doc/compile/media_carousel_delivery.json。旧封包、位流、V0.2及修改前源码快照保留。

## 复现

    python sim/build_media_assets.py
    python sim/build_media_fixtures.py
    python sim/run_regression.py --sim modelsim --timeout 1200
    python prj/td/verify_patient_paths.py tb_named_pcm tb_patient_pcm_path
    python sim/run_vendor_sdram.py --system --system-tb tb_media_top --timeout 1200
    python sim/run_vendor_sdram.py --system --timeout 400
    python sim/run_vendor_sdram.py --system --system-tb tb_v03_top_audio --timeout 400
    python sim/run_vendor_sdram.py --system --system-tb tb_basic_calling --timeout 120
    python prj/td/medq_td.py --mode synth --run
    python prj/td/route_seed.py --parent-result <new-synth-result.json> --seed 23
    python prj/td/signoff_timing.py --result <new-route-result.json> --bitgen
    python prj/td/finalize_media_release.py
    python prj/td/package_media_release.py
    python prj/td/seal_timing_release.py

board_test: not_tested。未进行实板下载、HDMI屏幕/扬声器验收或真实TF卡速度测量。
'''
    (ROOT/'README.md').write_text(summary,encoding='utf-8')
    (ROOT/'doc/compile/v03_report.md').write_text(summary,encoding='utf-8')
    dump('doc/compile/v03_status.json',dict(version='0.3',revision=REVISION,implementation='complete',simulation='PASS',
        modelsim_tests=len(regression['results']),additional_modelsim_tests=2,sta='PASS',bitstream='PASS',board_test='not_tested',
        release_authority='deliverables/latest_v03.json',bitstream_path=result['bitstream'],bitstream_sha256=bit['bitstream_sha256'],signoff=bit['parent_signoff']))
    handoff=ROOT/'HANDOFF.md';current=handoff.read_text(encoding='utf-8');marker='\n\n## 14. SD封面、医生轮播和音频波形'
    if marker in current:current=current[:current.index(marker)]
    handoff.write_text(current+marker+'（2026-11-03）\n\n'+summary,encoding='utf-8')
    hardware=read('doc/hw/toolchain.json')
    hardware['td'].update(timing_signoff=bit['parent_signoff'],bitstream_evidence=pointer['result'],physical_resource_status=area,
        implementation_status='native_routed_strict_signoff_PASS',bitstream_generated=True,license_status='PASS',
        license_evidence=signed['original_result'],full_top_analysis_evidence=signed['original_result'])
    dump('doc/hw/toolchain.json',hardware)
    print('MEDIA_DELIVERY_PASS',len(regression['results']),'+2',values,delta,'board_test: not_tested')

if __name__=='__main__':main()

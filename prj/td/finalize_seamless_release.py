"""Seal centered, continuous subtitle evidence without changing speech assets."""
from pathlib import Path
import hashlib
import json
import re
import shutil
import subprocess
import sys
import zipfile
from PIL import Image
import medq_td
import signoff_timing

ROOT = medq_td.ROOT
REVISION = 'seamless_marquee_20261102'
EVIDENCE = 'doc/compile/seamless_marquee'


def read(path):
    return json.loads((ROOT / path).read_text(encoding='utf-8'))


def dump(path, obj):
    medq_td.dump(ROOT / path, obj)


def preserve(source, destination):
    if not destination.exists():
        shutil.copytree(source, destination)
    for p in source.rglob('*'):
        if p.is_file():
            assert medq_td.sha(p) == medq_td.sha(destination / p.relative_to(source))


def main():
    simulation = signoff_timing.simulation_gate()
    reg = read('sim/regression_result.json')
    pointer = read('prj/td/latest_timing_bitstream.json')
    bit = read(pointer['result'])
    signed = read(bit['parent_signoff'])
    assert bit['status'] == signed['status'] == 'PASS'
    assert 'SEAMLESS_MARQUEE_' in bit['bitstream']
    signoff_timing.check_hashes(bit['source_sha256'])
    signoff_timing.check_hashes(bit['simulation_evidence_sha256'])
    assert medq_td.sha(ROOT / bit['parent_signoff']) == bit['parent_signoff_sha256']
    assert medq_td.sha(ROOT / bit['bitstream']) == bit['bitstream_sha256']
    snapshots = list((ROOT/'baseline').glob('v03_pre_seamless_marquee_*/manifest.json'))
    assert len(snapshots) == 1
    frozen = read(snapshots[0].relative_to(ROOT))
    old = frozen['previous_release']
    for kind in ('archive', 'bitstream'):
        assert medq_td.sha(ROOT / old[kind]) == old[kind+'_sha256']
    with zipfile.ZipFile(ROOT / old['archive']) as z:
        changed_rtl = []
        for p in sorted((ROOT/'rtl').rglob('*')):
            if p.is_file() and p.suffix != '.pyc':
                name = p.relative_to(ROOT).as_posix()
                if p.read_bytes() != z.read(name):
                    changed_rtl.append(name)
        assert changed_rtl == ['rtl/medq_dual_ui_scene.v'], changed_rtl
        assets = []
        for p in sorted((ROOT/'assets').rglob('*')):
            if p.is_file() and p.suffix != '.pyc':
                name = p.relative_to(ROOT).as_posix()
                assert p.read_bytes() == z.read(name), 'Speech/patient asset changed: '+name
                assets.append(name)
        for p in (ROOT/'prj/constr').glob('*'):
            if p.is_file():
                assert p.read_bytes() == z.read(p.relative_to(ROOT).as_posix())
        previous = json.loads(z.read('doc/compile/masked_smooth_delivery.json'))
    clips = read('assets/voice_manifest.json')['clips']
    assert len(clips) == 54
    card = previous['tf_card_directory']
    for clip in clips:
        assert medq_td.sha(ROOT/'assets/sd_root'/clip['file']) == clip['sha256']
        assert medq_td.sha(ROOT/card/'SD_ROOT'/clip['file']) == clip['sha256']
    assert len(list((ROOT/card/'SD_ROOT').iterdir())) == 54
    targeted = read('doc/compile/patient_names/targeted_latest.json')
    assert {read(p)['top'] for p in targeted} == {'tb_named_pcm', 'tb_patient_pcm_path'}
    for p in targeted:
        result = read(p)
        assert result['status'] == 'PASS' and result['tool'] == 'modelsim'
        signoff_timing.check_hashes(result['input_sha256'])
        simulation[p] = medq_td.sha(ROOT/p)
    for p in ('assets/speech_previews/pace_comparison.json', 'doc/compile/masked_smooth/lossless_font_packing.json'):
        quality = read(p)
        assert quality['status'] == 'PASS'
        signoff_timing.check_hashes(quality['source_sha256'])
        simulation[p] = medq_td.sha(ROOT/p)
    ring_log = ROOT/'sim/tests/modelsim/tb_marquee_seamless/sim.log'
    text = ring_log.read_text(encoding='utf-8')
    assert re.search(r'PASS 14042240 exact independent raster checks', text)
    assert '23680 immediate left-to-right seam exchanges' in text
    capture_path = 'sim/ui/seamless_marquee/capture_manifest.json'
    cap = read(capture_path)
    assert cap['source_directory'] == 'sim/tests/modelsim/tb_marquee_seamless'
    assert len(cap['frames']) == 38 and cap['positions_per_revolution'] == 592
    for row in cap['frames']:
        assert medq_td.sha(ROOT/row['source']) == row['ppm_sha256']
        assert medq_td.sha(ROOT/row['png']) == row['png_sha256']
        simulation[row['source']] = row['ppm_sha256']
        simulation[row['png']] = row['png_sha256']
    simulation[capture_path] = medq_td.sha(ROOT/capture_path)
    simulation[ring_log.relative_to(ROOT).as_posix()] = medq_td.sha(ring_log)
    full_path = 'sim/ui/v03_rtl/capture_manifest.json'
    full = read(full_path)
    assert len(full['frames']) == 12 and not full['identical_adjacent_frames']
    preview = ROOT/'sim/ui/seamless_marquee'
    sheet = Image.new('RGB', (1280, 444), 'white')
    for i, row in enumerate(full['frames']):
        assert medq_td.sha(ROOT/row['source']) == row['ppm_sha256']
        assert medq_td.sha(ROOT/row['png']) == row['png_sha256']
        im = Image.open(ROOT/row['png']).convert('RGB')
        sheet.paste(im.crop((0,67,640,141)), ((i%2)*640, (i//2)*74))
    sheet.save(preview/'actual_top_subtitles.png')
    simulation[full_path] = medq_td.sha(ROOT/full_path)
    for row in full['frames']:
        simulation[row['source']] = row['ppm_sha256']
        simulation[row['png']] = row['png_sha256']
    implementation = read(signed['original_result'])
    gate = Path(implementation['parent_gate'])
    parent = next(p for p in gate.parents if (p/'result.json').is_file())
    parent_result = read((parent/'result.json').relative_to(ROOT))
    assert parent_result['status'] == 'PASS'
    assert parent_result['meta']['source_sha256'] == implementation['meta']['source_sha256']
    assert medq_td.sha(gate) == implementation['parent_gate_sha256']
    saved_parent = ROOT/EVIDENCE/'native_parent'/parent.name
    preserve(parent, saved_parent)
    attempts = []
    for path in sorted((ROOT/'prj/td/runs').glob('*/result.json')):
        candidate = read(path.relative_to(ROOT))
        if candidate.get('meta',{}).get('source_sha256') != implementation['meta']['source_sha256']:
            continue
        if 'placement_seed' not in candidate.get('meta',{}):
            continue
        entry = {'result':path.relative_to(ROOT).as_posix(), 'seed':candidate['meta']['placement_seed'],
                 'raw_status':candidate['status'], 'timing':candidate.get('timing_slack_ns')}
        if path != ROOT/signed['original_result']:
            saved = ROOT/EVIDENCE/'native_attempts'/path.parent.name
            preserve(path.parent, saved)
            entry['package_evidence'] = saved.relative_to(ROOT).as_posix()
        attempts.append(entry)
    command = [sys.executable, '-m', 'unittest', 'discover', '-s', 'prj/td', '-p', 'test_*.py', '-v']
    tests = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, encoding='utf-8', timeout=60)
    (ROOT/EVIDENCE).mkdir(parents=True, exist_ok=True)
    (ROOT/EVIDENCE/'tool_tests.log').write_text(tests.stdout, encoding='utf-8')
    number = re.search(r'Ran (\d+) tests', tests.stdout)
    assert tests.returncode == 0 and number and int(number[1]) >= 36 and re.search(r'^OK\s*$', tests.stdout,re.M)
    dump(EVIDENCE+'/tool_tests.json', {'status':'PASS','tests':int(number[1]),
         'source_sha256':{p.relative_to(ROOT).as_posix():medq_td.sha(p) for p in sorted((ROOT/'prj/td').glob('*.py'))}})
    before, after = previous['physical_resources'], signed['physical_resources']
    delta = {k:{'before':before[k]['used'],'after':after[k]['used'],'change':after[k]['used']-before[k]['used']} for k in ('lut','reg','bram','dsp')}
    native_dir = (ROOT/signed['original_result']).parent
    qor = (native_dir/'reports/MedQv03_route.qor').read_text(encoding='utf-8')
    slices = float(re.search(r'slices percentage\s*\|\s*([\d.]+)%',qor)[1])
    values = signed['timing']['values']
    result = {'status':'PC_SIGNOFF_PASS','revision':REVISION,'board_test':'not_tested',
        'specification':'doc/spec/seamless_marquee_20261102.md','screen':'center each new sentence, then leftward 592-pixel torus; outgoing left pixel immediately enters right; no horizontal edge fade',
        'unchanged_assets':assets,'changed_rtl':changed_rtl,'voice_assets':54,'voice_assets_unchanged':True,
        'modelsim_regression':len(reg['results']),'additional_modelsim_tests':len(targeted),
        'independent_name_pixels':2012800,'independent_event_pixels':1065600,
        'independent_full_ring_pixels':14042240,'immediate_edge_exchange_checks':23680,
        'font_and_coverage':'unchanged four-level AA; no frame buffer or duplicated font',
        'tool_gate_tests':int(number[1]),'simulation_evidence_sha256':simulation,
        'native_signoff':bit['parent_signoff'],'native_setup_hold_ns':values,'physical_resources':after,
        'resource_change_vs_previous_sealed_release':delta,'slice_percent':slices,
        'tf_card_directory':card,'tf_card_update_required_vs_masked_smooth':False,
        'preview':'sim/ui/seamless_marquee/continuous.gif','native_placement_attempts':attempts,
        'bitstream':'deliverables/'+Path(bit['bitstream']).name,'bitstream_sha256':bit['bitstream_sha256'],
        'previous_release_unchanged':old,'preserved_native_gate_parent':saved_parent.relative_to(ROOT).as_posix()}
    dump('doc/compile/seamless_marquee_delivery.json', result)
    summary = f'''# MedQ V0.3 居中刷新、连续循环字幕（2026-11-02）

A/B新操作仍在下一帧立即刷新，整句按实际字形宽度居中，然后按原速每两帧向左一像素（约29.76px/s）。x24..615为592像素环，左侧移出的像素在同一步从右侧进入，没有等整句退出的空白阶段。取消字幕窗口水平渐隐，原四级抗锯齿保持。

屏幕仍为“请C01张*民到A诊室就诊”；语音仍播完整姓名，保持上一版提速、去边缘静音后的54段PCM。SW1/SW2独立叫号、SW3/SW4医生功能、取号/回诊/计数/优先级/暂停排空与重播均保留。本次RTL只修改medq_dual_ui_scene.v，所有字体、患者表、音频素材、底层RTL及约束与上一封版逐文件一致。

## 更新
仅更新新版位流：{result['bitstream']}。SHA256：{bit['bitstream_sha256']}。
已使用MASKED_SMOOTH版54段PCM的TF卡无需重拷。完整配套音频仍在{card}/SD_ROOT；更旧的慢速TF卡应更新这54段，音频经HDMI输出。

## 验证
ModelSim完整{len(reg['results'])}/{len(reg['results'])}通过，另2项实际FAT/SDRAM/PCM链路专项通过。独立名单像素2012800点、18类事件1065600点；新增全环14042240点、双室592个位置、23680次左出右入边缘交换和零空帧检查通过。字模、遮罩与颜色精确比较，不使用DUT计算作为像素期望。整机真实SDRAM、长语音和无卡降级均通过，原完整业务与外设回归保留。
真实整机12帧见sim/ui/v03_rtl；592步全环38帧字幕见sim/ui/seamless_marquee/，continuous.gif/APNG按实际速度播放，无软件重画文字。36项工具负向与签核测试通过。

## 时序与资源
原生slow/fast全部组setup/hold WNS {values['SWNS']:+.3f}/{values['HWNS']:+.3f}ns，TNS0、违例端点0；fresh bitgen重新导入已审计路由库并通过STA。
LUT {before['lut']['used']}->{after['lut']['used']}，REG {before['reg']['used']}->{after['reg']['used']}，BRAM {after['bram']['used']}/64，DSP {after['dsp']['used']}/29；Slice {slices:.2f}%。不增加字库、帧缓存或放宽约束。
签核：{bit['parent_signoff']}；详细结果：doc/compile/seamless_marquee_delivery.json。旧封包、旧位流和V0.2冻结保留。

## 复现
```powershell
python sim/build_marquee_reference.py
python sim/build_event_reference.py
python sim/run_regression.py --sim modelsim --timeout 600
python prj/td/verify_patient_paths.py tb_named_pcm tb_patient_pcm_path
python sim/run_vendor_sdram.py --system --timeout 600
python sim/run_vendor_sdram.py --system --system-tb tb_v03_top_audio --timeout 300
python sim/run_vendor_sdram.py --system --system-tb tb_basic_calling --timeout 180
python prj/td/medq_td.py --name MedQv03 --mode synth --run --timeout 300
python prj/td/route_seed.py --parent-result <new-synth-result.json> --seed 23 --timeout 1800
python prj/td/signoff_timing.py --result <new-route-result.json> --bitgen
python sim/capture_v03.py --source <new-real-system-directory>
python sim/capture_seamless.py
python prj/td/finalize_seamless_release.py
python prj/td/package_seamless_release.py --timing
python prj/td/seal_timing_release.py
```
board_test: not_tested。没有执行实板下载或声学/电气验收。As of 2026-11-02。
'''
    (ROOT/'README.md').write_text(summary,encoding='utf-8')
    (ROOT/'doc/compile/v03_report.md').write_text(summary,encoding='utf-8')
    dump('doc/compile/v03_status.json',{'version':'0.3','revision':REVISION,'implementation':'complete',
        'simulation':'PASS','modelsim_tests':len(reg['results']),'additional_modelsim_tests':2,'sta':'PASS','bitstream':'PASS',
        'board_test':'not_tested','release_authority':'deliverables/latest_v03.json','bitstream_path':result['bitstream'],
        'bitstream_sha256':bit['bitstream_sha256'],'signoff':bit['parent_signoff']})
    handoff = ROOT/'HANDOFF.md'
    text = handoff.read_text(encoding='utf-8'); marker='\n\n## 13. 居中连续字幕'
    if marker in text:
        text=text[:text.index(marker)]
    handoff.write_text(text+marker+'（2026-11-02）\n\n'+summary,encoding='utf-8')
    hw=read('doc/hw/toolchain.json')
    hw['td'].update(timing_signoff=bit['parent_signoff'],bitstream_evidence=pointer['result'],
        physical_resource_status=after,implementation_status='native_routed_strict_signoff_PASS',bitstream_generated=True,
        license_status='PASS',license_evidence=signed['original_result'],full_top_analysis_evidence=signed['original_result'],
        gate_synthesis_evidence=parent.relative_to(ROOT).as_posix()+'/result.json')
    dump('doc/hw/toolchain.json',hw)
    print('SEAMLESS_MARQUEE_DELIVERY_PASS',len(reg['results']),'+2',values,delta,'board_test: not_tested')


if __name__ == '__main__':
    main()

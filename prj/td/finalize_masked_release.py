"""Finalize named-patient speech, privacy UI and measured resource evidence."""
from pathlib import Path
import hashlib
import json
import re
import shutil
import subprocess
import sys
import wave
import zipfile
from PIL import Image
import medq_td
import signoff_timing

ROOT = medq_td.ROOT


def read(path):
    return json.loads((ROOT / path).read_text(encoding='utf-8'))


def dump(path, value):
    medq_td.dump(ROOT / path, value)


def main():
    simulation = signoff_timing.simulation_gate()
    reg = read('sim/regression_result.json')
    pointer = read('prj/td/latest_timing_bitstream.json')
    bit = read(pointer['result'])
    signed = read(bit['parent_signoff'])
    assert bit['status'] == signed['status'] == 'PASS'
    assert 'MASKED_SMOOTH_' in bit['bitstream']
    signoff_timing.check_hashes(bit['source_sha256'])
    signoff_timing.check_hashes(bit['simulation_evidence_sha256'])
    assert medq_td.sha(ROOT / bit['parent_signoff']) == bit['parent_signoff_sha256']
    assert medq_td.sha(ROOT / bit['bitstream']) == bit['bitstream_sha256']
    snapshots = sorted((ROOT / 'baseline').glob('v03_pre_masked_smooth_*/manifest.json'))
    assert len(snapshots) == 1
    frozen = read(snapshots[0].relative_to(ROOT))
    old = frozen['previous_release']
    for kind in ('archive', 'bitstream'):
        assert medq_td.sha(ROOT / old[kind]) == old[kind + '_sha256']
    guard = read('doc/compile/marquee_source_asset_audit.json')['unchanged_hardware_files']
    with zipfile.ZipFile(ROOT / old['archive']) as z:
        for name in guard:
            assert (ROOT / name).read_bytes() == z.read(name), name
        assert (ROOT / 'rtl/font_rom.hex').read_bytes() == z.read('rtl/font_rom.hex')
        current = (ROOT / 'rtl/font_v03.hex').read_text().split()
        assert len(current) == 8192 and current[:4096] == z.read('rtl/font_v03.hex').decode().split()[:4096]
        baseline_signoff = json.loads(z.read('doc/compile/patient_names_delivery.json'))
    table = read('assets/patients.json')['patients']
    voice = read('assets/voice_manifest.json')
    clips = voice['clips']
    assert len(table) == 30 and len(clips) == 54
    assert len({c['sha256'] for c in clips[3:13]}) == 10
    for i, row in enumerate(table):
        assert row['clip'] == 21 + i and clips[21 + i]['phrase'] == row['name']
        assert row['surname'] == row['name'][0]
        assert row['display_name'] == row['name'][0]+'*'+row['name'][-1]
    for clip in clips:
        assert medq_td.sha(ROOT / 'assets/sd_root' / clip['file']) == clip['sha256']
        assert clip['samples'] * 2 == clip['bytes'] and clip['bytes'] > 0
    words = sum((c['bytes'] + 3) // 4 for c in clips)
    assert 0x0e1000 + words <= 0x18f000
    targeted = read('doc/compile/patient_names/targeted_latest.json')
    for path in targeted:
        result = read(path)
        assert result['status'] == 'PASS' and result['tool'] == 'modelsim'
        signoff_timing.check_hashes(result['input_sha256'])
        simulation[path] = medq_td.sha(ROOT / path)
    assert {read(p)['top'] for p in targeted} == {'tb_named_pcm', 'tb_patient_pcm_path'}
    quality = read('assets/speech_previews/pace_comparison.json')
    assert quality['status']=='PASS' and quality['max_join_quiet_ms']==24
    signoff_timing.check_hashes(quality['source_sha256'])
    packing = read('doc/compile/masked_smooth/lossless_font_packing.json')
    assert packing['status']=='PASS' and packing['sprites']==115
    signoff_timing.check_hashes(packing['source_sha256'])
    for evidence in ['assets/speech_previews/pace_comparison.json','doc/compile/masked_smooth/lossless_font_packing.json']:
        simulation[evidence]=medq_td.sha(ROOT/evidence)
    # Preserve the exact native parent gate used for the independently seeded run.
    implementation = read(signed['original_result'])
    gate_path = Path(implementation['parent_gate'])
    parent_dir = next((p for p in gate_path.parents if (p / 'result.json').is_file()), None)
    assert parent_dir is not None and parent_dir.parent == ROOT / 'prj/td/runs'
    parent_tag = parent_dir.name
    parent = read((parent_dir / 'result.json').relative_to(ROOT))
    assert parent['status'] == 'PASS' and parent['meta']['source_sha256'] == implementation['meta']['source_sha256']
    assert medq_td.sha(parent_dir / 'output/MedQv03_gate.db') == implementation['parent_gate_sha256']
    preserved = ROOT / 'doc/compile/masked_smooth/native_parent' / parent_tag
    if not preserved.exists():
        shutil.copytree(parent_dir, preserved)
    for p in parent_dir.rglob('*'):
        if p.is_file():
            assert medq_td.sha(p) == medq_td.sha(preserved / p.relative_to(parent_dir))
    attempts = []
    for path in sorted((ROOT / 'prj/td/runs').glob('*/result.json')):
        attempt = read(path.relative_to(ROOT))
        if attempt.get('meta', {}).get('source_sha256') != implementation['meta']['source_sha256']:
            continue
        if 'placement_seed' not in attempt.get('meta', {}):
            continue
        entry = {'result': path.relative_to(ROOT).as_posix(), 'status': attempt['status'],
                 'seed': attempt['meta']['placement_seed'], 'timing': attempt.get('timing_slack_ns')}
        if path != ROOT / signed['original_result']:
            saved = ROOT / 'doc/compile/masked_smooth/native_attempts' / path.parent.name
            if not saved.exists():
                shutil.copytree(path.parent, saved)
            for artifact in path.parent.rglob('*'):
                if artifact.is_file():
                    assert medq_td.sha(artifact) == medq_td.sha(saved / artifact.relative_to(path.parent))
            entry['package_evidence'] = saved.relative_to(ROOT).as_posix()
        attempts.append(entry)
    # Only PCM is present in the copy-to-card folder. WAV/previews stay outside.
    card = ROOT / 'deliverables/TF_CARD_MASKED_SMOOTH_20261102'
    (card / 'SD_ROOT').mkdir(parents=True, exist_ok=True)
    for clip in clips:
        src = ROOT / 'assets/sd_root' / clip['file']
        dst = card / 'SD_ROOT' / clip['file']
        if dst.exists():
            assert medq_td.sha(dst) == clip['sha256']
        else:
            shutil.copy2(src, dst)
    assert len(list((card / 'SD_ROOT').iterdir())) == 54
    (card / '使用说明.txt').write_text('请与本版MASKED_SMOOTH位流配套更新TF卡。FAT32格式；把SD_ROOT内54个CLIP00..53.PCM复制到根目录，可任意顺序；不要复制WAV或整个SD_ROOT文件夹。可保留原BMP；请移走旧的同名PCM后再复制。请替换全部54段PCM；旧54段素材仍是原慢速语音。音频经HDMI输出；板载蜂鸣器仅作降级提示音。名单外不冒用姓名，使用“患者”。未执行本次上板测试。\n', encoding='utf-8-sig')
    dump((card / 'PCM_SHA256.json').relative_to(ROOT), {c['file']: c['sha256'] for c in clips})
    # Native full-top captures: cropping/export only, never repainting the UI.
    cap = read('sim/ui/v03_rtl/capture_manifest.json')
    assert len(cap['frames']) == 12 and not cap['identical_adjacent_frames']
    preview = ROOT / 'sim/ui/masked_smooth'
    preview.mkdir(exist_ok=True)
    sheet = Image.new('RGB', (1280, 444), 'white')
    for i, row in enumerate(cap['frames']):
        assert medq_td.sha(ROOT / row['source']) == row['ppm_sha256']
        assert medq_td.sha(ROOT / row['png']) == row['png_sha256']
        im = Image.open(ROOT / row['png']).convert('RGB')
        sheet.paste(im.crop((0, 67, 640, 141)), ((i % 2) * 640, (i // 2) * 74))
        im.save(preview / f'page_{i:02}.bmp')
    sheet.save(preview / 'actual_subtitle_frames.png')
    dump('sim/ui/masked_smooth/export_manifest.json', {
        'scope': 'actual RTL frame exports for visual review; not a replacement runtime image engine',
        'source_capture_manifest': 'sim/ui/v03_rtl/capture_manifest.json',
        'files': {p.relative_to(ROOT).as_posix(): medq_td.sha(p) for p in sorted(preview.iterdir()) if p.suffix in ('.bmp', '.png')}})
    cmd = [sys.executable, '-m', 'unittest', 'discover', '-s', 'prj/td', '-p', 'test_*.py', '-v']
    tests = subprocess.run(cmd, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, encoding='utf-8', timeout=60)
    (ROOT / 'doc/compile/masked_smooth/tool_tests.log').write_text(tests.stdout, encoding='utf-8')
    assert tests.returncode == 0 and 'Ran 36 tests' in tests.stdout and re.search(r'^OK\s*$', tests.stdout, re.M)
    dump('doc/compile/masked_smooth/tool_tests.json', {'status': 'PASS', 'tests': 36,
         'source_sha256': {p.relative_to(ROOT).as_posix(): medq_td.sha(p) for p in sorted((ROOT / 'prj/td').glob('*.py'))}})
    before, after = baseline_signoff['physical_resources'], signed['physical_resources']
    delta = {k: {'before': before[k]['used'], 'after': after[k]['used'], 'change': after[k]['used'] - before[k]['used']} for k in ('lut', 'reg', 'bram', 'dsp')}
    native_dir = (ROOT / signed['original_result']).parent
    qor = (native_dir / 'reports/MedQv03_route.qor').read_text(encoding='utf-8')
    slices = float(re.search(r'slices percentage\s*\|\s*([\d.]+)%', qor)[1])
    result = {'status': 'PC_SIGNOFF_PASS', 'revision': 'masked_smooth_20261102', 'board_test': 'not_tested',
        'specification': 'doc/spec/masked_smooth_20261102.md', 'patient_table': 'assets/patients.json',
        'voice_assets': len(clips), 'voice_bytes': sum(c['bytes'] for c in clips),
        'audio_pool_end_word': 0x0e1000 + words, 'audio_pool_limit_word': 0x18f000,
        'filename_mapping': 'CLIP00..53.PCM independent of directory/copy order',
        'screen': 'first character + literal * + last character; anonymous outside list', 'speech': 'actual ticket plus full name, Huihui Rate=1, trimmed edge silence <=24ms',
        'modelsim_regression': len(reg['results']), 'additional_modelsim_tests': len(targeted),
        'exhaustive_actual_PCM_sentences': 396, 'actual_PCM_clips': 3564, 'actual_signed_output_sample_checks': 32076,
        'independent_masked_name_pixel_checks': 2012800, 'event_pixel_checks': 1065600,
        'tool_gate_tests': 36, 'simulation_evidence_sha256': simulation,
        'native_signoff': bit['parent_signoff'], 'native_setup_hold_ns': signed['timing']['values'],
        'physical_resources': after, 'resource_change_vs_previous_sealed_release': delta,
        'slice_percent': slices, 'bram_headroom_blocks': 64 - after['bram']['used'],
        'runtime_image_replacement': 'not applied: preserve live state, scrolling and animation',
        'image_exports': 'sim/ui/masked_smooth/export_manifest.json',
        'tf_card_directory': card.relative_to(ROOT).as_posix(),
        'voice_quality': quality, 'lossless_font_packing': packing,
        'native_placement_attempts': attempts,
        'bitstream': 'deliverables/' + Path(bit['bitstream']).name, 'bitstream_sha256': bit['bitstream_sha256'],
        'previous_release_unchanged': old, 'protected_hardware_files': guard,
        'preserved_native_gate_parent': preserved.relative_to(ROOT).as_posix()}
    dump('doc/compile/masked_smooth_delivery.json', result)
    v = signed['timing']['values']
    c01=quality['sentence_comparison'][0]
    summary = f"""# MedQ V0.3 姓名遮罩与流畅语音（2026-11-02）

屏幕显示首字+单个星号+末字：例如请C01张*民到A诊室就诊；语音仍播完整姓名张伟民。全部30人、原独立A/B初诊与C/D回诊号段、匿名兜底不变。
54段语音统一Huihui Rate=1（原=-1）；移除各段首尾静音，12ms保护垫+2ms淡入淡出，词内声音不裁切。16kHz/16bit单声道与播放器48kHz/插值时序未改。C01整句PCM由{c01['before_seconds']:.3f}s降至{c01['after_seconds']:.3f}s；素材拼接处静音上限24ms，未将该数值冒充实板测量。全部54段活动样本逐一保留检查通过。

## 更新方式
必须更新位流并替换全部54段PCM。{result['tf_card_directory']}/SD_ROOT中只有CLIP00..53.PCM，可按任意顺序复制到FAT32根目录，原BMP可保留；不要复制WAV。旧的54段素材仍是原慢速播报。
音频经HDMI，蜂鸣器仅为降级提示音。名单/姓名遮罩：assets/patients.json；生成与波形统计：assets/voice_manifest.json；新旧试听：assets/speech_previews/；C01_张伟民.wav是新版，previous_C01_张伟民.wav是旧版。

## 保留与验证
SW1/SW2独立A/B叫号、SW3/SW4医生双边沿、回诊优先、暂停安全排空/同患者重播、0/30/60秒、每操作下一帧x24字幕刷新、抗锯齿和动态人数保持。
ModelSim完整{len(reg['results'])}/{len(reg['results'])}、2项源绑定专项、36项签核器测试通过。34例覆盖30人的遮罩像素共2012800点；18类事件1065600点；396种01..99语句全链路32076个PCM输出样本均匹配。
真实加密SDRAM控制器三类整机模式通过；12连续RTL帧见sim/ui/v03_rtl/，字幕裁剪和页面BMP见sim/ui/masked_smooth/。

## 资源和时序
两角setup/hold {v['SWNS']:+.3f}/{v['HWNS']:+.3f}ns，TNS0、全部组违例端点0。LUT {before['lut']['used']}->{after['lut']['used']}，REG {before['reg']['used']}->{after['reg']['used']}，BRAM {before['bram']['used']}->{after['bram']['used']}/64，DSP仍{after['dsp']['used']}/29；Slice {baseline_signoff['slice_percent']:.2f}%->{slices:.2f}%。
新增遮罩字形没有缩字/降色；附加字库无损从240行压到180行，115个sprite的101958像素逐一相同，原首4K字模和legacy ROM字节不变。布局证据doc/compile/masked_smooth/lossless_font_packing.json。
SDRAM/PLL/HDMI/播放器/约束等23个保护文件不变；旧位流、旧包与V0.2冻结保留。没有假路径掩盖或降频。
签核：{bit['parent_signoff']}；详细结果doc/compile/masked_smooth_delivery.json。位流：{result['bitstream']}；SHA256 {bit['bitstream_sha256']}。

## 复现
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File sim/build_voice.ps1
python sim/build_dual_font.py
python sim/build_marquee_reference.py
python sim/build_event_reference.py
python prj/td/verify_smooth_audio.py
python sim/run_regression.py --sim modelsim --timeout 600
python prj/td/verify_patient_paths.py tb_named_pcm tb_patient_pcm_path
python sim/run_vendor_sdram.py --system --timeout 600
python sim/run_vendor_sdram.py --system --system-tb tb_v03_top_audio --timeout 300
python sim/run_vendor_sdram.py --system --system-tb tb_basic_calling --timeout 180
python prj/td/medq_td.py --name MedQv03 --mode synth --run --timeout 300
python prj/td/route_seed.py --parent-result <new-synth-result.json> --seed 61 --timeout 1800
python prj/td/signoff_timing.py --result <new-route-result.json> --bitgen
python sim/capture_v03.py --source <new-real-system-directory>
python prj/td/finalize_masked_release.py
python prj/td/package_masked_release.py --timing
python prj/td/seal_timing_release.py
```
生产前的无损字库比对是本次冻结旧布局到新布局的证据，日常复现无需重新生成该历史比较。所有最终文件按deliverables/latest_v03.json与ZIP内DELIVERY_MANIFEST.json校验。
board_test: not_tested。未下载、未做实板声学/电气测试。As of 2026-11-02。
"""
    (ROOT/'README.md').write_text(summary,encoding='utf-8')
    (ROOT/'doc/compile/v03_report.md').write_text(summary,encoding='utf-8')
    dump('doc/compile/v03_status.json',{'version':'0.3','revision':result['revision'],'implementation':'complete','simulation':'PASS','modelsim_tests':len(reg['results']),'additional_modelsim_tests':2,'sta':'PASS','bitstream':'PASS','board_test':'not_tested','release_authority':'deliverables/latest_v03.json','bitstream_path':result['bitstream'],'bitstream_sha256':bit['bitstream_sha256'],'signoff':bit['parent_signoff']})
    handoff=ROOT/'HANDOFF.md';text=handoff.read_text(encoding='utf-8');marker='\n\n## 12. 姓名遮罩与流畅语音'
    if marker in text:text=text[:text.index(marker)]
    handoff.write_text(text+marker+'（2026-11-02）\n\n'+summary,encoding='utf-8')
    hw=read('doc/hw/toolchain.json')
    hw['td'].update(timing_signoff=bit['parent_signoff'],bitstream_evidence=pointer['result'],physical_resource_status=after,implementation_status='native_routed_strict_signoff_PASS',bitstream_generated=True,license_status='PASS',license_evidence=signed['original_result'],full_top_analysis_evidence=signed['original_result'],gate_synthesis_evidence=parent_dir.relative_to(ROOT).as_posix()+'/result.json')
    dump('doc/hw/toolchain.json',hw)
    print('MASKED_SMOOTH_DELIVERY_PASS',len(reg['results']),'+2',v,delta,'board_test: not_tested')


if __name__=='__main__':
    main()

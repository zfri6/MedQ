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
    assert 'PATIENT_NAMES_' in bit['bitstream']
    signoff_timing.check_hashes(bit['source_sha256'])
    signoff_timing.check_hashes(bit['simulation_evidence_sha256'])
    assert medq_td.sha(ROOT / bit['parent_signoff']) == bit['parent_signoff_sha256']
    assert medq_td.sha(ROOT / bit['bitstream']) == bit['bitstream_sha256']
    snapshots = sorted((ROOT / 'baseline').glob('v03_pre_patient_names_*/manifest.json'))
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
        for i in range(21):
            name = f'assets/sd_root/CLIP{i:02}.PCM'
            assert (ROOT / name).read_bytes() == z.read(name)
        baseline_signoff = json.loads(z.read('doc/compile/marquee_events_delivery.json'))
    table = read('assets/patients.json')['patients']
    voice = read('assets/voice_manifest.json')
    clips = voice['clips']
    assert len(table) == 30 and len(clips) == 54
    assert len({c['sha256'] for c in clips[3:13]}) == 10
    for i, row in enumerate(table):
        assert row['clip'] == 21 + i and clips[21 + i]['phrase'] == row['name']
        assert row['surname'] == row['name'][0]
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
    # Preserve the exact native parent gate used for the independently seeded run.
    implementation = read(signed['original_result'])
    gate_path = Path(implementation['parent_gate'])
    parent_dir = next((p for p in gate_path.parents if (p / 'result.json').is_file()), None)
    assert parent_dir is not None and parent_dir.parent == ROOT / 'prj/td/runs'
    parent_tag = parent_dir.name
    parent = read((parent_dir / 'result.json').relative_to(ROOT))
    assert parent['status'] == 'PASS' and parent['meta']['source_sha256'] == implementation['meta']['source_sha256']
    assert medq_td.sha(parent_dir / 'output/MedQv03_gate.db') == implementation['parent_gate_sha256']
    preserved = ROOT / 'doc/compile/patient_names/native_parent' / parent_tag
    if not preserved.exists():
        shutil.copytree(parent_dir, preserved)
    for p in parent_dir.rglob('*'):
        if p.is_file():
            assert medq_td.sha(p) == medq_td.sha(preserved / p.relative_to(parent_dir))
    # Only PCM is present in the copy-to-card folder. WAV/previews stay outside.
    card = ROOT / 'deliverables/TF_CARD_PATIENT_NAMES_20261102'
    (card / 'SD_ROOT').mkdir(parents=True, exist_ok=True)
    for clip in clips:
        src = ROOT / 'assets/sd_root' / clip['file']
        dst = card / 'SD_ROOT' / clip['file']
        if dst.exists():
            assert medq_td.sha(dst) == clip['sha256']
        else:
            shutil.copy2(src, dst)
    assert len(list((card / 'SD_ROOT').iterdir())) == 54
    (card / '使用说明.txt').write_text('请与本版PATIENT_NAMES位流配套更新TF卡。FAT32格式；把SD_ROOT内54个CLIP00..53.PCM复制到根目录，可任意顺序；不要复制WAV或整个SD_ROOT文件夹。可保留原BMP；请移走旧的同名PCM后再复制。旧21段卡会降级为提示音，不能播报名单姓名。音频经HDMI输出；板载蜂鸣器仅作降级提示音。名单外不冒用姓名，使用“患者”。未执行本次上板测试。\n', encoding='utf-8-sig')
    dump((card / 'PCM_SHA256.json').relative_to(ROOT), {c['file']: c['sha256'] for c in clips})
    # Native full-top captures: cropping/export only, never repainting the UI.
    cap = read('sim/ui/v03_rtl/capture_manifest.json')
    assert len(cap['frames']) == 12 and not cap['identical_adjacent_frames']
    preview = ROOT / 'sim/ui/patient_names'
    preview.mkdir(exist_ok=True)
    sheet = Image.new('RGB', (1280, 444), 'white')
    for i, row in enumerate(cap['frames']):
        assert medq_td.sha(ROOT / row['source']) == row['ppm_sha256']
        assert medq_td.sha(ROOT / row['png']) == row['png_sha256']
        im = Image.open(ROOT / row['png']).convert('RGB')
        sheet.paste(im.crop((0, 67, 640, 141)), ((i % 2) * 640, (i // 2) * 74))
        im.save(preview / f'page_{i:02}.bmp')
    sheet.save(preview / 'actual_subtitle_frames.png')
    dump('sim/ui/patient_names/export_manifest.json', {
        'scope': 'actual RTL frame exports for visual review; not a replacement runtime image engine',
        'source_capture_manifest': 'sim/ui/v03_rtl/capture_manifest.json',
        'files': {p.relative_to(ROOT).as_posix(): medq_td.sha(p) for p in sorted(preview.iterdir()) if p.suffix in ('.bmp', '.png')}})
    cmd = [sys.executable, '-m', 'unittest', 'discover', '-s', 'prj/td', '-p', 'test_*.py', '-v']
    tests = subprocess.run(cmd, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, encoding='utf-8', timeout=60)
    (ROOT / 'doc/compile/patient_names/tool_tests.log').write_text(tests.stdout, encoding='utf-8')
    assert tests.returncode == 0 and 'Ran 36 tests' in tests.stdout and re.search(r'^OK\s*$', tests.stdout, re.M)
    dump('doc/compile/patient_names/tool_tests.json', {'status': 'PASS', 'tests': 36,
         'source_sha256': {p.relative_to(ROOT).as_posix(): medq_td.sha(p) for p in sorted((ROOT / 'prj/td').glob('*.py'))}})
    before, after = baseline_signoff['physical_resources'], signed['physical_resources']
    delta = {k: {'before': before[k]['used'], 'after': after[k]['used'], 'change': after[k]['used'] - before[k]['used']} for k in ('lut', 'reg', 'bram', 'dsp')}
    native_dir = (ROOT / signed['original_result']).parent
    qor = (native_dir / 'reports/MedQv03_route.qor').read_text(encoding='utf-8')
    slices = float(re.search(r'slices percentage\s*\|\s*([\d.]+)%', qor)[1])
    result = {'status': 'PC_SIGNOFF_PASS', 'revision': 'patient_names_20261102', 'board_test': 'not_tested',
        'specification': 'doc/spec/patient_names_20261102.md', 'patient_table': 'assets/patients.json',
        'voice_assets': len(clips), 'voice_bytes': sum(c['bytes'] for c in clips),
        'audio_pool_end_word': 0x0e1000 + words, 'audio_pool_limit_word': 0x18f000,
        'filename_mapping': 'CLIP00..53.PCM independent of directory/copy order',
        'screen': 'surname only; anonymous outside list', 'speech': 'actual ticket plus full name; anonymous outside list',
        'modelsim_regression': len(reg['results']), 'additional_modelsim_tests': len(targeted),
        'exhaustive_actual_PCM_sentences': 396, 'actual_PCM_clips': 3564, 'actual_signed_output_sample_checks': 32076,
        'independent_surname_pixel_checks': 2012800, 'event_pixel_checks': 1065600,
        'tool_gate_tests': 36, 'simulation_evidence_sha256': simulation,
        'native_signoff': bit['parent_signoff'], 'native_setup_hold_ns': signed['timing']['values'],
        'physical_resources': after, 'resource_change_vs_previous_sealed_release': delta,
        'slice_percent': slices, 'bram_headroom_blocks': 64 - after['bram']['used'],
        'runtime_image_replacement': 'not applied: preserve live state, scrolling and animation',
        'image_exports': 'sim/ui/patient_names/export_manifest.json',
        'tf_card_directory': card.relative_to(ROOT).as_posix(),
        'bitstream': 'deliverables/' + Path(bit['bitstream']).name, 'bitstream_sha256': bit['bitstream_sha256'],
        'previous_release_unchanged': old, 'protected_hardware_files': guard,
        'preserved_native_gate_parent': preserved.relative_to(ROOT).as_posix()}
    dump('doc/compile/patient_names_delivery.json', result)
    v = signed['timing']['values']
    summary = f'''# MedQ V0.3 全名语音与姓氏显示（2026-11-02）

电脑端签核通过；未上板。ModelSim完整{len(reg['results'])}/{len(reg['results'])}，另有2项源绑定专项仿真及36项签核器测试。
全部30名患者按assets/patients.json映射；保留A/B初诊、C/D回诊的独立01..99号。C01=张伟民、A01=赵敏华、D01=马宁远、B01=杨帆宇；名单外为“患者”。
语音播完整姓名与当前实际号码；屏幕仅显示姓氏，例如“请C01张到A诊室就诊”。396种01..99呼叫的3564片段、32076个实际PCM输出样本比对通过；30个姓氏的2012800个像素比对通过。
原语音按FAT目录出现顺序索引，复制顺序会错配。新版本按CLIPnn.PCM精确定位，已验证逆序、多根簇、缺失、未知、重复ID；未读取用户实卡，不能断言旧板固定数字的唯一原因。
54段PCM总计{result['voice_bytes']}字节，原21段字节不变；新增30个姓名与号/到/患者。必须与新位流配套更新卡。音频经HDMI；蜂鸣器仍仅有限降级提示音。

## 操作与素材
K1/K2/K3/K4分别A初诊/B初诊/A回诊/B回诊；SW1/SW2低有效允许A/B叫号，SW3/SW4医生双边沿到位/离开。队列、严格回诊优先、三次叫号、暂停计时/安全排空、恢复同患者重播、两条事件字幕下一帧x24刷新均保留。无卡/素材不全降级；旧21段卡不播全名。
把{result['tf_card_directory']}/SD_ROOT内54个PCM复制到FAT32卡根目录，顺序任意；不要复制WAV。已有BMP可保留。首次加载时间增加；服务准备超时后的提示音模式不阻止后台继续加载，完成后恢复语音模式。
患者名单：assets/patients.json；完整素材校验：assets/voice_manifest.json；实音拼接试听：assets/speech_previews/。

## 资源与图片方案
相对前一封包：LUT {before['lut']['used']} -> {after['lut']['used']}，REG {before['reg']['used']} -> {after['reg']['used']}，BRAM {before['bram']['used']} -> {after['bram']['used']}/64，DSP仍{after['dsp']['used']}/29；Slice {baseline_signoff['slice_percent']:.2f}% -> {slices:.2f}%。
节省来自PCM元数据改为同步无复位RAM+有效位图，增加名单后仍减少LUT/寄存器；这是以BRAM换逻辑，BRAM余量为0块，不能称为所有资源都下降。
整页640x480 RGB888文件921600字节；现有SDRAM实际32bit/像素每页1228800字节，每秒约73.14MB读流量（59.5238fps）。现有显示读取已存在，换静态底图不必重复读取，但动态姓名、计数、提示、动画仍需OSD/状态逻辑，且整页状态枚举不能代替实时字幕。新TF卡语音已接近音频专用区容量，不可混占该地址区。
本版保留实时页面，未把动态功能固化为图片。另导出12张实际RTL页面BMP与字幕裁剪图供审阅：sim/ui/patient_names/；这些图片未被伪装成新的硬件渲染证据。后续静态底图合入需像素等价、显示/PCM带宽、输入切换和STA重新闭环。

## 构建验证
最终slow/fast setup/hold {v['SWNS']:+.3f}/{v['HWNS']:+.3f} ns，TNS0、所有路径组违例端点0；SDRAM/PLL/HDMI/约束及播放器等23个保护文件字节不变。未添加全局false path/内部多周期或降频。
签核：{bit['parent_signoff']}；全证据：doc/compile/patient_names_delivery.json；原包和V0.2保留。
位流：{result['bitstream']}；SHA256 {bit['bitstream_sha256']}。当前封包以deliverables/latest_v03.json为准。

```powershell
python sim/run_regression.py --sim modelsim --timeout 600
python prj/td/verify_patient_paths.py tb_named_pcm tb_patient_pcm_path
python sim/run_vendor_sdram.py --system --timeout 600
python sim/run_vendor_sdram.py --system --system-tb tb_v03_top_audio --timeout 300
python sim/run_vendor_sdram.py --system --system-tb tb_basic_calling --timeout 180
python prj/td/medq_td.py --name MedQv03 --mode synth --run --timeout 300
python prj/td/route_seed.py --parent-result <new-synth-result.json> --seed 61 --timeout 1800
python prj/td/signoff_timing.py --result <new-route-result.json> --bitgen
python sim/capture_v03.py --source <new-real-system-directory>
python prj/td/finalize_patient_release.py
python prj/td/package_patient_release.py --timing
python prj/td/seal_timing_release.py
```

board_test: not_tested。未下载、未验证用户实卡或实板音频。已知原先无热插拔/持久化/第二HDMI等限制保留。As of 2026-11-02。
'''
    (ROOT / 'README.md').write_text(summary, encoding='utf-8')
    (ROOT / 'doc/compile/v03_report.md').write_text(summary, encoding='utf-8')
    dump('doc/compile/v03_status.json', {'version': '0.3', 'revision': result['revision'], 'implementation': 'complete',
        'simulation': 'PASS', 'modelsim_tests': len(reg['results']), 'additional_modelsim_tests': 2,
        'sta': 'PASS', 'bitstream': 'PASS', 'board_test': 'not_tested',
        'release_authority': 'deliverables/latest_v03.json', 'bitstream_path': result['bitstream'],
        'bitstream_sha256': bit['bitstream_sha256'], 'signoff': bit['parent_signoff']})
    handoff = ROOT / 'HANDOFF.md'
    text = handoff.read_text(encoding='utf-8')
    marker = '\n\n## 11. 全名语音与姓氏显示'
    if marker in text:
        text = text[:text.index(marker)]
    handoff.write_text(text + '\n\n## 11. 全名语音与姓氏显示（2026-11-02）\n\n' + summary, encoding='utf-8')
    hw = read('doc/hw/toolchain.json')
    hw['td'].update(timing_signoff=bit['parent_signoff'], bitstream_evidence=pointer['result'],
        physical_resource_status=after, implementation_status='native_routed_strict_signoff_PASS',
        bitstream_generated=True, license_status='PASS', license_evidence=signed['original_result'],
        full_top_analysis_evidence=signed['original_result'], gate_synthesis_evidence=parent_dir.relative_to(ROOT).as_posix() + '/result.json')
    dump('doc/hw/toolchain.json', hw)
    print('PATIENT_NAMES_DELIVERY_PASS', len(reg['results']), '+2', v, delta, 'board_test: not_tested')


if __name__ == '__main__':
    main()

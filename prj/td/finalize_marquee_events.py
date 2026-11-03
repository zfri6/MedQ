"""Finalize the event-subtitle revision using current native/simulation evidence."""
import hashlib
import json
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path
import medq_td
import signoff_timing

ROOT = medq_td.ROOT


def read(path):
    return json.loads((ROOT / path).read_text(encoding='utf-8'))


def dump(path, value):
    (ROOT / path).write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')


def main():
    evidence = signoff_timing.simulation_gate()
    ptr = read('prj/td/latest_timing_bitstream.json')
    bit = read(ptr['result'])
    signed = read(bit['parent_signoff'])
    assert bit['status'] == signed['status'] == 'PASS'
    signoff_timing.check_hashes(bit['source_sha256'])
    signoff_timing.check_hashes(bit['simulation_evidence_sha256'])
    reg = read('sim/regression_result.json')
    implementation = read(signed['original_result'])
    routing_parent = None
    if implementation.get('parent_gate_sha256'):
        tag = Path(implementation['parent_gate']).parents[3].name
        parent_dir = ROOT / 'prj/td/runs' / tag
        parent = read((parent_dir / 'result.json').relative_to(ROOT))
        assert parent['meta']['source_sha256'] == implementation['meta']['source_sha256']
        assert medq_td.sha(parent_dir / 'output/MedQv03_gate.db') == implementation['parent_gate_sha256']
        copy = ROOT / 'doc/compile/marquee_routing_parent' / tag
        if not copy.exists():
            shutil.copytree(parent_dir, copy)
        for path in parent_dir.rglob('*'):
            if path.is_file():
                assert medq_td.sha(path) == medq_td.sha(copy / path.relative_to(parent_dir))
        routing_parent = {'original_result': (parent_dir / 'result.json').relative_to(ROOT).as_posix(),
                          'preserved_package_copy': copy.relative_to(ROOT).as_posix(),
                          'original_status': parent['status'], 'placement_seed': implementation['meta']['placement_seed'],
                          'unchanged_gate_sha256': implementation['parent_gate_sha256']}
    audit = read('doc/compile/marquee_source_asset_audit.json')
    assert audit['status'] == 'PASS'
    old = audit['previous_release']
    for key in ('archive', 'bitstream'):
        assert medq_td.sha(ROOT / old[key]) == old[key + '_sha256']
    with zipfile.ZipFile(ROOT / old['archive']) as z:
        for name in audit['unchanged_hardware_files']:
            assert medq_td.sha(ROOT / name) == hashlib.sha256(z.read(name)).hexdigest()
        assert (ROOT / 'rtl/font_rom.hex').read_bytes() == z.read('rtl/font_rom.hex')
        compact = (ROOT / 'rtl/font_v03.hex').read_text().split()
        assert len(compact) == 8192 and compact[:4096] == z.read('rtl/font_v03.hex').decode().split()
    cap = read('sim/ui/v03_rtl/capture_manifest.json')
    assert len(cap['frames']) == 12 and not cap['identical_adjacent_frames']
    for row in cap['frames']:
        assert medq_td.sha(ROOT / row['source']) == row['ppm_sha256']
        assert medq_td.sha(ROOT / row['png']) == row['png_sha256']
    command = [sys.executable, '-m', 'unittest', 'discover', '-s', 'prj/td', '-p', 'test_*.py', '-v']
    tests = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           encoding='utf-8', errors='replace', timeout=60)
    (ROOT / 'doc/compile/marquee_tool_tests.log').write_text(tests.stdout, encoding='utf-8')
    assert tests.returncode == 0 and 'Ran 36 tests' in tests.stdout and re.search(r'^OK\s*$', tests.stdout, re.M)
    dump('doc/compile/marquee_tool_test_result.json', {
        'status': 'PASS', 'tests': 36, 'command': command,
        'tool_source_sha256': {p.relative_to(ROOT).as_posix(): medq_td.sha(p)
                               for p in sorted((ROOT / 'prj/td').glob('*.py'))}})
    native = (ROOT / signed['original_result']).parent
    qor = (native / 'reports/MedQv03_route.qor').read_text(encoding='utf-8')
    utilization = float(re.search(r'slices percentage\s*\|\s*([\d.]+)%', qor)[1])
    result = {
        'status': 'PC_SIGNOFF_PASS', 'revision': 'marquee_events_20261101',
        'specification': 'doc/spec/marquee_events_20261101.md',
        'operation_kinds': {'1': 'normal enqueue', '2': 'return enqueue', '3': 'call/recall/replay admitted',
                            '4': 'arrival', '5': 'departure', '6': 'pause', '7': 'enable', '8': 'missed', '9': 'rejected'},
        'display_policy': 'latest per-room operation at next atomic frame; independent left reset and phase',
        'left_start_pixel': 24, 'scroll_home': 592, 'scroll_pixels_per_two_frames': 1,
        'same_value_transient_events_and_frame_edge_commit': 'PASS',
        'old_patient_preserved_on_departure_and_missed': 'PASS',
        'cross_room_caption_isolation': 'PASS', 'fresh_left_text_unfaded': 'PASS',
        'modelsim_tests': len(reg['results']), 'tool_gate_tests': 36,
        'independent_event_pixel_checks': 1065600, 'independent_calling_pixel_checks': 236800,
        'message_examples': read('sim/ui/event_reference.json')['cases'],
        'unchanged_original_font_sprites': 75, 'new_AA_sprites': 8, 'production_ROM_words': 8192,
        'unchanged_PCM_clips': 21, 'real_system_frames': 12, 'distinct_frames': 12,
        'simulation_evidence_sha256': evidence, 'native_signoff': bit['parent_signoff'],
        'native_setup_hold_ns': signed['timing']['values'], 'physical_resources': signed['physical_resources'],
        'slice_percent': utilization, 'route_qor_stage_audit': signed['route_qor_audit'],
        'routing_parent_provenance': routing_parent,
        'bitstream': 'deliverables/' + Path(bit['bitstream']).name,
        'bitstream_sha256': bit['bitstream_sha256'], 'fresh_bitgen_STA': 'PASS',
        'previous_package_and_bit_unchanged': True, 'release_authority': 'deliverables/latest_v03.json',
        'board_test': 'not_tested'}
    dump('doc/compile/marquee_events_delivery.json', result)
    hw = read('doc/hw/toolchain.json')
    hw['td'].update(timing_signoff=bit['parent_signoff'], bitstream_evidence=ptr['result'],
                    physical_resource_status=signed['physical_resources'],
                    implementation_status='native_routed_strict_signoff_PASS',
                    bitstream_generated=True, license_status='PASS', license_evidence=signed['original_result'],
                    full_top_analysis_evidence=signed['original_result'], gate_synthesis_evidence=signed['original_result'])
    dump('doc/hw/toolchain.json', hw)
    v = signed['timing']['values']
    note = f'''

## 10. 事件字幕最终交付（2026-11-01）

用户确认每次操作显示对应提示。A/B独立字幕在下一帧从x24显示，分别重置滚动相位；
取号、回诊取号、拒绝、启停、叫号/重呼/实际恢复开播、到位、离开、过号均有对应内容。
同室帧间多事件显示最新操作，另一室不重置；离开/过号保留原患者号，三个星号为姓名。
原75个sprite与完整legacy字体字节不变，8个新增AA sprite使用第二页；生产ROM8192字。
开关映射、队列和21段语音素材保持前版。

ModelSim {len(reg['results'])}/{len(reg['results'])}、Verilog-2001、真实SDRAM三种整机模式、36项签核工具测试通过。
原生slow/fast setup/hold {v['SWNS']:+.3f}/{v['HWNS']:+.3f} ns，TNS0、全部组违例端点0。
位流：{result['bitstream']}；SHA256 {bit['bitstream_sha256']}。
签核：{bit['parent_signoff']}；当前详细结果：doc/compile/marquee_events_delivery.json。
封包以deliverables/latest_v03.json为准。board_test: not_tested。
'''
    path = ROOT / 'HANDOFF.md'
    text = path.read_text(encoding='utf-8')
    marker = '\n\n## 10. 事件字幕最终交付'
    if marker in text:
        text = text[:text.index(marker)]
    path.write_text(text + note, encoding='utf-8')
    (ROOT / 'doc/compile/marquee_events_integration.md').write_text(note + '\n完整需求、同拍优先级和QSTATE描述见doc/spec/marquee_events_20261101.md。字形/素材/硬件保护见marquee_source_asset_audit.json。原单色/历史暂停约定以本次明确修订为准；底层HDMI/SDRAM/PCM/PLL/约束未修改。\n', encoding='utf-8')
    print('MARQUEE_EVENTS_DELIVERY_PASS', len(reg['results']), v, 'board_test: not_tested')


if __name__ == '__main__':
    main()

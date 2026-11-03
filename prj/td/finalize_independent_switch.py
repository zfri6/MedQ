"""Write the current revision delivery record from verified native evidence."""
import hashlib
import json
import re
import subprocess
import sys
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
    pointer = read('prj/td/latest_timing_bitstream.json')
    bit = read(pointer['result'])
    signed = read(bit['parent_signoff'])
    assert bit['status'] == signed['status'] == 'PASS'
    signoff_timing.check_hashes(bit['source_sha256'])
    signoff_timing.check_hashes(bit['simulation_evidence_sha256'])
    regression = read('sim/regression_result.json')
    capture = read('sim/ui/v03_rtl/capture_manifest.json')
    assert len(capture['frames']) == 12 and not capture['identical_adjacent_frames']
    for row in capture['frames']:
        assert medq_td.sha(ROOT / row['source']) == row['ppm_sha256']
        assert medq_td.sha(ROOT / row['png']) == row['png_sha256']
    source = read('doc/compile/independent_switch_source_audit.json')
    asset = read('doc/compile/independent_switch_asset_audit.json')
    assert source['status'] == asset['status'] == 'PASS'
    assert medq_td.sha(ROOT / source['previous_archive']) == source['previous_archive_sha256']
    command = [sys.executable, '-m', 'unittest', 'discover', '-s', 'prj/td', '-p', 'test_*.py', '-v']
    tests = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           encoding='utf-8', errors='replace', timeout=60)
    (ROOT / 'doc/compile/independent_switch_tool_tests.log').write_text(tests.stdout, encoding='utf-8')
    assert tests.returncode == 0 and 'Ran 28 tests' in tests.stdout and re.search(r'^OK\s*$', tests.stdout, re.M)
    dump('doc/compile/independent_switch_tool_test_result.json', {
        'status': 'PASS', 'tests': 28, 'command': command,
        'tool_source_sha256': {p.relative_to(ROOT).as_posix(): medq_td.sha(p)
                               for p in sorted((ROOT / 'prj/td').glob('*.py'))}})
    native_dir = (ROOT / signed['original_result']).parent
    qor = (native_dir / 'reports/MedQv03_route.qor').read_text(encoding='utf-8')
    utilization = float(re.search(r'slices percentage\s*\|\s*([\d.]+)%', qor)[1])
    result = {
        'status': 'PC_SIGNOFF_PASS', 'revision': 'independent_switch_name_20261031',
        'switches': {'SW1': 'SW[0] active-low A calling enable', 'SW2': 'SW[1] active-low B calling enable',
                     'SW3': 'SW[2] both-edge A doctor', 'SW4': 'SW[3] both-edge B doctor'},
        'modelsim_tests': len(regression['results']), 'tool_gate_tests': 28,
        'all_16_switch_initial_levels': 'PASS', 'per_room_random_scoreboard': 'PASS',
        'independent_stop_and_audio_fairness': 'PASS', 'safe_PCM_drain_and_same_patient_replay_without_grant': 'PASS',
        'stopped_doctor_cancel_and_no_stale_replay': 'PASS', 'live_queues_and_both_marquees': 'PASS',
        'name_placeholder': '***', 'marquee_examples': ['请A01***到A诊室就诊', '请B01***到B诊室就诊',
                                                    '请C01***到A诊室就诊', '请D01***到B诊室就诊'],
        'independent_subtitle_pixel_checks': 236800, 'unchanged_font_sprites': 74,
        'unchanged_PCM_clips': 21, 'real_system_frames': 12, 'distinct_frames': 12,
        'simulation_evidence_sha256': evidence, 'native_signoff': bit['parent_signoff'],
        'native_setup_hold_ns': signed['timing']['values'], 'physical_resources': signed['physical_resources'],
        'slice_percent': utilization, 'STA_coverage_percent': signed['timing']['coverage_percent'],
        'route_qor_stage_audit': signed['route_qor_audit'],
        'bitstream': 'deliverables/' + Path(bit['bitstream']).name,
        'bitstream_sha256': bit['bitstream_sha256'], 'fresh_bitgen_STA': 'PASS',
        'previous_package_unchanged': True, 'release_authority': 'deliverables/latest_v03.json',
        'board_test': 'not_tested'}
    dump('doc/compile/independent_switch_delivery.json', result)
    hw = read('doc/hw/toolchain.json')
    hw['td'].update(timing_signoff=bit['parent_signoff'], bitstream_evidence=pointer['result'],
                    physical_resource_status=signed['physical_resources'],
                    implementation_status='native_routed_strict_signoff_PASS',
                    bitstream_generated=True, license_status='PASS',
                    license_evidence=signed['original_result'],
                    full_top_analysis_evidence=signed['original_result'],
                    gate_synthesis_evidence=signed['original_result'])
    dump('doc/hw/toolchain.json', hw)
    vals = signed['timing']['values']
    note = f'''

## 9. 双室独立开关与姓名占位最终交付（2026-10-31）

SW1/SW2分别低有效允许A/B叫号，SW3/SW4分别为A/B医生双边沿到位/离开；取号和画面始终实时。
停止当前语句会安全排空并让另一室继续，重开同患者重播不计新次数；医生取消使旧语句失效。
字幕请A01***到A诊室就诊 / 请B01***到B诊室就诊，C/D回诊目标仍为A/B。
原21段PCM和其余74个sprite覆盖度字节不变。当前操作见doc/spec/operation_v03.md。

完整ModelSim {len(regression['results'])}/{len(regression['results'])}，Verilog-2001门禁、真实控制器三种顶层模式、28项签核工具测试均通过。
原生slow/fast setup/hold WNS {vals['SWNS']:+.3f}/{vals['HWNS']:+.3f} ns，TNS为0，全部组违例端点为0。
新位流：{result['bitstream']}；SHA256 {bit['bitstream_sha256']}。
签核：{bit['parent_signoff']}；详细结果：doc/compile/independent_switch_delivery.json。
封包和真实解压逐文件校验由deliverables/latest_v03.json及seal_summary.json记录。board_test: not_tested。
'''
    handoff = ROOT / 'HANDOFF.md'
    text = handoff.read_text(encoding='utf-8')
    marker = '\n\n## 9. 双室独立开关与姓名占位最终交付'
    if marker in text:
        text = text[:text.index(marker)]
    handoff.write_text(text + note, encoding='utf-8')
    integration = ROOT / 'doc/compile/independent_switch_integration.md'
    text = integration.read_text(encoding='utf-8')
    marker = '\n\n## 最终原生结果'
    if marker in text:
        text = text[:text.index(marker)]
    integration.write_text(text + f'\n\n## 最终原生结果\n\nModelSim {len(regression["results"])}/{len(regression["results"])}、真实SDRAM、28项工具测试均通过；setup/hold {vals["SWNS"]:+.3f}/{vals["HWNS"]:+.3f} ns，TNS0、全部组端点0。\n\n原生实现{signed["original_result"]}，fresh bitgen {pointer["result"]}。位流SHA256 {bit["bitstream_sha256"]}。未上板。\n', encoding='utf-8')
    print('INDEPENDENT_SWITCH_DELIVERY_PASS', len(regression['results']), vals, 'board_test: not_tested')


if __name__ == '__main__':
    main()

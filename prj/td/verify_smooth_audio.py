"""Verify speech boundaries, preserved active samples and before/after pace."""
from pathlib import Path
from array import array
import hashlib
import json
import shutil
import wave
import medq_td

ROOT = medq_td.ROOT


def main():
    snapshot, = (ROOT / 'baseline').glob('v03_pre_masked_smooth_*')
    frozen = json.loads((snapshot / 'manifest.json').read_text(encoding='utf-8'))
    for name in ['assets/voice_manifest.json', 'assets/speech_previews/C01_张伟民.wav']:
        assert medq_td.sha(snapshot / name) == frozen['files'][name]
    old = json.loads((snapshot / 'assets/voice_manifest.json').read_text(encoding='utf-8'))
    new = json.loads((ROOT / 'assets/voice_manifest.json').read_text(encoding='utf-8'))
    rows = json.loads((ROOT / 'assets/patients.json').read_text(encoding='utf-8'))['patients']
    assert new['tts_rate'] == 1 and new['prior_tts_rate'] == -1
    files = [Path(__file__), ROOT / 'sim/build_voice.ps1', ROOT / 'sim/voice_manifest.py',
             ROOT / 'assets/voice_manifest.json', ROOT / 'assets/patients.json']
    checks = []
    for clip in new['clips']:
        p = ROOT / 'assets/sd_root' / clip['file']
        samples = array('h', p.read_bytes())
        with wave.open(str(p.with_suffix('.wav')), 'rb') as w:
            assert (w.getnchannels(), w.getsampwidth(), w.getframerate()) == (1, 2, 16000)
            raw = array('h', w.readframes(w.getnframes()))
        active = [i for i, v in enumerate(raw) if abs(v) > 32]
        start, end = max(0, active[0]-192), min(len(raw), active[-1]+193)
        assert samples[0] == samples[-1] == 0 and len(samples) == end-start
        assert samples[32:-32] == raw[start+32:end-32]
        assert [v for v in samples if abs(v) > 32] == [v for v in raw if abs(v) > 32]
        assert clip['leading_quiet_ms'] <= 12 and clip['trailing_quiet_ms'] <= 12
        assert medq_td.sha(p) == clip['sha256']
        files.extend([p, p.with_suffix('.wav')])
        checks.append({'id': clip['id'], 'active_samples_preserved': True, 'zero_ends': True})
    assert len(checks) == 54 and len({c['sha256'] for c in new['clips'][3:13]}) == 10
    comparisons = []
    for row in rows:
        ticket, n = row['ticket'], int(row['ticket'][1:])
        ids = [1, {'A':2, 'B':17, 'C':19, 'D':20}[ticket[0]], 3+n//10, 3+n%10,
               51, row['clip'], 52, 14 if row['room']=='A' else 15, 18]
        before = sum(old['clips'][i]['samples'] for i in ids)/16000
        after = sum(new['clips'][i]['samples'] for i in ids)/16000
        assert 0 < after < before
        assert row['display_name'] == row['name'][0]+'*'+row['name'][-1]
        comparisons.append({'ticket': ticket, 'name': row['name'], 'display_name': row['display_name'],
                            'before_seconds': before, 'after_seconds': after,
                            'reduction_percent': 100*(1-after/before), 'clips': ids})
    preview = ROOT / 'assets/speech_previews'
    shutil.copy2(snapshot / 'assets/speech_previews/C01_张伟民.wav', preview / 'previous_C01_张伟民.wav')
    result = {'status': 'PASS', 'revision': 'masked_smooth_20261102',
              'clips': checks, 'sentence_comparison': comparisons, 'max_join_quiet_ms': 24,
              'source_sha256': {p.relative_to(ROOT).as_posix(): medq_td.sha(p) for p in files},
              'board_test': 'not_tested', 'scope': 'PCM waveform/assembly verification; not recorded hardware audio'}
    medq_td.dump(preview / 'pace_comparison.json', result)
    print('SMOOTH_AUDIO_PASS', len(checks), 'clips,', len(comparisons), 'sentences, edge silence <=24ms')
    print('C01 seconds', comparisons[0]['before_seconds'], '->', comparisons[0]['after_seconds'])


if __name__ == '__main__':
    main()

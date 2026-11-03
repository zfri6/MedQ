"""Faster speech with bounded edge silence; playback clocks stay unchanged."""
from pathlib import Path
from array import array
import hashlib
import json
import wave

ROOT = Path(__file__).resolve().parents[1]
RATE, PAD, FADE, THRESHOLD = 16000, 192, 32, 32
phrases = ['提示','请','A','零','一','二','三','四','五','六','七','八','九','号到','A诊室','B诊室','欢迎','B','就诊','C','D']
patients = json.loads((ROOT / 'assets/patients.json').read_text(encoding='utf-8'))['patients']
phrases += [r['name'] for r in patients] + ['号','到','患者']
entries = []
for i, phrase in enumerate(phrases):
    source = ROOT / 'assets/sd_root' / f'CLIP{i:02}.wav'
    with wave.open(str(source), 'rb') as w:
        assert (w.getnchannels(), w.getsampwidth(), w.getframerate()) == (1, 2, RATE)
        original = w.readframes(w.getnframes())
    samples = array('h', original)
    active = [k for k, v in enumerate(samples) if abs(v) > THRESHOLD]
    assert active, f'Silent speech asset {i}'
    first, last = max(0, active[0] - PAD), min(len(samples), active[-1] + PAD + 1)
    processed = samples[first:last]
    # Fades sit inside the quiet guard regions, not on voiced phonemes.
    for k in range(min(FADE, len(processed) // 2)):
        processed[k] = round(processed[k] * k / FADE)
        processed[-1-k] = round(processed[-1-k] * k / FADE)
    data = processed.tobytes()
    destination = source.with_suffix('.PCM')
    destination.write_bytes(data)
    kept = [k for k, v in enumerate(processed) if abs(v) > THRESHOLD]
    assert kept and len(kept) == len(active), 'Voiced samples removed by trimming'
    entries.append(dict(id=i, file=destination.name, phrase=phrase, bytes=len(data), samples=len(processed),
                        sha256=hashlib.sha256(data).hexdigest(), raw_wav_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                        source_samples=len(samples), removed_samples=len(samples)-len(processed),
                        leading_quiet_ms=kept[0]*1000/RATE,
                        trailing_quiet_ms=(len(processed)-1-kept[-1])*1000/RATE))
assert sum((e['bytes']+3)//4 for e in entries) + 0x0e1000 <= 0x18f000
assert max(e['leading_quiet_ms'] for e in entries) <= 12
assert max(e['trailing_quiet_ms'] for e in entries) <= 12
assert len({e['sha256'] for e in entries[3:13]}) == 10
manifest = {'revision':'masked_smooth_20261102', 'sample_rate':RATE,
            'format':'signed16 little endian mono raw', 'voice':'Microsoft Huihui Desktop',
            'tts_rate':1, 'prior_tts_rate':-1, 'edge_threshold':THRESHOLD,
            'edge_guard_samples':PAD, 'fade_samples':FADE,
            'max_join_quiet_ms':max(e['trailing_quiet_ms'] for e in entries)+max(e['leading_quiet_ms'] for e in entries),
            'sequence':['请','A/B/C/D','实际十位','实际个位','号','完整姓名','到','A/B诊室','就诊'], 'clips':entries}
(ROOT / 'assets/voice_manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
preview = ROOT / 'assets/speech_previews'
preview.mkdir(exist_ok=True)
notes = []
for ticket in ['C01','A02','B09','D05']:
    row = next(r for r in patients if r['ticket'] == ticket)
    n = int(ticket[1:])
    ids = [1, {'A':2,'B':17,'C':19,'D':20}[ticket[0]], 3+n//10, 3+n%10,
           51, row['clip'], 52, 14 if row['room']=='A' else 15, 18]
    data = b''.join((ROOT / 'assets/sd_root' / entries[k]['file']).read_bytes() for k in ids)
    path = preview / (ticket+'_'+row['name']+'.wav')
    with wave.open(str(path), 'wb') as w:
        w.setparams((1, 2, RATE, 0, 'NONE', 'not compressed'))
        w.writeframes(data)
    notes.append({'ticket':ticket, 'text':'请'+ticket+'号'+row['name']+'到'+row['room']+'诊室就诊',
                  'clips':ids, 'duration_seconds':len(data)/(2*RATE), 'file':path.relative_to(ROOT).as_posix(),
                  'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
(preview / 'manifest.json').write_text(json.dumps(notes, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
print('SPEECH_SMOOTH_PASS',len(entries),'clips',sum(e['bytes'] for e in entries),'bytes',
      'max_join_quiet_ms',manifest['max_join_quiet_ms'])
for row in notes:
    print(row['ticket'],f"{row['duration_seconds']:.3f}s",row['text'])

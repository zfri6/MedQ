"""Direct text raster oracles for every per-room operation; no DUT atlas read."""
from pathlib import Path
import json
import hashlib
from build_marquee_reference import ink

ROOT = Path(__file__).resolve().parents[1]
WIDTH, HEIGHT = 384, 20
LABELS = {1: '取号成功，请候诊', 2: '回诊取号成功，请候诊', 4: '已到位，就诊中',
          5: '就诊结束', 6: '已暂停叫号', 7: '已开启叫号', 8: '未到位，已过号', 9: '取号失败·满员或号尽'}


def main():
    values, cases = [], []
    for room in range(2):
        for kind in range(1, 10):
            ret = kind in (2, 4, 5, 8)
            letter = ('D' if room else 'C') if ret else ('B' if room else 'A')
            target = 'B' if room else 'A'
            surname=('马*远' if room else '张*民') if ret else ('杨*宇' if room else '赵*华')
            strip = [[0] * WIDTH for _ in range(HEIGHT)]
            pos = 0

            def put(text, accent=False, numeric=False, gap=0):
                nonlocal pos
                glyph = ink(text, numeric)
                for y, row in enumerate(glyph):
                    for x, cov in enumerate(row):
                        strip[y][pos + x] = cov | (4 if accent and cov else 0)
                pos += len(glyph[0]) + gap

            if kind in (6, 7, 9):
                put(target, True, True, 3); put('诊室', gap=6); put(LABELS[kind])
                text = target + '诊室' + LABELS[kind]
            elif kind == 3:
                put('请', gap=6); put(letter, True, True, 2); put('0', True, True, 2); put('1', True, True, 6)
                put(surname, gap=3); put('到', gap=6); put(target, True, True, 3); put('诊室', gap=5); put('就诊')
                text = f'请{letter}01{surname}到{target}诊室就诊'
            else:
                put(letter, True, True, 2); put('0', True, True, 2); put('1', True, True, 6)
                put(surname, gap=6); put(LABELS[kind])
                text = letter + '01' + surname + LABELS[kind]
            assert pos <= WIDTH
            values.extend(v for row in strip for v in row)
            cases.append(dict(room=room, kind=kind, is_return=ret, text=text, width=pos))
    path = ROOT / 'tb/medq_event_reference.hex'
    path.write_text(''.join(f'{v:x}\n' for v in values), encoding='ascii')
    (ROOT / 'tb/medq_event_widths.hex').write_text(''.join(f'{row["width"]:03x}\n' for row in cases), encoding='ascii')
    (ROOT / 'sim/ui/event_reference.json').write_text(json.dumps({
        'oracle': 'direct independently positioned font rasters, no RTL/generated layout/atlas import',
        'width': WIDTH, 'height': HEIGHT, 'cases': cases,
        'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}, ensure_ascii=False, indent=2), encoding='utf-8')
    print('EVENT_ORACLE_PASS', len(cases), 'messages', len(values), 'source pixels')


if __name__ == '__main__':
    main()

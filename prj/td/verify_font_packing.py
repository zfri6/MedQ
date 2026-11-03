"""Exact unpacked sprite comparison across the two lossless atlas layouts."""
import json
from pathlib import Path
import medq_td

ROOT = medq_td.ROOT


def main():
    before = ROOT / 'doc/compile/masked_smooth/packing_before'
    a = json.loads((before / 'v03_font.json').read_text(encoding='utf-8'))
    b = json.loads((ROOT / 'sim/ui/v03_font.json').read_text(encoding='utf-8'))
    old = [int(v, 16) for v in (before / 'font_v03.hex').read_text().split()]
    new = [int(v, 16) for v in (ROOT / 'rtl/font_v03.hex').read_text().split()]
    assert len(old) == len(new) == 8192 and old[:4096] == new[:4096]
    assert len(a['sprites']) == len(b['sprites']) == 115
    pixels = 0
    for x, y in zip(a['sprites'], b['sprites']):
        assert (x['name'], x['id'], x['w'], x['h']) == (y['name'], y['id'], y['w'], y['h'])
        base = 4096 if x['id'] >= 75 else 0
        for yy in range(x['h']):
            for xx in range(x['w']):
                p, q = x['x']+xx, y['x']+xx
                v = (old[base+(x['y']+yy)*16+p//16] >> (30-2*(p%16))) & 3
                w = (new[base+(y['y']+yy)*16+q//16] >> (30-2*(q%16))) & 3
                assert v == w, (x['name'], xx, yy)
                pixels += 1
    files = [Path(__file__), ROOT / 'rtl/font_v03.hex', ROOT / 'rtl/medq_dual_layout.vh',
             ROOT / 'sim/build_dual_font.py', ROOT / 'sim/ui/v03_font.json',
             before / 'font_v03.hex', before / 'medq_dual_layout.vh', before / 'v03_font.json']
    result = {'status': 'PASS', 'sprite_pixels_compared': pixels, 'sprites': 115,
              'before_rows': a['extra_atlas_rows_used'], 'after_rows': b['extra_atlas_rows_used'],
              'original_4K_unchanged': True,
              'source_sha256': {p.relative_to(ROOT).as_posix(): medq_td.sha(p) for p in files}}
    medq_td.dump(ROOT / 'doc/compile/masked_smooth/lossless_font_packing.json', result)
    print('LOSSLESS_FONT_PACK_PASS', pixels, result['before_rows'], '->', result['after_rows'])


if __name__ == '__main__':
    main()

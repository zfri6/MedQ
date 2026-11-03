"""Independent un-packed pixel oracle for the requested name-placeholder subtitles."""
from pathlib import Path
import hashlib
import json
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
WIDTH, HEIGHT = 384, 20
CASES = [('A', '01', 'A', '赵*华'), ('B', '09', 'B', '蒋*怡'), ('C', '10', 'A', '患者'), ('D', '99', 'B', '患者')]

CASES += [(r['ticket'][0],r['ticket'][1:],r['room'],r['display_name']) for r in json.loads((ROOT/'assets/patients.json').read_text(encoding='utf-8'))['patients']]

def ink(text, numeric=False):
    path = 'C:/Windows/Fonts/' + ('bahnschrift.ttf' if numeric else 'Noto Sans SC Medium (TrueType).otf')
    font = ImageFont.truetype(path, 17 if numeric else 16)
    if numeric:
        font.set_variation_by_name(b'SemiBold')
    canvas = Image.new('L', (512, HEIGHT))
    ImageDraw.Draw(canvas).text((40, 16), text, font=font, fill=255, anchor='ls')
    pixels = [[min(3, int((canvas.getpixel((x, y)) / 255) ** 0.8 * 3 + 0.5))
               for x in range(512)] for y in range(HEIGHT)]
    cols = [x for x in range(512) if any(row[x] for row in pixels)]
    return [row[min(cols):max(cols) + 1] for row in pixels]


def main():
    values, notes = [], []
    for prefix, number, room, surname in CASES:
        strip = [[0] * WIDTH for _ in range(HEIGHT)]
        pos = 0

        def put(text, accent=False, numeric=False, gap=0):
            nonlocal pos
            glyph = ink(text, numeric)
            for y, row in enumerate(glyph):
                for x, cov in enumerate(row):
                    strip[y][pos + x] = cov | (4 if accent and cov else 0)
            pos += len(glyph[0]) + gap

        put('请', gap=6)
        put(prefix, accent=True, numeric=True, gap=2)
        put(number[0], accent=True, numeric=True, gap=2)
        put(number[1], accent=True, numeric=True, gap=6)
        put(surname, gap=3); put('到', gap=6)
        put(room, accent=True, numeric=True, gap=3)
        put('诊室', gap=5)
        put('就诊')
        assert pos <= WIDTH
        values.extend(v for row in strip for v in row)
        notes.append({'text': f'请{prefix}{number}{surname}到{room}诊室就诊', 'width': pos,
                      'prefix': prefix, 'ticket_bcd': int(number, 16), 'room': room})
    path = ROOT / 'tb/medq_marquee_reference.hex'
    path.write_text(''.join(f'{v:x}\n' for v in values), encoding='ascii')
    (ROOT / 'tb/medq_marquee_widths.hex').write_text(''.join(f'{row["width"]:03x}\n' for row in notes), encoding='ascii')
    (ROOT / 'sim/ui/marquee_name_reference.json').write_text(json.dumps({
        'oracle': 'independent direct Pillow raster; no DUT atlas, generated header or RTL imported',
        'width': WIDTH, 'height': HEIGHT, 'cases': notes,
        'fixture_sha256': hashlib.sha256(path.read_bytes()).hexdigest()}, ensure_ascii=False, indent=2), encoding='utf-8')
    print('MARQUEE_ORACLE_PASS', len(values), 'pixels, all 30 masked names, calling privacy, and anonymous boundaries')


if __name__ == '__main__':
    main()

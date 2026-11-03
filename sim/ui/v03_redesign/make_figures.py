"""Assemble preview / edge-zoom figures from RTL-rendered PPM frames.

usage: python make_figures.py <after_dir> <before_ppm> <out_dir>
Pixels are copied unchanged; zooms use nearest-neighbour only.
"""
from pathlib import Path
import sys
from PIL import Image, ImageDraw, ImageFont

FONT = 'C:/Windows/Fonts/msyh.ttc'


def zoom(im, box, k):
    c = im.crop(box)
    return c.resize((c.width * k, c.height * k), Image.Resampling.NEAREST)


def panel(pairs, title):
    label = ImageFont.truetype(FONT, 18)
    w = max(a.width + b.width for _, a, b in pairs) + 60
    h = sum(max(a.height, b.height) + 40 for _, a, b in pairs) + 50
    out = Image.new('RGB', (w, h), 'white')
    d = ImageDraw.Draw(out)
    d.text((20, 12), title, font=label, fill=(23, 50, 74))
    y = 50
    for name, a, b in pairs:
        d.text((20, y), f'{name}  左：改前 V0.3   右：改后', font=label, fill=(100, 122, 139))
        y += 28
        out.paste(a, (20, y))
        out.paste(b, (40 + a.width, y))
        y += max(a.height, b.height) + 12
    return out


def main():
    after_dir, before_ppm, out = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
    shots = {p.stem: Image.open(p).convert('RGB') for p in sorted(after_dir.glob('s*.ppm'))}
    for name, im in shots.items():
        im.save(out / f'{name}.png')
    hero = shots['s1_a01_b01']
    hero.save(out / 'preview_640x480.png')
    grid = Image.new('RGB', (640 * 2 + 8, 480 * 3 + 16), (200, 210, 216))
    for i, name in enumerate(sorted(shots)):
        grid.paste(shots[name], ((i % 2) * 648, (i // 2) * 488))
    grid.save(out / 'preview_states.png')

    before = Image.open(before_ppm).convert('RGB')
    pairs = [
        ('大号码 A01', zoom(before, (56, 238, 164, 292), 4), zoom(hero, (60, 244, 176, 298), 4)),
        ('诊室标题/状态', zoom(before, (24, 184, 112, 238), 5), zoom(hero, (28, 156, 116, 230), 5)),
        ('字幕', zoom(before, (24, 80, 140, 106), 5), zoom(hero, (24, 74, 140, 100), 5)),
    ]
    panel(pairs, 'MedQ V0.3 字体边缘放大（最近邻放大，RTL 实际像素）').save(out / 'font_edge_zoom.png')
    # Pixel-level close-up of one glyph edge on the new page.
    zoom(hero, (68, 248, 100, 280), 12).save(out / 'font_edge_zoom_12x.png')


if __name__ == '__main__':
    main()

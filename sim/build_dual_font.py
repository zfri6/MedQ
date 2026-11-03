"""Build the V0.3 dual-clinic two-bit coverage atlas.

The production font ROM is the existing 4096-word window (virtual 3584..7679,
rtl/font_v03.hex). It now holds one 256x256 atlas with four coverage levels:
16 two-bit pixels per word, MSB-left, word = row*16 + x/16. Glyphs are never
thresholded to one bit. Normal simulation uses the saved HEX and needs neither
Pillow nor the fonts below.
"""
from pathlib import Path
import argparse
import json
import math
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
FONTS = 'C:/Windows/Fonts/'
BASE, WORDS, ATLAS_W, ATLAS_H = 3584, 4096, 256, 256
GAMMA = 0.8  # Slightly darkens partial coverage so thin CJK strokes hold up.

# style: font, pixel size, sprite height, baseline row
STYLES = {
    'title': ('bold', 20, 26, 21),
    'head': ('bold', 17, 22, 18),
    'body': ('medium', 14, 18, 15),
    'small': ('medium', 12, 16, 13),
    'tick': ('medium', 16, 20, 16),
}
LABELS = [
    ('title', 'title', '智慧门诊叫号'),
    ('sub', 'small', 'MedQ·双诊室服务'),
    ('svc_loading', 'body', '语音准备中'),
    ('svc_ready', 'body', '语音就绪'),
    ('svc_basic', 'body', '提示音模式'),
    ('svc_fault', 'body', '存储异常'),
    ('room', 'head', '诊室'),
    ('pill_idle', 'body', '空闲'),
    ('pill_call', 'body', '呼叫中'),
    ('pill_visit', 'body', '就诊中'),
    ('current', 'body', '当前号码'),
    ('wait', 'body', '候诊'),
    ('ret', 'body', '回诊'),
    ('unit', 'body', '人'),
    ('det_none', 'body', '暂无患者'),
    ('det_di', 'body', '第'),
    ('det_call', 'body', '次呼叫·等待到位'),
    ('det_visit', 'body', '患者已到位'),
    ('note_rule', 'small', '回诊患者优先就诊'),
    ('note_reject', 'body', '取号拒绝·满员或号尽'),
    ('map_title', 'head', '示例导诊图'),
    ('map_room', 'body', '诊室'),
    ('map_corridor', 'small', '走廊'),
    ('map_area', 'body', '候诊区'),
    ('map_entry', 'small', '入口'),
    ('map_note1', 'small', '请留意屏幕与语音'),
    ('tk_qing', 'tick', '请'),
    ('tk_haodao', 'tick', '***到'),
    ('tk_room', 'tick', '诊室'),
    ('tk_jiu', 'tick', '就诊'),
    ('tk_arrived', 'tick', '已到位，就诊中'),
    ('tk_none', 'tick', '暂无候诊'),
    ('tk_soon', 'tick', '即将叫号'),
]
EXTRA_LABELS = [
    ('tk_stars', 'tick', '***'),
    ('tk_taken', 'tick', '取号成功，请候诊'),
    ('tk_return_taken', 'tick', '回诊取号成功，请候诊'),
    ('tk_left', 'tick', '就诊结束'),
    ('tk_pause', 'tick', '已暂停叫号'),
    ('tk_enable', 'tick', '已开启叫号'),
    ('tk_missed', 'tick', '未到位，已过号'),
    ('tk_reject', 'tick', '取号失败·满员或号尽'),
]
patients = json.loads((ROOT / 'assets/patients.json').read_text(encoding='utf-8'))['patients']
EXTRA_LABELS += [('surname_' + str(i), 'tick', row['display_name']) for i, row in enumerate(patients)]
EXTRA_LABELS += [('tk_dao', 'tick', '到'), ('tk_anonymous', 'tick', '患者')]
# A/B are ordinary room prefixes; C/D are the distinct return-queue prefixes
# for room A/B. Keep all four in every proportional numeral atlas.
GLYPHS = '0123456789ABCD'
# numeral set: pixel size, tracking, fixed (height, baseline) or None, supersample
NUMERALS = {'big': (66, 5, None, True), 'mid': (26, 2, None, False), 'tick': (17, 2, (20, 16), False)}
RADII = (4, 6, 8, 12)


def quantize(im):
    return im.point(lambda v: min(3, int(((v / 255) ** GAMMA) * 3 + 0.5)))


def crop_columns(levels):
    """Trim empty columns so spacing is set explicitly from ink, not bearings."""
    cols = [x for x in range(levels.width) if any(levels.getpixel((x, y)) for y in range(levels.height))]
    return levels.crop((cols[0], 0, cols[-1] + 1, levels.height))


def render(font, text, height, baseline, supersample):
    k = 4 if supersample else 1
    canvas = Image.new('L', ((len(text) * 2 + 4) * height * k, height * k))
    ImageDraw.Draw(canvas).text((2 * height * k, baseline * k), text, font=font, fill=255, anchor='ls')
    if supersample:
        canvas = canvas.reduce(k)  # Box filter: exact area coverage, no ringing.
    return crop_columns(quantize(canvas))


def load(path, size, variation=None):
    font = ImageFont.truetype(path, size)
    if variation:
        font.set_variation_by_name(variation)
    return font


def cut_table(radius):
    """Per-row corner inset plus a half-coverage edge flag, sampled at pixel centres."""
    rows = []
    for i in range(radius):
        dy = radius - i - 0.5
        boundary = radius - math.sqrt(max(0.0, radius * radius - dy * dy))
        full = int(boundary)
        partial = full + 1 - boundary  # covered share of the first non-empty pixel
        if partial <= 0.2:
            rows.append((full + 1, 0))
        elif partial >= 0.8:
            rows.append((full, 0))
        else:
            rows.append((full, 1))
    return rows


def _pack_order(sprites, order):
    """Best-short-side-fit rectangle packing; IDs remain declaration order."""
    # The original skyline pack filled the atlas exactly. C/D return prefixes
    # add six small glyphs, so use the free rectangles between existing sprites
    # instead of changing font sizes or dropping coverage levels.
    free = [(0, 0, ATLAS_W, ATLAS_H)]
    place = {}
    for i in order:
        im = sprites[i][1]
        best = None
        for fi, (fx, fy, fw, fh) in enumerate(free):
            if im.width <= fw and im.height <= fh:
                score = (min(fw - im.width, fh - im.height),
                         max(fw - im.width, fh - im.height), fy, fx)
                if best is None or score < best[0]:
                    best = (score, fi, fx, fy)
        if best is None:
            raise ValueError('Coverage atlas overflow: shorten labels or reduce sizes')
        _, _, px, py = best
        place[i] = (px, py)
        new_free = []
        for fx, fy, fw, fh in free:
            if px >= fx + fw or px + im.width <= fx or py >= fy + fh or py + im.height <= fy:
                new_free.append((fx, fy, fw, fh))
                continue
            if px > fx:
                new_free.append((fx, fy, px - fx, fh))
            if px + im.width < fx + fw:
                new_free.append((px + im.width, fy, fx + fw - (px + im.width), fh))
            if py > fy:
                new_free.append((fx, fy, fw, py - fy))
            if py + im.height < fy + fh:
                new_free.append((fx, py + im.height, fw, fy + fh - (py + im.height)))
        pruned = []
        for fi, rect in enumerate(new_free):
            fx, fy, fw, fh = rect
            if fw <= 0 or fh <= 0:
                continue
            contained = any(fi != fj and ox <= fx and oy <= fy and
                            ox + ow >= fx + fw and oy + oh >= fy + fh
                            for fj, (ox, oy, ow, oh) in enumerate(new_free))
            if not contained:
                pruned.append(rect)
        free = pruned
    used_rows = max((y + sprites[i][1].height for i, (x, y) in place.items()), default=0)
    return place, used_rows


def pack(sprites):
    # Repacking must preserve every pixel, font size and two-bit coverage level.
    # Try deterministic rectangle orderings before declaring the fixed ROM full.
    keys = [lambda im: (im.width, im.height),
            lambda im: (max(im.size), min(im.size)),
            lambda im: (im.width * im.height, im.width),
            lambda im: (im.height, im.width),
            lambda im: (im.width + im.height, im.width)]
    for key in keys:
        order = sorted(range(len(sprites)),
                       key=lambda i: tuple(-v for v in key(sprites[i][1])) + (i,))
        try:
            return _pack_order(sprites, order)
        except ValueError:
            pass
    raise ValueError('Coverage atlas overflow after all lossless packing orders')


def pack_extra(sprites):
    """Equal-height ticker sprites use tight lossless shelves, never scaling."""
    heights = {im.height for _, im in sprites}
    if len(heights) != 1:
        return pack(sprites)
    height = next(iter(heights))
    used, place = [], {}
    for i in sorted(range(len(sprites)), key=lambda i: (-sprites[i][1].width, i)):
        width = sprites[i][1].width
        assert width <= ATLAS_W
        choices = [j for j, x in enumerate(used) if x + width <= ATLAS_W]
        row = max(choices, key=lambda j: used[j]) if choices else len(used)
        if row == len(used):
            used.append(0)
        place[i] = (used[row], row * height)
        used[row] += width
    rows = len(used) * height
    assert rows <= ATLAS_H
    return place, rows


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--medium-font', default=FONTS + 'Noto Sans SC Medium (TrueType).otf')
    parser.add_argument('--bold-font', default=FONTS + 'Noto Sans SC Bold (TrueType).otf')
    parser.add_argument('--number-font', default=FONTS + 'bahnschrift.ttf')
    args = parser.parse_args()
    paths = {'medium': args.medium_font, 'bold': args.bold_font}

    sprites = []
    for name, style, text in LABELS:
        face, size, height, baseline = STYLES[style]
        sprites.append((name, render(load(paths[face], size), text, height, baseline, False)))
    numeral_meta = {}
    for kind, (size, track, fixed, supersample) in NUMERALS.items():
        font = load(args.number_font, size * (4 if supersample else 1), b'SemiBold')
        top = min(font.getbbox(c, anchor='ls')[1] for c in GLYPHS) // (4 if supersample else 1)
        height, baseline = fixed or (2 - top, 1 - top)
        first = len(sprites)
        for i, c in enumerate(GLYPHS):
            sprites.append((f'{kind}_{c}', render(font, c, height, baseline, supersample)))
        numeral_meta[kind] = dict(first=first, track=track, height=height)

    place, used_rows = pack(sprites)
    atlas = Image.new('L', (ATLAS_W, ATLAS_H))
    for i, (name, im) in enumerate(sprites):
        atlas.paste(im, place[i])
    extra_first = len(sprites)
    extra = [(name, render(load(paths[STYLES[style][0]], STYLES[style][1]),
                           text, STYLES[style][2], STYLES[style][3], False))
             for name, style, text in EXTRA_LABELS]
    extra_place, extra_rows = pack_extra(extra)
    atlas_extra = Image.new('L', (ATLAS_W, ATLAS_H))
    for i, (name, im) in enumerate(extra):
        atlas_extra.paste(im, extra_place[i])
        place[extra_first + i] = extra_place[i]
    sprites += extra

    words = [int(v, 16) for v in (ROOT / 'rtl/font_rom.hex').read_text().split()]
    for row in range(ATLAS_H):
        for wx in range(16):
            words[BASE + row * 16 + wx] = sum(atlas.getpixel((wx * 16 + p, row)) << (30 - 2 * p) for p in range(16))
    (ROOT / 'rtl/font_rom.hex').write_text(''.join(f'{w:08x}\n' for w in words), encoding='ascii')
    # The second atlas is production-only. Preserve every legacy full-ROM word
    # outside the original window, including the original UI at8192..16383.
    extra_words = [sum(atlas_extra.getpixel((wx * 16 + p, row)) << (30 - 2 * p)
                       for p in range(16)) for row in range(ATLAS_H) for wx in range(16)]
    (ROOT / 'rtl/font_v03.hex').write_text(''.join(f'{w:08x}\n' for w in words[BASE:BASE + WORDS] + extra_words), encoding='ascii')

    ls = ['// Generated by sim/build_dual_font.py: 256x256 two-bit coverage atlas,',
          '// virtual font words 3584..7679 (the production 4K window).',
          f'localparam D3_ATLAS_BASE={BASE};']
    ls += [f'localparam D3_EXTRA0={extra_first};', f'localparam D3_EXTRA_BASE={BASE + WORDS};']
    for i, (name, im) in enumerate(sprites[:len(LABELS)]):
        ls.append(f'localparam D3_{name.upper()}={i};')
        ls.append(f'localparam D3_W_{name.upper()}={im.width};')
    for i, (name, im) in enumerate(extra):
        ls += [f'localparam D3_{name.upper()}={extra_first + i};', f'localparam D3_W_{name.upper()}={im.width};']
    for kind, meta in numeral_meta.items():
        ls.append(f'localparam D3_{kind.upper()}0={meta["first"]};')
        ls.append(f'localparam D3_{kind.upper()}_H={meta["height"]};')
        ls.append(f'localparam D3_{kind.upper()}_TRACK={meta["track"]};')
    ls += ['function [31:0] d3_sprite;', 'input [6:0] id;', 'begin', 'case(id)']
    for i, (name, im) in enumerate(sprites):
        x, y = place[i]
        ls.append(f"{i}:d3_sprite={{8'd{x},8'd{y},8'd{im.width},8'd{im.height}}};")
    ls += ["default:d3_sprite=32'd0;", 'endcase', 'end', 'endfunction']
    for kind, meta in numeral_meta.items():
        ls += [f'// Advance = ink width + tracking; proportional, so "1" does not leave holes.',
               f'function [5:0] d3_{kind}_adv;', 'input [3:0] glyph;', 'begin', 'case(glyph)']
        for g in range(len(GLYPHS)):
            ls.append(f"{g}:d3_{kind}_adv=6'd{sprites[meta['first'] + g][1].width + meta['track']};")
        ls += [f"default:d3_{kind}_adv=6'd{sprites[meta['first']][1].width + meta['track']};", 'endcase', 'end', 'endfunction']
    ls += ['// Rounded-corner inset {edge_half_coverage, inset} for row distance to the nearest edge.',
           'function [4:0] d3_cut;', 'input [3:0] radius;', 'input [9:0] row;', 'begin', "d3_cut=5'd0;", 'case(radius)']
    for r in RADII:
        ls.append(f'{r}:case(row)')
        for i, (inset, edge) in enumerate(cut_table(r)):
            ls.append(f"{i}:d3_cut={{1'b{edge},4'd{inset}}};")
        ls.append("default:d3_cut=5'd0;endcase")
    ls += ["default:d3_cut=5'd0;", 'endcase', 'end', 'endfunction']
    (ROOT / 'rtl/medq_dual_layout.vh').write_text('\n'.join(ls) + '\n', encoding='ascii')

    out = ROOT / 'sim/ui'
    preview = atlas.point(lambda v: 255 - v * 85)
    preview.save(out / 'v03_font_atlas.png')
    atlas_extra.point(lambda v: 255 - v * 85).save(out / 'v03_font_events_atlas.png')
    entries = [dict(id=i, name=n, page=int(i>=extra_first), x=place[i][0], y=place[i][1], w=im.width, h=im.height) for i, (n, im) in enumerate(sprites)]
    (out / 'v03_font.json').write_text(json.dumps({
        'coverage_bits': 2, 'levels': [0, 85, 170, 255], 'gamma': GAMMA,
        'virtual_base_word': BASE, 'rom_words': WORDS * 2, 'atlas': [ATLAS_W, ATLAS_H], 'atlas_rows_used': used_rows,
        'extra_atlas_rows_used': extra_rows,
        'fonts': {'chinese_medium': Path(args.medium_font).name, 'chinese_bold': Path(args.bold_font).name,
                  'numerals': Path(args.number_font).name + ' SemiBold'},
        'labels': {n: t for n, _, t in LABELS + EXTRA_LABELS}, 'sprites': entries}, ensure_ascii=False, indent=2), encoding='utf-8')
    print(f'V0.3 coverage atlas: {len(sprites)} sprites, two 4096-word pages, original glyph coverage preserved')


if __name__ == '__main__':
    main()

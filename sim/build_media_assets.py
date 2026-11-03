"""Prepare native SD BMPs offline. Runtime performs no JPEG or PNG decoding."""
from pathlib import Path
from PIL import Image, ImageOps, ImageDraw
import hashlib
import json
import struct

ROOT = Path(__file__).resolve().parents[1]

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def bmp_topdown(im, path):
    im = im.convert('RGB')
    width, height = im.size
    raw = im.tobytes('raw', 'BGR')
    assert width % 4 == 0
    header = b'BM'+struct.pack('<IHHI', 54+len(raw), 0, 0, 54)
    header += struct.pack('<IiiHHIIiiII', 40, width, -height, 1, 24, 0, len(raw), 2835, 2835, 0, 0)
    path.write_bytes(header+raw)
    assert Image.open(path).convert('RGB').tobytes() == im.tobytes()

def main():
    source = ROOT/'assets/media_source'
    target = ROOT/'assets/sd_root'
    preview = ROOT/'sim/ui/media_assets'
    preview.mkdir(parents=True, exist_ok=True)
    records = []
    configs = [
        ('cover.jpg', 'COVER.BMP', None),
        ('doctor_male.png', 'DOC01.BMP', (210, 0, 1270, 900)),
        ('doctor_female.jpg', 'DOC02.BMP', (160, 0, 1175, 855)),
    ]
    for original, runtime, crop in configs:
        p = source/original
        photo = Image.open(p).convert('RGB')
        size = photo.size
        if crop is None:
            canvas = ImageOps.fit(photo, (640, 480), method=Image.Resampling.LANCZOS)
        else:
            canvas = Image.new('RGB', (640, 480), 'white')
            # Supersampled corner mask prevents staircase edges in the viewport.
            cut = ImageOps.fit(photo.crop(crop), (152,128), method=Image.Resampling.LANCZOS)
            mask = Image.new('L', (608,512))
            ImageDraw.Draw(mask).rounded_rectangle((0,0,607,511), radius=32, fill=255)
            mask = mask.resize((152,128), Image.Resampling.LANCZOS)
            canvas.paste(cut, (456,298), mask)
        bmp_topdown(canvas, target/runtime)
        canvas.save(preview/(runtime[:-4]+'.png'))
        records.append(dict(source=str(p.relative_to(ROOT)), source_sha256=sha(p), source_size=size,
                            crop=crop, runtime=str((target/runtime).relative_to(ROOT)), sha256=sha(target/runtime),
                            dimensions=[640,480], format='24-bit uncompressed top-down BMP',
                            viewport=None if crop is None else [456,298,152,128]))
    manifest = dict(revision='media_carousel_20261103', male_selection='doctor_male.png',
                    scaling='offline Lanczos, supersampled rounded corner mask; runtime native pixels', images=records)
    (ROOT/'assets/media_manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(manifest, ensure_ascii=False, indent=2))

if __name__ == '__main__':
    main()

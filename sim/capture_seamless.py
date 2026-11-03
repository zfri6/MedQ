"""Convert the actual scene/font raster captures; never redraw subtitle text."""
from pathlib import Path
import argparse
import hashlib
import json
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--source', default='sim/tests/modelsim/tb_marquee_seamless')
    args = ap.parse_args()
    source = ROOT / args.source
    out = ROOT / 'sim/ui/seamless_marquee'
    out.mkdir(parents=True, exist_ok=True)
    paths = sorted(source.glob('seamless_*.ppm'))
    assert len(paths) == 38
    frames, records = [], []
    for p in paths:
        step = int(p.stem.split('_')[-1])
        im = Image.open(p).convert('RGB')
        assert im.size == (592, 40)
        dest = out / (p.stem + '.png')
        im.save(dest)
        records.append({'left_steps': step, 'source': p.relative_to(ROOT).as_posix(),
                        'ppm_sha256': hashlib.sha256(p.read_bytes()).hexdigest(),
                        'png': dest.relative_to(ROOT).as_posix(),
                        'png_sha256': hashlib.sha256(dest.read_bytes()).hexdigest()})
        if step != 592:
            frames.append(im)
    assert Image.open(paths[0]).tobytes() == Image.open(paths[-1]).tobytes()
    # 16 left steps/frame, two original VGA frame periods/step: true playback speed.
    duration_ms = 16 * 2 * 800 * 525 / 25000000 * 1000
    durations = [round((i+1)*duration_ms/10)*10-round(i*duration_ms/10)*10 for i in range(len(frames))]
    frames[0].save(out/'continuous.gif', save_all=True, append_images=frames[1:],
                   duration=durations, loop=0, optimize=False, disposal=2)
    frames[0].save(out/'continuous.png', save_all=True, append_images=frames[1:],
                   duration=duration_ms, loop=0, disposal=0)
    summary = {'scope': 'actual RTL scene + unchanged production font pixels; PPM conversion only; no board evidence',
               'source_directory': args.source, 'positions_per_revolution': 592,
               'one_pixel_per_vga_frames': 2, 'animation_step_pixels': 16,
               'animation_frame_ms': duration_ms, 'revolution_seconds': 592 * 2 * 800 * 525 / 25000000,
               'frames': records}
    (out/'capture_manifest.json').write_text(json.dumps(summary, indent=2)+'\n', encoding='utf-8')
    print('SEAMLESS_CAPTURE_PASS', len(records), 'actual RTL strips; exact 592-step return; true-speed preview')


if __name__ == '__main__':
    main()

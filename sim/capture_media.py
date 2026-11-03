"""Convert proven RTL PPM pixels to review PNGs, with source hashes."""
from pathlib import Path
from PIL import Image
import argparse
import hashlib
import json

ROOT=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--source',required=True);ap.add_argument('--destination',default='sim/ui/media_rtl')
    a=ap.parse_args();source=ROOT/a.source;out=ROOT/a.destination;out.mkdir(parents=True,exist_ok=True)
    files=sorted(source.glob('media_*.ppm'));assert files
    records=[];pictures={}
    for p in files:
        im=Image.open(p).convert('RGB');assert im.size==(640,480)
        dest=out/(p.stem+'.png');im.save(dest);pictures[p.stem]=im
        records.append(dict(source=p.relative_to(ROOT).as_posix(),source_sha256=sha(p),png=dest.relative_to(ROOT).as_posix(),png_sha256=sha(dest)))
    if 'media_1_64' in pictures:
        male=pictures['media_1_64'];female=pictures['media_2_64']
        sheet=Image.new('RGB',(1280,480));sheet.paste(male,(0,0));sheet.paste(female,(640,0));sheet.save(out/'two_portraits.png')
        frames=[pictures['media_1_64']]*6+[pictures[f'media_1_{n:02d}'] for n in range(56,-1,-8)]
        frames += [pictures[f'media_2_{n:02d}'] for n in range(0,65,8)]+[pictures['media_2_64']]*6
        frames += [pictures[f'media_2_{n:02d}'] for n in range(56,-1,-8)]+[pictures[f'media_1_{n:02d}'] for n in range(0,65,8)]
        frames[0].save(out/'fade_review.png',save_all=True,append_images=frames[1:],duration=67.2,loop=0,disposal=0)
    (out/'capture_manifest.json').write_text(json.dumps(dict(scope='Actual RTL pixels only; PPM conversion, no software UI redraw, not a board photo',
        animation_note='Alpha test snapshots; full production frame-held smoothstep animation is verified separately',frames=records),indent=2)+'\n',encoding='utf-8')
    print('Converted',len(records),'actual RTL frames:',out)

if __name__=='__main__':main()

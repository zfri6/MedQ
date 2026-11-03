"""Export previews from actual RTL captures; never redraw or retouch pixels."""
from pathlib import Path
from PIL import Image
import argparse
import hashlib
import json

ROOT=Path(__file__).resolve().parent.parent

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input',default='sim/tests/modelsim/tb_medq_ui')
    args=parser.parse_args()
    source=ROOT/args.input
    dest=ROOT/'sim/ui';dest.mkdir(exist_ok=True)
    frames=[];hashes={}
    for index in range(20):
        path=source/f'ui_frame_{index:02d}.ppm'
        im=Image.open(path).convert('RGB')
        if im.size!=(640,480):raise ValueError(f'Wrong size: {path}')
        frames.append(im.copy())
        hashes[path.relative_to(ROOT).as_posix()]=hashlib.sha256(path.read_bytes()).hexdigest()
    frames[17].save(dest/'medq_dashboard.png')
    frames[18].save(dest/'medq_recall.png')
    frames[19].save(dest/'medq_priority.png')
    # GIF timestamps have 10ms resolution. Twenty ms keeps every captured frame.
    # The RTL itself still advances at 59.5238Hz (16.8ms/frame).
    sequence=[frames[0]]+frames[1:18]+[frames[18],frames[19]]
    durations=[900]+[20]*16+[1100,700,1100]
    palette=Image.new('RGB',(640,480*3))
    for i,index in enumerate((0,17,19)):palette.paste(frames[index],(0,i*480))
    palette=palette.quantize(colors=128)
    sequence=[f.quantize(palette=palette,dither=Image.Dither.NONE) for f in sequence]
    sequence[0].save(dest/'medq_call_animation.gif',save_all=True,append_images=sequence[1:],
                     duration=durations,loop=0,disposal=1,optimize=True)
    # Flat-color and ROM coverage checks are independent of the RTL scoreboard.
    settled=frames[17]
    if settled.getpixel((0,100))!=(236,243,247):raise ValueError('Raster origin/background mismatch')
    if settled.getpixel((30,42))!=(7,138,134):raise ValueError('Medical icon position mismatch')
    colors=settled.crop((44,198,264,266)).getcolors(1000)
    coverage_colors={(255,255,255),(177,187,195),(100,118,134),(22,50,74)}
    actual={color for count,color in colors}
    if not coverage_colors.issubset(actual):raise ValueError(f'Missing AA coverage level: {actual}')
    row={'status':'PASS','origin':'RTL osd_renderer + synchronous font_rom',
         'captures':20,'width':640,'height':480,'scan_refresh_hz':25_000_000/800/525,
         'call_animation_frames':16,'call_animation_ms':268.8,'gif_step_ms':20,
         'checks':['frame dimensions','raster/icon position','all four AA coverage colors'],
         'capture_sha256':hashes}
    (dest/'preview_verification.json').write_text(json.dumps(row,indent=2)+'\n',encoding='utf-8')
    print('PASS: actual RTL PNG/GIF previews in sim/ui; all four coverage levels present')

if __name__=='__main__':main()

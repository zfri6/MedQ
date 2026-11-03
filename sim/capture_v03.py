"""Convert actual RTL PPMs only; never redraw the UI in software."""
from pathlib import Path
from PIL import Image
import argparse,hashlib,json
ROOT=Path(__file__).resolve().parents[1]
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--source',required=True);a=ap.parse_args()
 source=ROOT/a.source;files=sorted(source.glob('top_frame_*.ppm'));assert len(files)==12
 out=ROOT/'sim/ui/v03_rtl';out.mkdir(exist_ok=True)
 images=[];evidence=[]
 for i,p in enumerate(files):
  im=Image.open(p).convert('RGB');assert im.size==(640,480)
  dest=out/f'frame_{i:02}.png';im.save(dest);images.append(im)
  evidence.append({'source':p.relative_to(ROOT).as_posix(),'ppm_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'png':dest.relative_to(ROOT).as_posix(),'png_sha256':hashlib.sha256(dest.read_bytes()).hexdigest()})
 # GIF timing is quantized to 10ms. APNG retains 16.8ms/frame metadata.
 durations=[round((i+1)*1.68)*10-round(i*1.68)*10 for i in range(len(images))]
 images[0].save(out/'continuous.gif',save_all=True,append_images=images[1:],duration=durations,loop=0,optimize=False,disposal=2)
 images[0].save(out/'continuous.png',save_all=True,append_images=images[1:],duration=16.8,loop=0,disposal=0)
 identical=[(i-1,i) for i in range(1,len(images)) if images[i-1].tobytes()==images[i].tobytes()]
 (out/'capture_manifest.json').write_text(json.dumps({'scope':'Actual full-top RTL pixels, PPM-to-PNG/GIF/APNG conversion only; no board evidence','source_directory':a.source,'frame_period_ms':16.8,'fps':25000000/800/525,'identical_adjacent_frames':identical,'frames':evidence},indent=2),encoding='utf-8')
 print('Converted 12 actual RTL frames; identical adjacent frames:',identical)
if __name__=='__main__':main()

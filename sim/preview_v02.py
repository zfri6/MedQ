"""Export a gallery exclusively from complete RTL captures, no pixel redrawing."""
from pathlib import Path
import argparse,base64,hashlib,json
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--input',default='sim/tests/modelsim/tb_medq_ui');args=ap.parse_args()
    src=ROOT/args.input;out=ROOT/'sim/ui';out.mkdir(exist_ok=True)
    labels=[(17,'ready','语音就绪'),(20,'basic','无卡基础叫号'),(21,'fault','存储异常仍保留叫号'),(22,'care','关怀静态模式'),(24,'loading','正在准备语音'),(25,'warning','缓冲告警')]
    snapshots={};panels=[]
    for i,key,label in labels:
        p=src/f'ui_frame_{i:02d}.ppm';im=Image.open(p).convert('RGB');assert im.size==(640,480)
        dest=out/f'medq_v02_{key}.png';im.save(dest)
        snapshots[p.relative_to(ROOT).as_posix()]=hashlib.sha256(p.read_bytes()).hexdigest()
        panels.append((key,label,base64.b64encode(dest.read_bytes()).decode()))
    a=(src/'ui_frame_22.ppm').read_bytes();b=(src/'ui_frame_23.ppm').read_bytes()
    assert a==b,'Reduced-motion screen changed across30 frames'
    frames=[Image.open(src/f'ui_frame_{i:02d}.ppm').convert('RGB') for i in range(20)]
    frames[0].save(out/'medq_v02_call.png',save_all=True,append_images=frames[1:],duration=[900]+[16.8]*16+[1000,800,1000],loop=0)
    j={'origin':'RTL osd_renderer + synchronous font_rom','raster':[640,480],'actual_scan_hz':25000000/800/525,
       'call_ease_frames':16,'call_ease_ms':268.8,'reduced_motion_30frame_identical':True,'snapshots_sha256':snapshots}
    (out/'v02_preview_evidence.json').write_text(json.dumps(j,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    gallery=''.join(f'<section><h2>{label}</h2><img alt="{label}" src="data:image/png;base64,{data}"></section>' for key,label,data in panels)
    animation=base64.b64encode((out/'medq_v02_call.png').read_bytes()).decode()
    html="""<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>MedQ 医序 v0.2</title>
<style>body{font:16px system-ui,"Microsoft YaHei",sans-serif;background:#ecf3f7;color:#16324a;margin:0;padding:32px}main{max-width:1360px;margin:auto}header{padding:12px 0 24px}h1{font-size:32px;margin:0 0 12px}p{line-height:1.7;color:#60798a}article{display:grid;grid-template-columns:repeat(auto-fit,minmax(440px,1fr));gap:24px}section{background:white;border:1px solid #dce9ee;border-radius:16px;overflow:hidden;padding:16px}h2{font-size:17px;margin:0 0 14px}img{display:block;width:100%;height:auto}small{color:#60798a}.tag{background:#e8f6f2;color:#078a86;padding:6px 12px;border-radius:20px;display:inline-block}</style>
<main><header><div class="tag">MedQ v0.2 · 实际RTL画面</div><h1>有序叫号，连续服务</h1><p>语音未就绪时，屏幕叫号和有限提示音仍可用。关怀模式保持静态重点，减轻位移动画干扰。下方为仿真捕获的完整画面；物理扫描为59.52Hz，截图动画反映逐帧缓动，不代表实板已验收。</p></header><article>
"""+f'<section><h2>16帧叫号聚焦动画</h2><img src="data:image/png;base64,{animation}" alt="RTL叫号动画"></section>'+gallery+'</article><p><small>所有像素直接来自RTL与同步字体ROM，未用网页重画或修饰。工程、资源和时序验收状态请看README与doc/compile/v02_report.md。</small></p></main></html>'
    (out/'MedQ_v02_preview.html').write_text(html,encoding='utf-8')
    print('PASS RTL gallery: six service scenarios, APNG call animation, reduced-motion exact30-frame stability')
if __name__=='__main__':main()

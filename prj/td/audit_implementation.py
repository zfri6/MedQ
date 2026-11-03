"""Read and re-evaluate original TD output; never edit original run results."""
from pathlib import Path
import hashlib,json,re
import medq_td
ROOT=medq_td.ROOT
def main():
    pointer=json.loads((ROOT/'prj/td/latest_MedQv03.json').read_text(encoding='utf-8'))
    result_path=ROOT/pointer['result'];original=json.loads(result_path.read_text(encoding='utf-8'))
    stage=Path(original['stage_path']);run=result_path.parent;name=original['meta']['name']
    changed=[p for p,d in original['meta']['source_sha256'].items() if hashlib.sha256((ROOT/p).read_bytes()).hexdigest()!=d]
    assert not changed,changed
    text=(run/'td_run.log').read_text(encoding='utf-8')
    audited=medq_td.judge(original['mode'],name,stage,text,original['exit_code'])
    physical={}
    p=run/'reports'/f'{name}_phy.area'
    if p.exists():
        for m in re.finditer(r'^#(\w+)\s+(\d+)\s+out of\s+(\d+)',p.read_text(encoding='utf-8'),re.M):
            physical[m[1]]={'used':int(m[2]),'available':int(m[3])}
    timing_path=run/'reports'/f'{name}_pr.timing'
    timing=timing_path.read_text(encoding='utf-8') if timing_path.exists() else ''
    paths=[]
    for block in re.split(r'\nSlack\s*:',timing)[1:]:
        slack=re.match(r'\s*(-?\d+(?:\.\d+)?)ns',block)
        begin=re.search(r'Begin Point\s*:\s*(.+)',block);end=re.search(r'End Point\s*:\s*(.+)',block)
        kind=re.search(r'Check Type\s*:\s*(.+)',block)
        if slack and begin and end and float(slack[1])<0:
            paths.append({'slack_ns':float(slack[1]),'begin':begin[1],'end':end[1],'check':kind[1] if kind else 'unknown'})
    paths.sort(key=lambda p:p['slack_ns'])
    coverage=re.search(r'STA coverage\s*:\s*([\d.]+)%',timing)
    row={'scope':'Re-evaluation of immutable original TD run, not another build or board test',
         'original_result':pointer['result'],'original_status':original['status'],
         'source_hashes_match':True,'audit':audited,'gate':original['gate_resources'],'physical':physical,
         'sta_coverage_percent':float(coverage[1]) if coverage else None,'negative_paths':paths[:20],
         'clock_report_note':'EG4 report_clock_utilization unsupported; Clock Summary already in native pr.timing'}
    out=ROOT/'doc/compile/v03_td_audit.json';out.write_text(json.dumps(row,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(audited['status'],audited['timing_slack_ns'])
    for p in paths[:4]:print(p['slack_ns'],p['check'],p['begin'].split(' (')[0],'->',p['end'].split(' (')[0])
if __name__=='__main__':main()

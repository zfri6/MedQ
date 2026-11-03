"""Freeze the current release and import the user supplied media, without altering history."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json
import shutil

ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path('C:/Users/zhang/xwechat_files/wxid_3anr17hgddu022_185f/temp/RWTemp/2026-11/97e66f37805475c0cbc65bb823453c7e')

def digest(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    target = ROOT / 'baseline' / ('v03_pre_media_' + stamp)
    target.mkdir()
    selected = []
    for folder in ('rtl', 'tb', 'prj/constr', 'doc/arch', 'doc/spec'):
        selected += [p for p in (ROOT / folder).rglob('*') if p.is_file()]
    for folder in ('sim', 'prj/td'):
        selected += list((ROOT / folder).glob('*.py'))
    selected += [ROOT/p for p in ('README.md', 'HANDOFF.md', 'deliverables/latest_v03.json', 'sim/regression_result.json')]
    selected += list((ROOT/'assets').rglob('*'))
    selected = sorted(set(p for p in selected if p.is_file()))
    records = {}
    for p in selected:
        relative = p.relative_to(ROOT)
        destination = target/relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(p, destination)
        records[relative.as_posix()] = digest(p)
        assert digest(destination) == records[relative.as_posix()]
    prior = json.loads((ROOT/'deliverables/latest_v03.json').read_text(encoding='utf-8'))
    for key in ('archive', 'bitstream'):
        assert digest(ROOT/prior[key]) == prior[key+'_sha256']
    original = ROOT/'assets/media_source'
    original.mkdir(parents=True, exist_ok=True)
    photos = {}
    for source_name, name in (
        ('de599429e07956707f76f3a342487481.jpg', 'cover.jpg'),
        ('6acef8137da335a7065bec9ac96bd209.jpg', 'doctor_male_alternate.jpg'),
        ('d5943d8773c6d04e7e07ae061e4e2550.jpg', 'doctor_female.jpg'),
        ('f83f6e2331f852c3fa07ab5602a62045.png', 'doctor_male.png'),
    ):
        shutil.copy2(SOURCE/source_name, original/name)
        photos[name] = dict(original=str(SOURCE/source_name), sha256=digest(original/name))
    manifest = dict(created_utc=stamp, files=records, prior_release=prior, media=photos,
                    board_test='not_tested')
    (target/'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    (ROOT/'doc/compile/media_intake.json').write_text(json.dumps(dict(snapshot=target.relative_to(ROOT).as_posix(), **manifest), ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(f'FROZEN {len(records)} files: {target}')

if __name__ == '__main__':
    main()

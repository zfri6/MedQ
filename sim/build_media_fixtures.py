"""Actual delivered image bytes inside shuffled multi-cluster FAT32 fixtures."""
from pathlib import Path
from PIL import Image
import hashlib
import json
import random
import struct

ROOT = Path(__file__).resolve().parents[1]

def main():
    spc, sectors, fat_sectors = 8, 6144, 8
    data_start = 2+fat_sectors
    disk = bytearray(sectors*512)
    def put(lba, offset, b):
        disk[lba*512+offset:lba*512+offset+len(b)] = b
    def u16(x):return struct.pack('<H', x)
    def u32(x):return struct.pack('<I', x)
    put(0,446,bytes([0,0,0,0,0x0c,0,0,0])+u32(1)+u32(sectors-1))
    put(0,510,b'\x55\xaa')
    put(1,0,b'\xeb\x58\x90MEDQMEDI')
    put(1,11,u16(512)+bytes([spc])+u16(1)+bytes([1]))
    put(1,32,u32(sectors-1));put(1,36,u32(fat_sectors));put(1,44,u32(2));put(1,510,b'\x55\xaa')
    fat = [0]*(fat_sectors*128)
    fat[0:3] = [0x0ffffff8,0x0fffffff,0x0fffffff]
    files = []
    for name in ('DOC02.BMP', 'COVER.BMP', 'DOC01.BMP'):
        files.append((name, (ROOT/'assets/sd_root'/name).read_bytes()))
    files.append(('UNUSED.BMP', b'unrelated image must be ignored'))
    for clip in range(54):
        files.append((f'CLIP{clip:02}.PCM', struct.pack('<hhh', 12000+clip, -10000-clip, 8000+clip)))
    random.Random(203).shuffle(files)
    cluster = 3
    records = []
    for idx, (filename, data) in enumerate(files):
        count = (len(data)+spc*512-1)//(spc*512)
        start = cluster
        for n in range(count):
            fat[cluster] = 0x0fffffff if n==count-1 else cluster+1
            payload = data[n*spc*512:(n+1)*spc*512]
            put(data_start+(cluster-2)*spc, 0, payload)
            cluster += 1
        name, extension = filename.split('.')
        entry = bytearray(32)
        entry[:11] = name.encode().ljust(8,b' ')+extension.encode()
        entry[11] = 0x20
        entry[20:22] = u16(start>>16);entry[26:28] = u16(start&65535);entry[28:32] = u32(len(data))
        put(data_start,idx*32,entry)
        records.append(dict(name=filename, cluster=start, bytes=len(data), clusters=count,
                            sha256=hashlib.sha256(data).hexdigest()))
    assert cluster < 768
    put(2,0,b''.join(u32(v) for v in fat))
    path = ROOT/'tb/medq_media_sd.hex'
    path.write_text(''.join(f'{b:02x}\n' for b in disk), encoding='ascii')
    # An independent, RGB-per-word reference made directly from decoded SD BMP.
    for index,name in enumerate(('COVER.BMP','DOC01.BMP','DOC02.BMP')):
        im = Image.open(ROOT/'assets/sd_root'/name).convert('RGB')
        (ROOT/f'tb/medq_media_rgb{index}.hex').write_text(''.join(f'{r:02x}{g:02x}{b:02x}\n' for r,g,b in im.getdata()),encoding='ascii')
    (ROOT/'sim/ui/media_assets/fixture_manifest.json').write_text(json.dumps(dict(sectors=sectors,spc=spc,
        fat_sectors=fat_sectors,directory_order=records,fixture_sha256=hashlib.sha256(path.read_bytes()).hexdigest()),indent=2)+'\n',encoding='utf-8')
    print('MEDIA FIXTURE:',sectors,'sectors,',len(files),'shuffled files,',cluster-3,'data clusters')

if __name__=='__main__':main()

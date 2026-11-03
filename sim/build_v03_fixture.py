"""64-source-sample clips on an actual SPI/FAT32 test card, for abort/pause."""
from pathlib import Path
import struct
root=Path(__file__).resolve().parents[1]
disk=bytearray(int(v,16) for v in (root/'tb/medq_sd_image.hex').read_text().split())
for i in range(54):
 entry=54-i
 offset=(3*512+entry*32+28) if entry<32 else (119*512+(entry-32)*32+28)
 disk[offset:offset+4]=struct.pack('<I',128)
 pos=(7+2*i)*512
 disk[pos:pos+128]=struct.pack('<64h',*[(-1 if n&1 else 1)*(i*100+n*20) for n in range(64)])
(root/'tb/medq_v03_long.hex').write_text(''.join(f'{v:02x}\n' for v in disk),encoding='ascii')
print('V0.3 long voice fixture: original FAT/physical placement, 54x64; reverse directory order PCM samples')

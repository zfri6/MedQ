"""Synthetic FAT32 fixture: MBR, BPB, 2-sector root, BMP and 54 PCM clips."""
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parent.parent
disk = bytearray(128 * 512)
def put(lba, offset, value):
    disk[lba*512+offset:lba*512+offset+len(value)] = value
def u16(value): return struct.pack('<H', value)
def u32(value): return struct.pack('<I', value)
put(0, 446, bytes([0,0,0,0,0x0C,0,0,0])+u32(1)+u32(127))
put(0, 510, b'\x55\xaa')
put(1, 0, b'\xeb\x58\x90MEDQTEST')
put(1, 11, u16(512)+bytes([2])+u16(1)+bytes([1]))
put(1, 32, u32(127)); put(1, 36, u32(1)); put(1, 44, u32(2)); put(1, 510, b'\x55\xaa')
for cluster in range(62): put(2, cluster*4, u32(0x0FFFFFFF))
put(2, 2*4, u32(60))  # two nonadjacent root clusters; 55+ entries

def directory(index, name, extension, cluster, size):
    entry = bytearray(32)
    entry[:11] = name.encode('ascii').ljust(8, b' ')+extension.encode('ascii')
    entry[11]=0x20; entry[20:22]=u16(cluster>>16); entry[26:28]=u16(cluster&65535); entry[28:32]=u32(size)
    start=(3*512+index*32) if index<32 else (119*512+(index-32)*32); disk[start:start+32]=entry
bmp = bytearray(70)
bmp[:2]=b'BM'; bmp[2:6]=u32(70); bmp[10:14]=u32(54); bmp[14:18]=u32(40)
bmp[18:22]=u32(2); bmp[22:26]=struct.pack('<i', -2); bmp[26:28]=u16(1); bmp[28:30]=u16(24)
# Top-down corners: black, red / green, blue; each row has two pad bytes.
bmp[54:]=bytes([0,0,0, 0,0,255, 0,0, 0,255,0, 255,0,0, 0,0])
directory(0, 'GUIDE', 'BMP', 3, len(bmp)); put(5,0,bmp)
for entry,index in enumerate(reversed(range(54))):
    directory(entry+1, f'CLIP{index:02}', 'PCM', index+4, 6)
    put(7+2*index, 0, struct.pack('<hhh', 100+index, -200-index, 300+index))
(ROOT/'tb/medq_sd_image.hex').write_text(''.join(f'{byte:02x}\n' for byte in disk), encoding='ascii')
print('Wrote tb/medq_sd_image.hex: 128 sectors, 1 BMP, 54 PCM clips')

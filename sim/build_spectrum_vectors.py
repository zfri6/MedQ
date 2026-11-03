"""Independent block Goertzel integer reference; no RTL pipeline/state-machine reuse."""
import json
import math
import random
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]


def signed32(value):
    return (value+2**31)%2**32-2**31


def main():
    rng=random.Random(20261026)
    tones=lambda k,a:[round(a*math.sin(2*math.pi*k*n/256)) for n in range(256)]
    blocks=[[0]*256,[32767]*256,[-32768]*256,tones(1,12000),tones(4,18000),tones(16,20000),
            [32767 if n%2 else -32768 for n in range(256)],[-32768+257*n for n in range(256)],
            [rng.randrange(-32768,32768) for n in range(256)],
            [round(6000*math.sin(2*math.pi*2*n/256)+8000*math.sin(2*math.pi*11*n/256)) for n in range(256)],
            [32000]+[0]*255,[0]*256]
    coefs=[round(32768*math.cos(2*math.pi*(i+1)/256)) for i in range(16)]
    expected=[];energies=[]
    for samples in blocks:
        powers=[]
        for coef in coefs:
            s1=s2=0
            for sample in samples:
                s0=signed32(sample+(coef*s1//16384)-s2)
                s2,s1=s1,s0
            power=max(0,s1*s1+s2*s2-s1*(coef*s2//16384))
            powers.append(power)
            expected.append(min(31,max(0,(power>>16).bit_length()-1))*8)
        energies.append(powers)
    for block,target in ((3,0),(4,3),(5,15)):
        assert max(range(16),key=lambda i:energies[block][i])==target
    (ROOT/'tb/medq_spectrum_samples.hex').write_text(''.join(f'{v&65535:04x}\n' for block in blocks for v in block))
    (ROOT/'tb/medq_spectrum_expected.hex').write_text(''.join(f'{v:02x}\n' for v in expected))
    out=ROOT/'sim/resource_optimization';out.mkdir(exist_ok=True)
    (out/'spectrum_reference.json').write_text(json.dumps({'coefficients_q14':coefs,'blocks':len(blocks),
        'samples':len(blocks)*256,'expected_bins':expected,'energies':energies,
        'scope':'Independent parallel per-block fixed-point reference; no RTL TDM scheduling'},indent=2)+'\n')
    print(f'Built {len(blocks)*256} input samples and {len(expected)} independent expected bins')


if __name__=='__main__':main()

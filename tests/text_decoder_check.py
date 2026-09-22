"""Streaming BOM/Unicode decoding compared with Python's strict codecs."""
import argparse
import base64
from pathlib import Path
import random
import subprocess

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('backends', nargs='*', default=['bun', 'native-1', 'native-4'])
p.add_argument('--prefix', type=Path, default=ROOT / 'build/text-decoder')
a = p.parse_args()
random.seed(65001)
texts = ['', 'abc', '\0', 'éα😀', '\ufeffa\ufeff', '\r\n', 'a\U0010ffff',
         ''.join(chr(n) for n in range(128))]
texts += [''.join(chr(random.choice([random.randrange(0xD800), random.randrange(0xE000,0x110000)])) for _ in range(12)) for _ in range(20)]
values = [bom + text.encode(codec) for text in texts for codec,bom in
          [('utf-8',b''),('utf-8',b'\xef\xbb\xbf'),('utf-16le',b'\xff\xfe'),('utf-16be',b'\xfe\xff')]]
values += [b'\xff',b'\xfe',b'\xef',b'\xef\xbb',b'\xef\xbbA',b'\xc0\x80',b'\xed\xa0\x80',
           b'\xf4\x90\x80\x80',b'\xff\xfe\0',b'\xfe\xff\0',b'\xff\xfe\0\xd8',
           b'\xff\xfe\0\xdc',b'\xff\xfe\0\xd8a\0',b'\xfe\xff\xd8\0\0a',
           b'\xff\xfe\xff\xdb\xff\xdf',b'\xef\xbb\xbe',b'a\xff',b'a\xc3']
for _ in range(100):
    values.append(bytes(random.randrange(256) for _ in range(random.randrange(12))))

def oracle(value):
    try:
        codec = 'utf-16' if value.startswith((b'\xff\xfe',b'\xfe\xff')) else 'utf-8-sig'
        return 'ok:' + base64.b64encode(value.decode(codec).encode()).decode()
    except UnicodeError:
        return 'error'

cases = [(split,value,oracle(value)) for value in values for split in range(len(value)+1)]
for backend in a.backends:
    command = ['bun',str(a.prefix)+'.js','--','--'] if backend=='bun' else [str(a.prefix),'--threads',backend[-1],'--']
    for start in range(0,len(cases),100):
        rows=cases[start:start+100]
        args=[arg for split,value,_ in rows for arg in ['x'*split,base64.b64encode(value).decode()]]
        result=subprocess.run(command+args,text=True,capture_output=True,timeout=60)
        assert result.returncode==0,(backend,result.stderr)
        actual=result.stdout.splitlines()
        assert len(actual)==len(rows),(backend,len(actual),len(rows))
        for row,got in zip(rows,actual):assert got==row[2],(backend,row,got)
    print(f'{backend}: {len(cases)} strict UTF-8/UTF-16 BOM and byte-split oracle comparisons passed',flush=True)

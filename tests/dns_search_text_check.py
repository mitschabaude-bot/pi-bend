"""DNS search-text preparation: libc wire/absolute results and presentation dot counts."""
import ctypes
import hashlib
import json
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import platform
import random
import subprocess

ROOT=Path(__file__).resolve().parents[1];bun=Path.home()/'.bun/bin/bun';compiler=Path(BEND)
for suffix in ['c','js']:
    subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/dns-search-text-{suffix}-build.json','--',str(bun),str(compiler),'tests/dns-search-text.bend','-o',f'build/dns-search-text.{suffix}'],cwd=ROOT,check=True)
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'clang','-std=c11','-fbracket-depth=2048','-O1','build/dns-search-text.c','-lpthread','-lm','-o','build/dns-search-text'],cwd=ROOT,check=True)
libc=ctypes.CDLL(None);pton=libc.ns_name_pton;pton.argtypes=[ctypes.c_char_p,ctypes.c_void_p,ctypes.c_size_t];pton.restype=ctypes.c_int

def oracle(text):
    wire=ctypes.create_string_buffer(256);absolute=pton(text.encode('utf8'),wire,len(wire))
    if absolute<0:return 'invalid'
    raw=wire.raw;end=0
    while raw[end]:end+=raw[end]+1
    end+=1;assert end<=255
    return str(text.count('.'))+':'+str(absolute)+':'+''.join(str(byte)+',' for byte in raw[:end])

values=['','.','a','a.','a.b','a.b.','.a','a..','a..b','..','...',r'a\.b',r'a\.b.',r'\.',r'\\',
        '\\',r'\0',r'\00',r'\000',r'\255',r'\256',r'\999',r'\01a',r'\a',r'\1234',r'a\000b',r'\046',
        'a b','a\tb','x/y','x:y','[a]','bücher.example','例子.测试','😀.example',r'a\[b',
        'a'*63,'a'*64,'a'*256,'a'*100000,'é'*31,'é'*32,'a.'*126+'a','a.'*127+'a',
        '.'.join(['a'*63]*3+['b'*61]),'.'.join(['a'*63]*3+['b'*62])]
for n in range(1000):values.append('\\'+str(n).zfill(3))
for n in range(1,256):
    # A backslash followed by a non-digit quotes its byte (UTF-8 for text >127).
    values.extend(['\\'+chr(n), 'a\\'+chr(n)+'.b'])
for size in range(58,68):
    for final in ['', '.']:
        values.extend(['a'*size+final,('\\255'*size)+final,'.'.join(['x'*63]*3+['y'*size])+final])
rng=random.Random(8012)
alphabet=['a','Z','1','-','_','.', '\\', '0','2','5','9','é','😀',' ']
for _ in range(600):values.append(''.join(rng.choices(alphabet,k=rng.randrange(1,90))))
values=list(dict.fromkeys(values));expected=[oracle(v) for v in values];rows=[]
for label,command in [('native 1',['build/dns-search-text','--threads','1']),('native 4',['build/dns-search-text','--threads','4']),('Bun',[str(bun),'build/dns-search-text.js'])]:
    for start in range(0,len(values),64):
        batch=values[start:start+64];want=expected[start:start+64]
        run=subprocess.run([*command,*batch],cwd=ROOT,capture_output=True,text=True,timeout=30)
        assert run.returncode==0 and not run.stderr,(label,start,run.returncode,run.stderr,run.stdout[-500:])
        got=run.stdout.splitlines()
        assert len(got)==len(want),(label,start,len(got),len(want))
        for text,actual,result in zip(batch,got,want):assert actual==result,(label,repr(text),actual,result)
    rows.append(dict(backend=label,presentation_cases=len(values)));print(f'{label}: {len(values)} presentation names PASS',flush=True)
paths=['packages/runtime/src/dns-message.bend','packages/runtime/src/dns-message.bend','packages/runtime/src/dns-message.bend','packages/runtime/src/utf8.bend','tests/dns-search-text.bend','tests/dns_search_text_check.py','build/dns-search-text','build/dns-search-text.js']
(ROOT/'build/dns-search-text-result.json').write_text(json.dumps(dict(scope=__doc__,cases=rows,libc_version=list(platform.libc_ver()),sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},builds={suffix:json.loads((ROOT/f'build/dns-search-text-{suffix}-build.json').read_text()) for suffix in ['c','js']}),indent=2)+'\n')

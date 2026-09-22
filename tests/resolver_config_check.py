"""Immutable resolver configuration syntax, compared with an independent model.

This checks parsing and preservation, not defaults or applied resolver policy.
"""
import ctypes
import hashlib
import json
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import random
import re
import socket
import subprocess

ROOT=Path(__file__).resolve().parents[1];bun=Path.home()/'.bun/bin/bun';compiler=Path(BEND)
for suffix in ['c','js']:
    subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/resolver-config-{suffix}-build.json','--',str(bun),str(compiler),'tests/resolver-config.bend','-o',f'build/resolver-config.{suffix}'],cwd=ROOT,check=True)
subprocess.run(['clang','-std=c11','-fbracket-depth=2048','-O1','build/resolver-config.c','-lpthread','-lm','-o','build/resolver-config'],cwd=ROOT,check=True)
libc=ctypes.CDLL(None);aton=libc.__inet_aton_exact;aton.argtypes=[ctypes.c_char_p,ctypes.c_void_p];aton.restype=ctypes.c_int

def address(text):
    word=ctypes.create_string_buffer(4)
    if aton(text.encode(),word):return '4:'+str(int.from_bytes(word.raw,'big'))
    host,sep,zone=text.partition('%')
    try:raw=socket.inet_pton(socket.AF_INET6,host)
    except OSError:return 'invalid'
    return '6:'+','.join(str(int.from_bytes(raw[i:i+4],'big')) for i in range(0,16,4))+':'+('some:'+zone if sep else 'none')

def fields(values):return ''.join(f'{len(value)}:{value}' for value in values)

def model(text):
    result=[]
    for line in text.split('\n'):
        if not line or line[0] in '#;':continue
        match=re.match(r'([^ \t]*)[ \t](.*)\Z',line,re.DOTALL)
        if not match:
            result.append('unknown:'+fields([line]));continue
        key,tail=match.groups();values=[v for v in re.split('[ \t]+',tail) if v]
        if key=='nameserver':
            token=values[0] if values else ''
            result.append('server:'+fields([token])+':'+address(token))
        elif key=='domain':
            if values:result.append('domain:'+fields(values[:1]))
        elif key=='search':
            if values:result.append('search:'+fields(values))
        elif key in ['options','sortlist']:result.append(('options:' if key=='options' else 'sort:')+fields(values))
        else:result.append('unknown:'+fields([line]))
    return result+['END']

values=['', '\n\n', '# comment\n; comment\n', 'nameserver 127.0.0.1\nsearch example.test local\noptions ndots:2 timeout:3 attempts:4 rotate',
        'nameserver ::1\nnameserver fe80::1%eth0\nnameserver 0x7f.1\nnameserver 127.0.0.1.',
        'domain first\nsearch second third\ndomain last ignored\nsearch \noptions \nsortlist ',
        'search example #not-an-inline-comment ;also-a-token\noptions unknown-option ndots:15',
        'NAMESERVER 127.0.0.1\n nameserver 127.0.0.1\n\tnameserver ::1',
        'nameserver 127.0.0.1\r\nsearch domain\r\noptions rotate\r\n',
        'search ünicode.test 😀.test\ncustom éclair\n',
        'nameserver 1 # ignored tail\nnameserver 2;not-a-comment\nnameserver 3\t; ignored tail',
        '\n'.join(['nameserver 127.0.0.1','options rotate']*5000),
        'search '+' '.join('d'+str(i)+'.test' for i in range(5000))]
rng=random.Random(8139)
keywords=['nameserver','domain','search','options','sortlist','unknown','NAMESERVER',' nameserver','nameserverx']
tokens=['127.0.0.1','0x7f.1','::1','fe80::2%lo','bad','0x','example.test','ndots:3','rotate','#x',';x','😀','']
for _ in range(400):
    lines=[]
    for _ in range(rng.randrange(1,16)):
        key=rng.choice(keywords);separator=rng.choice([' ','\t','  \t',''])
        tail=rng.choice([' ','\t']).join(rng.choices(tokens,k=rng.randrange(6)))
        lines.append(key+separator+tail)
    values.append('\n'.join(lines)+rng.choice(['','\n']))
rows=[]
for label,command in [('native 1',['build/resolver-config','--threads','1']),('native 4',['build/resolver-config','--threads','4']),('Bun',[str(bun),'build/resolver-config.js'])]:
    # Keep large documents below per-argument and total exec limits.
    for text in values:
        if len(text.encode())>120000:
            # Split only the deliberately repeated-line stress document into
            # two large documents; each still exercises thousands of entries.
            documents=text.split('\n');half=len(documents)//2
            inputs=['\n'.join(documents[:half]),'\n'.join(documents[half:])]
        else:inputs=[text]
        want=[line for source in inputs for line in model(source)]
        run=subprocess.run([*command,*inputs],cwd=ROOT,capture_output=True,timeout=30)
        assert run.returncode==0 and not run.stderr,(label,run)
        got=run.stdout.decode().split('\n');assert got[-1]=='';got.pop()
        assert got==want,(label,repr(text[:500]),got[:30],want[:30])
    rows.append(dict(backend=label,documents=len(values)));print(f'{label}: {len(values)} configuration documents PASS',flush=True)
paths=['packages/runtime/src/resolver-config.bend','packages/runtime/src/resolver-config.bend','tests/resolver-config.bend','tests/resolver_config_check.py','build/resolver-config','build/resolver-config.js']
(ROOT/'build/resolver-config-result.json').write_text(json.dumps(dict(scope=__doc__,cases=rows,sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths}),indent=2)+'\n')

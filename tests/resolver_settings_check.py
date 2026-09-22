"""Resolver source precedence over typed overrides, independent of network I/O.

Option/sort tokens are retained, not interpreted. The override strings in this
fixture encode already-decoded lists, not libc environment-string semantics.
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
    subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/resolver-settings-{suffix}-build.json','--',str(bun),str(compiler),'tests/resolver-settings.bend','-o',f'build/resolver-settings.{suffix}'],cwd=ROOT,check=True)
subprocess.run(['clang','-std=c11','-fbracket-depth=2048','-O1','build/resolver-settings.c','-lpthread','-lm','-o','build/resolver-settings'],cwd=ROOT,check=True)
libc=ctypes.CDLL(None);aton=libc.__inet_aton_exact;aton.argtypes=[ctypes.c_char_p,ctypes.c_void_p];aton.restype=ctypes.c_int

def address(text):
    word=ctypes.create_string_buffer(4)
    if aton(text.encode(),word):return '4:'+str(int.from_bytes(word.raw,'big'))
    host,sep,zone=text.partition('%')
    try:raw=socket.inet_pton(socket.AF_INET6,host)
    except OSError:return None
    return '6:'+','.join(str(int.from_bytes(raw[i:i+4],'big')) for i in range(0,16,4))+':'+('some:'+zone if sep else 'none')

def words(text):return [x for x in re.split('[ \t]+',text) if x]
def fields(items):return ''.join(f'{len(x)}:{x}' for x in items)

def model(text,hostname,present,domains,environment_options):
    servers=[];search=None;options=[];sort=[];invalid=[];unknown=[]
    for line in text.split('\n'):
        if not line or line[0] in '#;':continue
        match=re.match(r'([^ \t]*)[ \t](.*)\Z',line,re.DOTALL)
        if not match:unknown.append(line);continue
        key,tail=match.groups();values=words(tail)
        if key=='nameserver':
            token=values[0] if values else '';value=address(token)
            if value is None:invalid.append(token)
            else:servers.append(value)
        elif key=='domain':
            if values:search=values[:1]
        elif key=='search':
            if values:search=values
        elif key=='options':options.extend(values)
        elif key=='sortlist':sort.extend(values)
        else:unknown.append(line)
    if present=='yes':search=words(domains)
    elif search is None:search=[hostname.partition('.')[2]] if '.' in hostname else []
    options.extend(words(environment_options))
    return (servers or ['4:2130706433'])+['search:'+fields(search),'options:'+fields(options),
         'sort:'+fields(sort),'invalid:'+fields(invalid),'unknown:'+fields(unknown)]

base=['','nameserver bad\nnameserver 0x','nameserver ::1\nnameserver 127.1\nnameserver ::1',
      'domain a\nsearch b c\ndomain final ignored\nsearch \n',
      'search a b\noptions ndots:1 rotate\noptions timeout:4\nsortlist 10/8\nsortlist 192.0/16\ncustom retained',
      '\n'.join('nameserver '+str(i) for i in range(1,9)),
      'nameserver fe80::1%lo\nsearch . root.test\noptions unsupported',
      'nameserver bad\n unknown x\nnameserver 1.2.3.4.\nunknown y']
cases=[]
for text in base:
    for hostname in ['', 'single', 'host.example.test', 'host.']:
        for present,domains in [('no','ignored'),('yes',''),('yes','override.test second.test')]:
            cases.append((text,hostname,present,domains,'ndots:5 attempts:3'))
rng=random.Random(6604)
lines=['nameserver 127.0.0.1','nameserver ::1','nameserver bad','domain one','search two three',
       'search ','options ndots:2','options timeout:9','options unknown','sortlist 10/8','custom x','#ignored']
for _ in range(150):
    cases.append(('\n'.join(rng.choices(lines,k=rng.randrange(1,40))),'host.default.test',rng.choice(['yes','no']),rng.choice(['','env.test','env1 env2']),'ndots:4'))
# Large ordered collections and replacing search directives use tail folds.
cases.append(('\n'.join(['nameserver 127.1','domain replaced','options rotate']*1000),'host.default','no','','timeout:5'))
rows=[]
for label,command in [('native 1',['build/resolver-settings','--threads','1']),('native 4',['build/resolver-settings','--threads','4']),('Bun',[str(bun),'build/resolver-settings.js'])]:
    for case in cases:
        run=subprocess.run([*command,*case],cwd=ROOT,capture_output=True,timeout=30)
        assert run.returncode==0 and not run.stderr,(label,run)
        got=run.stdout.decode().split('\n');assert got[-1]=='';got.pop()
        want=model(*case)
        assert got==want,(label,case,got,want)
    rows.append(dict(backend=label,cases=len(cases)));print(f'{label}: {len(cases)} settings cases PASS',flush=True)
paths=['packages/runtime/src/resolver-config.bend','packages/runtime/src/resolver-config.bend','packages/runtime/src/resolver-config.bend','tests/resolver-settings.bend','tests/resolver_settings_check.py','build/resolver-settings','build/resolver-settings.js']
(ROOT/'build/resolver-settings-result.json').write_text(json.dumps(dict(scope=__doc__,cases=rows,sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},builds={suffix:json.loads((ROOT/f'build/resolver-settings-{suffix}-build.json').read_text()) for suffix in ['c','js']}),indent=2)+'\n')

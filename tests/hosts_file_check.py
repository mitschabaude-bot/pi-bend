"""Strict hosts parsing and stable lookup; inet_pton supplies only address references."""
import hashlib
import ipaddress
import json
from pathlib import Path
import random
import re
import socket
import subprocess

ROOT=Path(__file__).resolve().parents[1]
bun=Path.home()/'.bun/bin/bun';compiler=Path.home()/'.bend/current/bend2'
for suffix in ['c','js']:
    with (ROOT/f'build/hosts-file-{suffix}.log').open('w') as log:
        subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/hosts-file-{suffix}-build.json','--',str(bun),str(compiler/'main.ts'),'tests/hosts-file.bend','-o',f'build/hosts-file.{suffix}'],cwd=ROOT,check=True,stdout=log,stderr=subprocess.STDOUT)
subprocess.run(['clang','-std=c11','-fbracket-depth=2048','-O1','build/hosts-file.c','-lpthread','-lm','-o','build/hosts-file'],cwd=ROOT,check=True)
def scalars(text):return ','.join(str(ord(x)) for x in text)
def fold(text):return text.translate(str.maketrans('ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz'))
def oracle(query,text):
    found=[]
    for number,line in enumerate(text.split('\n'),1):
        line=line.split('#',1)[0]
        invalid=next((ord(c) for c in line if (ord(c)<32 and c not in '\t\r\v\f') or ord(c)==127),None)
        if invalid is not None:return f'error:{number}:control:{invalid}'
        parts=re.findall(r'[^ \t\r\v\f]+',line)
        if not parts:continue
        if len(parts)==1:return f'error:{number}:name'
        address=None
        for family,size,prefix in [(socket.AF_INET,4,'4:'),(socket.AF_INET6,16,'6:')]:
            try:raw=socket.inet_pton(family,parts[0])
            except (OSError,ValueError):continue
            address=prefix+','.join(str(int.from_bytes(raw[i:i+4],'big')) for i in range(0,size,4));break
        if address is None:return f'error:{number}:address:{scalars(parts[0])}'
        if any(fold(query)==fold(name) for name in parts[1:]):
            found.append(address+'/'+scalars(parts[1])+'/'+''.join(scalars(x)+'|' for x in parts[2:])+';')
    return 'ok:'+''.join(found)

texts=['','# comment',' \t# comment\r\n','127.0.0.1 LocalHost alias ALIAS\n::1 localhost','127.0.0.1 a\n127.0.0.1 a',
       '127.0.0.1 a. a','127.0.0.1 café Ä\n::1 CAFé ä','127.0.0.1 a#inline\0comment',
       '\n127.0.0.1','127.0.0.1 a\ninvalid b\n::1 a','127.0.0.1 a\x00hidden','127.0.0.1 a\x01x','127.0.0.1 a\x7f',
       '\r\n127.0.0.1\ta\vb\fc\r\n::1 a', '127.0.0.1 a\nbad\ninvalid b']
addresses=['0','127.1','0177.0.0.1','0x7f.1','127.0.0.01','1.2.3.256','1.2.3.4.','[::1]','fe80::1%lo','::ffff:192.000.2.1','::ffff:192.0.2.1','::','255.255.255.255','1.2.3.4:53']
texts += [address+' a alias' for address in addresses]
rng=random.Random(84625)
for _ in range(128):
    rows=[]
    for _ in range(rng.randrange(1,7)):
        address=str(ipaddress.ip_address(rng.getrandbits(rng.choice([32,128]))))
        rows.append(rng.choice(['',' ','\t'])+address+rng.choice([' ','\t','\v','\f'])+rng.choice(['a','A','canonical'])+' '+rng.choice(['Alias','alias a','b','ä','a.'])+rng.choice(['',' # ignored','\r']))
    texts.append('\n'.join(rows))
cases=[(query,text) for text in texts for query in ['a','A','alias','LOCALHOST','a.','missing','Ä','ä']]
expected=[oracle(*case) for case in cases];checks=[]
for backend,cmd in [('native 1',['build/hosts-file','--threads','1']),('native 4',['build/hosts-file','--threads','4']),('Bun',[str(bun),'build/hosts-file.js'])]:
    for start in range(0,len(cases),32):
        batch=cases[start:start+32];args=[scalars(x) for pair in batch for x in pair]
        run=subprocess.run([*cmd,*args],cwd=ROOT,capture_output=True,text=True,timeout=30)
        assert run.returncode==0 and not run.stderr,(backend,run)
        assert run.stdout.splitlines()==expected[start:start+32],(backend,start,run.stdout,expected[start:start+32])
    checks.append(dict(backend=backend,cases=len(cases)));print(f'{backend}: {len(cases)} hosts cases PASS',flush=True)
sources=set()
def imports(path):
    path=path.resolve()
    if path in sources:return
    sources.add(path)
    for relative in re.findall(r'^import (\.[^\s]+)',path.read_text(),re.M):imports(path.parent/relative)
imports(ROOT/'tests/hosts-file.bend')
paths=sorted(str(p.relative_to(ROOT)) for p in sources)+['tests/hosts_file_check.py']
record=dict(scope=__doc__,checks=checks,seed=84625,sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},compiler_sha256={p:hashlib.sha256((compiler/p).read_bytes()).hexdigest() for p in ['main.ts','bend.ts','comp.ts','base.bend']},builds={s:json.loads((ROOT/f'build/hosts-file-{s}-build.json').read_text()) for s in ['c','js']})
(ROOT/'build/hosts-file-result.json').write_text(json.dumps(record,indent=2)+'\n')

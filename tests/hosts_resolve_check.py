"""Files-first routing: family/order retention, source errors and lazy network effects."""
import ast
import hashlib
import ipaddress
import json
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import random
import re
import socket
import subprocess

ROOT=Path(__file__).resolve().parents[1]
bun=Path.home()/'.bun/bin/bun'; compiler=TOOLCHAIN
for suffix in ['c','js']:
    with (ROOT/f'build/hosts-resolve-{suffix}.log').open('w') as log:
        subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/hosts-resolve-{suffix}-build.json','--',str(bun),str(compiler/'main.ts'),'tests/hosts-resolve.bend','-o',f'build/hosts-resolve.{suffix}'],cwd=ROOT,check=True,stdout=log,stderr=subprocess.STDOUT)
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'clang','-std=c11','-fbracket-depth=2048','-O1','build/hosts-resolve.c','-lpthread','-lm','-o','build/hosts-resolve'],cwd=ROOT,check=True)
# Reuse only the independent reference functions, without its eager builds.
source=ast.parse((ROOT/'tests/hosts_file_check.py').read_text())
functions=[node for node in source.body if isinstance(node,ast.FunctionDef) and node.name in {'scalars','fold','oracle'}]
exec(compile(ast.Module(body=functions,type_ignores=[]),'hosts-file-reference','exec'))

def expected(family,failure,name,text):
    result=oracle(name,text)
    if result.startswith('error:'):return [result]
    rows=[row for row in result[3:].split(';') if row]
    rows=[row for row in rows if family=='any' or row.startswith(family+':')]
    if rows:return ['hosts:'+''.join(row+';' for row in rows)]
    return ['query:'+family+':'+scalars(name),'network-error:73' if failure=='fail' else 'network:retained-network-report']

texts=['','# none','127.0.0.1 a A alias\n::1 a alias\n127.0.0.1 a',
       '::1 ONLY6 alias','127.0.0.1 ONLY4 alias','127.0.0.1 a.\n::1 a',
       '127.0.0.1 café Ä\n::1 CAFé ä','127.0.0.1 a\ninvalid later',
       '127.0.0.1 a\nmissing','127.0.0.1 a\x00hidden',
       '127.0.0.1 \\bad..name','127.0.0.1 a\n::ffff:192.0.2.1 a']
rng=random.Random(551902)
for _ in range(48):
    rows=[]
    for _ in range(rng.randrange(1,8)):
        address=str(ipaddress.ip_address(rng.getrandbits(rng.choice([32,128]))))
        rows.append(address+' '+rng.choice(['a','A','canonical'])+' '+rng.choice(['alias','a.','ä','a alias']))
    texts.append('\n'.join(rows))
cases=[(family,failure,name,text) for text in texts for family in ['any','4','6'] for failure in ['ok','fail'] for name in ['a','A','alias','ONLY4','ONLY6','a.','missing','Ä','ä','\\bad..name']]
checks=[]
for backend,cmd in [('native 1',['build/hosts-resolve','--threads','1']),('native 4',['build/hosts-resolve','--threads','4']),('Bun',[str(bun),'build/hosts-resolve.js'])]:
    for start in range(0,len(cases),24):
        batch=cases[start:start+24]
        args=[arg for family,failure,name,text in batch for arg in [family,failure,scalars(name),scalars(text)]]
        run=subprocess.run([*cmd,*args],cwd=ROOT,capture_output=True,text=True,timeout=30)
        wanted=[line for case in batch for line in expected(*case)]
        assert run.returncode==0 and not run.stderr,(backend,start,run)
        assert run.stdout.splitlines()==wanted,(backend,start,run.stdout,wanted)
    checks.append(dict(backend=backend,cases=len(cases)))
    print(f'{backend}: {len(cases)} hosts dispatch cases PASS',flush=True)
sources=set()
def imports(path):
    path=path.resolve()
    if path in sources:return
    sources.add(path)
    for relative in re.findall(r'^import (\.[^\s]+)',path.read_text(),re.M):imports(path.parent/relative)
imports(ROOT/'tests/hosts-resolve.bend')
paths=sorted(str(p.relative_to(ROOT)) for p in sources)+['tests/hosts_resolve_check.py','tests/hosts_file_check.py']
record=dict(scope=__doc__,checks=checks,seed=551902,sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},compiler_sha256={p:hashlib.sha256((compiler/p).read_bytes()).hexdigest() for p in ['main.ts','bend.ts','comp.ts','base.bend']},builds={s:json.loads((ROOT/f'build/hosts-resolve-{s}-build.json').read_text()) for s in ['c','js']})
(ROOT/'build/hosts-resolve-result.json').write_text(json.dumps(record,indent=2)+'\n')

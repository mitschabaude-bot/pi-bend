"""Real bounded hosts-file reads, explicit decoder selection, typed errors and closure."""
import ast
import errno
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
bun=Path.home()/'.bun/bin/bun';compiler=Path.home()/'.bend/current/bend2'
for suffix in ['c','js']:
    with (ROOT/f'build/hosts-load-{suffix}.log').open('w') as log:
        subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/hosts-load-{suffix}-build.json','--',str(bun),str(compiler/'main.ts'),'tests/hosts-load.bend','-o',f'build/hosts-load.{suffix}'],cwd=ROOT,check=True,stdout=log,stderr=subprocess.STDOUT)
# Reuse the existing fixture-fd audit, not the test module's build/execution.
tree=ast.parse((ROOT/'tests/resolver_file_check.py').read_text())
audit=next(ast.literal_eval(n.value) for n in tree.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='audit' for t in n.targets))
(ROOT/'build/hosts-load-audit.c').write_text((ROOT/'build/hosts-load.c').read_text()+audit)
subprocess.run(['clang','-std=c11','-fbracket-depth=2048','-O1','build/hosts-load-audit.c','-lpthread','-lm','-o','build/hosts-load'],cwd=ROOT,check=True)
# /proc fd inspection catches open fixture files on Bun as well as native.
js_audit='''import {readdirSync as auditList,readlinkSync as auditLink} from 'node:fs';
process.on('exit',()=>{let live=0;const root=process.env.PI_BEND_FILE_TEST_ROOT;
for(const fd of auditList('/proc/self/fd')) {try {const target=auditLink('/proc/self/fd/'+fd);if(target===root||target.startsWith(root+'/'))live++;}catch{}}
console.error('FILES '+live);});
'''
(ROOT/'build/hosts-load-audit.js').write_text(js_audit+(ROOT/'build/hosts-load.js').read_text())
# Pure parser/lookup reference from its test definition; omit all build code.
tree=ast.parse((ROOT/'tests/hosts_file_check.py').read_text());chosen=[n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name in ['scalars','fold','oracle']]
import socket
namespace=dict(re=re,socket=socket)
exec(compile(ast.Module(body=chosen,type_ignores=[]),'hosts-oracle','exec'),namespace)
model=namespace['oracle']
inputs=[b'',b'# comments\n',b'127.0.0.1 a alias\n::1 a\n',b'127.0.0.1 A\r\n127.0.0.2 a',b'127.0.0.1 a\ninvalid bad\n',b'127.0.0.1',b'127.0.0.1 a\x00hidden', '::1 café a\n'.encode(),b'127.0.0.1 a\n#'+b'x'*8192]
checks=[]
with tempfile.TemporaryDirectory(prefix='pi-bend-hosts-load-') as temp:
    root=Path(temp);env={**os.environ,'PI_BEND_FILE_TEST_ROOT':temp};cases=[]
    for i,data in enumerate(inputs):
        path=root/str(i);path.write_bytes(data)
        for chunk in [1,7,4096]:
            for limit in sorted({0,max(0,len(data)-1),len(data),len(data)+1}):
                for mode in ['decode','reject']:
                    wanted='large' if limit<len(data) else 'decode:selected decoder rejected input' if mode=='reject' else model('a',data.decode('utf-8','replace'))
                    cases.append(([mode,str(path),str(chunk),str(limit),'a'],wanted))
    for mode in ['decode','reject']:
        for path,chunk,want in [(root/'missing',7,'open:'+str(errno.ENOENT)),(root,7,'read:'+str(errno.EISDIR)),(root/'missing',0,'size')]:
            cases.append(([mode,str(path),str(chunk),'0','a'],want))
    for backend,command in [('native 1',['build/hosts-load','--threads','1']),('native 4',['build/hosts-load','--threads','4']),('Bun',[str(bun),'build/hosts-load-audit.js'])]:
        for index,(args,want) in enumerate(cases):
            run=subprocess.run([*command,*args],cwd=ROOT,env=env,capture_output=True,text=True,timeout=20)
            assert run.returncode==0 and run.stdout.splitlines()==[want] and run.stderr=='FILES 0\n',(backend,index,args,run,want)
        for mode in ['decode','reject']:
            pipe=root/f'pipe-{backend}-{mode}';os.mkfifo(pipe)
            keeper=os.open(pipe,os.O_RDWR|os.O_NONBLOCK)
            try:
                os.write(keeper,b'#x\n1234')
                run=subprocess.run([*command,mode,str(pipe),'7','0','a'],cwd=ROOT,env=env,capture_output=True,text=True,timeout=5)
                assert run.returncode==0 and run.stdout=='large\n' and run.stderr=='FILES 0\n',(backend,mode,'must stop without waiting for pipe EOF',run)
            finally:os.close(keeper)
        checks.append(dict(backend=backend,cases=len(cases),pipe_cases=2,early_stop_before_eof=True,fixture_fds_after=0));print(f'{backend}: {len(cases)} hosts file reads PASS',flush=True)
sources=set()
def imports(path):
    path=path.resolve()
    if path in sources:return
    sources.add(path)
    for relative in re.findall(r'^import (\.[^\s]+)',path.read_text(),re.M):imports(path.parent/relative)
imports(ROOT/'tests/hosts-load.bend')
paths=sorted(str(p.relative_to(ROOT)) for p in sources)+['tests/hosts_load_check.py','tests/hosts_file_check.py','tests/resolver_file_check.py']
record=dict(scope=__doc__,checks=checks,input_hex=[v.hex() for v in inputs],sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},compiler_sha256={p:hashlib.sha256((compiler/p).read_bytes()).hexdigest() for p in ['main.ts','bend.ts','comp.ts','base.bend']},builds={s:json.loads((ROOT/f'build/hosts-load-{s}-build.json').read_text()) for s in ['c','js']})
(ROOT/'build/hosts-load-result.json').write_text(json.dumps(record,indent=2)+'\n')

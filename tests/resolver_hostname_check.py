"""Lazy resolver hostname fallback with preserved failure diagnostics."""
import ctypes
import hashlib
import json
import os
from pathlib import Path
import re
import socket
import subprocess
ROOT=Path(__file__).resolve().parents[1]
bun=Path.home()/'.bun/bin/bun'
compiler=Path.home()/'.bend/current/bend2'
for suffix in ['c','js']:
    subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/resolver-hostname-{suffix}-build.json','--',str(bun),str(compiler/'main.ts'),'tests/resolver-hostname.bend','-o',f'build/resolver-hostname.{suffix}'],cwd=ROOT,check=True)
subprocess.run(['clang','-std=c11','-fbracket-depth=2048','-O1','build/resolver-hostname.c','-lpthread','-lm','-o','build/resolver-hostname'],cwd=ROOT,check=True)
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


def local_words(text):
    first=text.partition('\n')[0]
    result=words(first)
    return ([''] if not first or first[0] in ' \t' else [])+result

def expected(text,hostname,local,options):
    result=model(text,hostname,'no','','' if options is None else options)
    if local is not None:
        result=[('search:'+fields(local_words(local))) if line.startswith('search:') else line for line in result]
    return result

def environment(local,options):
    env={k:v for k,v in os.environ.items() if k not in ['LOCALDOMAIN','RES_OPTIONS']}
    if local is not None:env['LOCALDOMAIN']=local
    if options is not None:env['RES_OPTIONS']=options
    return env


files=['','nameserver bad','#ignored','domain \nsearch \n','domain file','search x y','domain old\nsearch final','search .']
cases=[(text,local,mode,name) for text in files for local in [None,'',' env','one two'] for mode in ['success','fail'] for name in ['host.domain','single','host.','']]
checks=[]
for backend,command in [('native 1',['build/resolver-hostname','--threads','1']),('native 4',['build/resolver-hostname','--threads','4']),('Bun',[str(bun),'build/resolver-hostname.js'])]:
    for i,(text,local,mode,name) in enumerate(cases):
        present=any(re.match(r'(domain|search)[ \t]+[^ \t\n]',line) for line in text.split('\n'))
        needed=local is None and not present
        used_name=name if needed and mode=='success' else ''
        want=(['called'] if needed else [])+expected(text,used_name,local,None)+['failure:5:hostname unavailable' if needed and mode=='fail' else 'none']
        run=subprocess.run([*command,text,'no' if local is None else 'yes',local or '',mode,name],cwd=ROOT,capture_output=True,timeout=15)
        assert run.returncode==0 and not run.stderr and run.stdout==('\n'.join(want)+'\n').encode(),(backend,i,run,want)
    checks.append(dict(backend=backend,cases=len(cases)))
    print(backend+': '+str(len(cases))+' lazy hostname cases PASS',flush=True)
paths=['packages/runtime/src/resolver-hostname.bend','tests/resolver-hostname.bend','tests/resolver_hostname_check.py']
r=dict(scope=__doc__,checks=checks,sha256={name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in paths},builds={suffix:json.loads((ROOT/f'build/resolver-hostname-{suffix}-build.json').read_text()) for suffix in ['c','js']})
(ROOT/'build/resolver-hostname-result.json').write_text(json.dumps(r,indent=2)+'\n')

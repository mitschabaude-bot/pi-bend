"""Resolver environment presence, grammar and error preservation."""
import ctypes
import hashlib
import json
import os
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import re
import socket
import subprocess
ROOT=Path(__file__).resolve().parents[1]
bun=Path.home()/'.bun/bin/bun'
compiler=TOOLCHAIN
fixtures=['resolver-environment','resolver-environment-source']
for fixture in fixtures:
    for suffix in ['c','js']:
        subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/{fixture}-{suffix}-build.json','--',str(bun),str(compiler/'main.ts'),f'tests/{fixture}.bend','-o',f'build/{fixture}.{suffix}'],cwd=ROOT,check=True)
    subprocess.run(['clang','-std=c11','-fbracket-depth=2048','-O1',f'build/{fixture}.c','-lpthread','-lm','-o',f'build/{fixture}'],cwd=ROOT,check=True)
subprocess.run(['cc','tests/resolver-environment-oracle.c','-lresolv','-o','build/resolver-environment-oracle'],cwd=ROOT,check=True)
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

locals=[None,'',' ','\t','one','one two','\t one\ttwo','one\nignored','\nignored','one\r two','x\v y','tést.域']
options=[None,'','rotate ndots:3',' timeout:4\tattempts:2','unknown\nvalue']
files=['','search file.test','domain file.one\noptions timeout:1']
cases=[(text,host,local,option) for text in files for host in ['host.default','bare'] for local in locals for option in options]
libc_rows=[]
for local in locals:
    if local is None:continue
    # Compare bytes to preserve embedded CR/vertical-tab rather than text-mode newline conversion.
    raw=subprocess.run(['build/resolver-environment-oracle'],cwd=ROOT,env=environment(local,''),capture_output=True,timeout=5)
    want=''.join(str(len(token.encode()))+':'+token+'\n' for token in local_words(local)).encode()
    assert raw.returncode==0 and not raw.stderr and raw.stdout==want,(local,raw,want)
    libc_rows.append(dict(local=local,domains=local_words(local)))
checks=[]
for backend in ['native 1','native 4','Bun']:
    def command(fixture):return [str(bun),f'build/{fixture}.js'] if backend=='Bun' else [f'build/{fixture}','--threads',backend.split()[-1]]
    for i,(text,host,local,option) in enumerate(cases):
        run=subprocess.run([*command('resolver-environment'),text,host],cwd=ROOT,env=environment(local,option),capture_output=True,timeout=15)
        want=('\n'.join(expected(text,host,local,option))+'\n').encode()
        assert run.returncode==0 and not run.stderr and run.stdout==want,(backend,i,run.stdout,want,run.stderr)
    for mode in ['normal','missing','empty','local-fail','options-fail','both-fail']:
        run=subprocess.run([*command('resolver-environment-source'),mode],cwd=ROOT,capture_output=True,timeout=15)
        if mode in ['local-fail','both-fail']:tail=['error:LOCALDOMAIN:13:lookup failed']
        elif mode=='options-fail':tail=['error:RES_OPTIONS:13:lookup failed']
        else:
            local,option={'normal':('one two','ndots:3'),'missing':(None,None),'empty':('','')}[mode]
            tail=expected('search file.test\noptions timeout:2','host.default',local,option)
        want=('\n'.join(['LOCALDOMAIN','RES_OPTIONS',*tail])+'\n').encode()
        assert run.returncode==0 and not run.stderr and run.stdout==want,(backend,mode,run,want)
    checks.append(dict(backend=backend,capture_and_precedence_cases=len(cases),injected_error_and_order_cases=6))
    print(backend+': '+str(len(cases))+' environment cases and 6 injected-source cases PASS',flush=True)
paths=['packages/runtime/src/resolver-config.bend','tests/resolver-environment.bend','tests/resolver-environment-source.bend','tests/resolver-environment-oracle.c','tests/resolver_environment_check.py']
r=dict(scope=__doc__,checks=checks,libc=libc_rows,reference='https://raw.githubusercontent.com/bminor/glibc/glibc-2.39/resolv/res_init.c',sha256={name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in paths},builds={f'{fixture}-{suffix}':json.loads((ROOT/f'build/{fixture}-{suffix}-build.json').read_text()) for fixture in fixtures for suffix in ['c','js']})
(ROOT/'build/resolver-environment-result.json').write_text(json.dumps(r,indent=2)+'\n')

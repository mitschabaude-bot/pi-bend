"""System settings loading with lazy OS/injected hostname discovery."""
import ctypes
import errno
import hashlib
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parents[1]
bun=Path.home()/'.bun/bin/bun'
compiler=ROOT/'build/bend-hostname-candidate'
for suffix in ['c','js']:
    subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/resolver-system-{suffix}-build.json','--',str(bun),str(compiler/'main.ts'),'tests/resolver-system.bend','-o',f'build/resolver-system.{suffix}'],cwd=ROOT,check=True)
audit='\n#include <unistd.h>\nstatic void __attribute__((destructor)) audit(void) {\n  const char* root=getenv("PI_BEND_FILE_TEST_ROOT");\n  unsigned live=0;\n  if(root) for(int fd=3;fd<512;fd++) {\n    char link[64], target[4096];\n    snprintf(link,sizeof(link),"/proc/self/fd/%d",fd);\n    ssize_t n=readlink(link,target,sizeof(target)-1);\n    if(n>=0) {\n      target[n]=0;\n      size_t len=strlen(root);\n      if(!strncmp(target,root,len) && (target[len]==0 || target[len]==\'/\')) live++;\n    }\n  }\n  fprintf(stderr,"FILES %u\\n",live);\n}\n'
(ROOT/'build/resolver-system-audit.c').write_text((ROOT/'build/resolver-system.c').read_text()+audit)
subprocess.run(['clang','-std=c11','-fbracket-depth=2048','-O1','build/resolver-system-audit.c','-lpthread','-lm','-o','build/resolver-system'],cwd=ROOT,check=True)
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

checks=[]
with tempfile.TemporaryDirectory(prefix='pi-bend-resolver-system-') as temp:
    root=Path(temp);cases=[]
    for index,text in enumerate(['','nameserver 127.1','search file.test','domain old\nsearch final','domain \nsearch \n']):
        path=root/str(index);path.write_text(text)
        configured=any(re.match(r'(domain|search)[ \t]+[^ \t\n]',line) for line in text.split('\n'))
        for local in [None,'',' env.test']:
            needed=local is None and not configured
            env=environment(local,'rotate');env['PI_BEND_FILE_TEST_ROOT']=temp
            for mode in ['mock','fail','system']:
                name=socket.gethostname() if mode=='system' else 'host.example'
                chosen=name if needed and mode!='fail' else ''
                want=(['called'] if needed and mode!='system' else [])+expected(text,chosen,local,'rotate')+['failure:5:hostname unavailable' if needed and mode=='fail' else 'none']
                for chunk in [1,4096]:
                    cases.append(([mode,str(path),str(chunk),str(len(text.encode())),'host.example'],env,want))
                    if text:cases.append(([mode,str(path),str(chunk),'0','host.example'],env,['large']))
    env=environment(None,None);env['PI_BEND_FILE_TEST_ROOT']=temp
    for mode in ['mock','fail','system','env-fail']:
        for path,chunk,error in [(root/'missing',7,'open:'+str(errno.ENOENT)),(root,7,'read:'+str(errno.EISDIR)),(root/'missing',0,'size')]:
            cases.append(([mode,str(path),str(chunk),'100','host.example'],env,['environment:LOCALDOMAIN:13' if mode=='env-fail' else error]))
    for backend,command in [('native 1',['build/resolver-system','--threads','1']),('native 4',['build/resolver-system','--threads','4']),('Bun',[str(bun),'build/resolver-system.js'])]:
        for index,(args,env,want) in enumerate(cases):
            run=subprocess.run([*command,*args],cwd=ROOT,env=env,capture_output=True,timeout=20)
            assert run.returncode==0 and run.stderr==(b'FILES 0\n' if backend!='Bun' else b'') and run.stdout==('\n'.join(want)+'\n').encode(),(backend,index,run,want)
        checks.append(dict(backend=backend,cases=len(cases),native_fixture_fds_after=0 if backend!='Bun' else None))
        print(backend+': '+str(len(cases))+' system settings loads PASS',flush=True)
paths=['packages/runtime/src/resolver-system.bend','packages/runtime/src/resolver-hostname.bend','tests/resolver-system.bend','tests/resolver_system_check.py']
r=dict(scope=__doc__,checks=checks,sha256={name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in paths},builds={suffix:json.loads((ROOT/f'build/resolver-system-{suffix}-build.json').read_text()) for suffix in ['c','js']})
(ROOT/'build/resolver-system-result.json').write_text(json.dumps(r,indent=2)+'\n')

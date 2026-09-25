"""Environment and bounded file settings load as one typed operation."""
import ctypes
import errno
import hashlib
import json
import os
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import re
import socket
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parents[1]
bun=Path.home()/'.bun/bin/bun'
compiler=TOOLCHAIN
for suffix in ['c','js']:
    subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/resolver-load-{suffix}-build.json','--',str(bun),str(compiler/'main.ts'),'tests/resolver-load.bend','-o',f'build/resolver-load.{suffix}'],cwd=ROOT,check=True)
audit='\n#include <unistd.h>\nstatic void __attribute__((destructor)) audit(void) {\n  const char* root=getenv("PI_BEND_FILE_TEST_ROOT");\n  unsigned live=0;\n  if(root) for(int fd=3;fd<512;fd++) {\n    char link[64], target[4096];\n    snprintf(link,sizeof(link),"/proc/self/fd/%d",fd);\n    ssize_t n=readlink(link,target,sizeof(target)-1);\n    if(n>=0) {\n      target[n]=0;\n      size_t len=strlen(root);\n      if(!strncmp(target,root,len) && (target[len]==0 || target[len]==\'/\')) live++;\n    }\n  }\n  fprintf(stderr,"FILES %u\\n",live);\n}\n'
(ROOT/'build/resolver-load-audit.c').write_text((ROOT/'build/resolver-load.c').read_text()+audit)
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'clang','-std=c11','-fbracket-depth=2048','-O1','build/resolver-load-audit.c','-lpthread','-lm','-o','build/resolver-load'],cwd=ROOT,check=True)
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
with tempfile.TemporaryDirectory(prefix='pi-bend-resolver-load-') as temp:
    root=Path(temp);cases=[]
    for index,text in enumerate(['','nameserver 127.1\nsearch file.test\noptions timeout:1','nameserver bad\ndomain old\nsearch last other\noptions unknown']):
        path=root/str(index);path.write_text(text)
        for local in [None,'',' env.test','one two\nignored']:
            for options in [None,'','rotate ndots:4']:
                for chunk in [1,4096]:
                    env=environment(local,options);env['PI_BEND_FILE_TEST_ROOT']=temp
                    cases.append((['read',str(path),str(chunk),str(len(text.encode())),'host.default'],env,expected(text,'host.default',local,options)))
                    if text:cases.append((['read',str(path),str(chunk),'0','host.default'],env,['large']))
    env=environment('override.test','rotate');env['PI_BEND_FILE_TEST_ROOT']=temp
    for mode,path,chunk,want in [('read',root/'missing',7,'open:'+str(errno.ENOENT)),('read',root,7,'read:'+str(errno.EISDIR)),('read',root/'missing',0,'size'),('fail',root/'missing',7,'environment:LOCALDOMAIN:13'),('fail',root/'missing',0,'environment:LOCALDOMAIN:13')]:
        cases.append(([mode,str(path),str(chunk),'100','host.default'],env,[want]))
    for backend,command in [('native 1',['build/resolver-load','--threads','1']),('native 4',['build/resolver-load','--threads','4']),('Bun',[str(bun),'build/resolver-load.js'])]:
        for index,(args,env,want) in enumerate(cases):
            run=subprocess.run([*command,*args],cwd=ROOT,env=env,capture_output=True,timeout=20)
            assert run.returncode==0 and run.stderr==(b'FILES 0\n' if backend!='Bun' else b'') and run.stdout==('\n'.join(want)+'\n').encode(),(backend,index,run,want)
        checks.append(dict(backend=backend,cases=len(cases),native_fixture_fds_after=0 if backend!='Bun' else None))
        print(backend+': '+str(len(cases))+' combined settings loads PASS',flush=True)
paths=['packages/runtime/src/resolver-config.bend','packages/runtime/src/resolver-config.bend','packages/runtime/src/resolver-config.bend','tests/resolver-load.bend','tests/resolver_load_check.py']
r=dict(scope=__doc__,checks=checks,sha256={name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in paths},builds={suffix:json.loads((ROOT/f'build/resolver-load-{suffix}-build.json').read_text()) for suffix in ['c','js']})
(ROOT/'build/resolver-load-result.json').write_text(json.dumps(r,indent=2)+'\n')

"""Bounded resolver file loading, explicit decoding, and settings precedence."""
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
compiler=Path.home()/'.bend/current/bend2'
for suffix in ['c','js']:
    subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/resolver-file-{suffix}-build.json','--',str(bun),str(compiler/'main.ts'),'tests/resolver-file.bend','-o',f'build/resolver-file.{suffix}'],cwd=ROOT,check=True)
audit='\n#include <unistd.h>\nstatic void __attribute__((destructor)) audit(void) {\n  const char* root=getenv("PI_BEND_FILE_TEST_ROOT");\n  unsigned live=0;\n  if(root) for(int fd=3;fd<512;fd++) {\n    char link[64], target[4096];\n    snprintf(link,sizeof(link),"/proc/self/fd/%d",fd);\n    ssize_t n=readlink(link,target,sizeof(target)-1);\n    if(n>=0) {\n      target[n]=0;\n      size_t len=strlen(root);\n      if(!strncmp(target,root,len) && (target[len]==0 || target[len]==\'/\')) live++;\n    }\n  }\n  fprintf(stderr,"FILES %u\\n",live);\n}\n'
(ROOT/'build/resolver-file-audit.c').write_text((ROOT/'build/resolver-file.c').read_text()+audit)
subprocess.run(['clang','-std=c11','-fbracket-depth=2048','-O1','build/resolver-file-audit.c','-lpthread','-lm','-o','build/resolver-file'],cwd=ROOT,check=True)
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


inputs=[b'',b'nameserver 127.1',b'nameserver ::1\nsearch one two\noptions rotate ndots:2\n',b'domain old\nsearch current other\noptions ndots:1\noptions timeout:3\n',b'nameserver bad\nnameserver 0x\nunknown saved',b'\xef\xbb\xbfnameserver 127.0.0.1\nsearch bom.test', 'search tést.域 local\n#😀\n'.encode(),b'search invalid-\xff\nunknown \xf0\x9f',b'nameserver fe80::1%lo\nsortlist 10/8\noptions unsupported',b'# comments\n; ignored\n',b'nameserver 127.1\noptions rotate\n'*300]
rows=[]
with tempfile.TemporaryDirectory(prefix='pi-bend-resolver-file-') as temp:
    root=Path(temp);environment={**os.environ,'PI_BEND_FILE_TEST_ROOT':temp};cases=[]
    for i,data in enumerate(inputs):
        path=root/str(i);path.write_bytes(data)
        for chunk in [1,3,31,4096]:
            for limit in sorted({0,max(0,len(data)-1),len(data),len(data)+1}):
                for present,domains in [('no','ignored'),('yes','override.test other')]:
                    for mode in ['decode','reject']:
                        args=[mode,str(path),str(chunk),str(limit),'host.default.test',present,domains,'attempts:3']
                        want=['large'] if limit<len(data) else ['decode:selected decoder rejected input'] if mode=='reject' else model(data.decode('utf-8','replace'),'host.default.test',present,domains,'attempts:3')
                        cases.append((args,want))
    for mode in ['decode','reject']:
        for path,chunk,want in [(root/'missing',7,'open:'+str(errno.ENOENT)),(root,7,'read:'+str(errno.EISDIR)),(root/'missing',0,'size'),(root/'0',0,'size')]:
            cases.append(([mode,str(path),str(chunk),'100','host.default','no','',''],[want]))
    for backend,command in [('native 1',['build/resolver-file','--threads','1']),('native 4',['build/resolver-file','--threads','4']),('Bun',[str(bun),'build/resolver-file.js'])]:
        for index,(args,want) in enumerate(cases):
            run=subprocess.run([*command,*args],cwd=ROOT,env=environment,capture_output=True,text=True,timeout=20)
            assert run.returncode==0 and run.stderr==('FILES 0\n' if backend!='Bun' else '') and run.stdout.splitlines()==want,(backend,index,args,run.returncode,run.stderr,run.stdout[:200],want[:3])
        rows.append(dict(backend=backend,cases=len(cases),native_fixture_fds_after=0 if backend!='Bun' else None))
        print(backend+': '+str(len(cases))+' resolver file cases PASS',flush=True)
paths=['packages/runtime/src/resolver-file.bend','packages/runtime/src/file-fold.bend','packages/runtime/src/resolver-config.bend','packages/runtime/src/resolver-settings.bend','tests/resolver-file.bend','tests/resolver_file_check.py']
r=dict(scope=__doc__,checks=rows,input_hex=[data.hex() for data in inputs],sha256={name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in paths},builds={suffix:json.loads((ROOT/f'build/resolver-file-{suffix}-build.json').read_text()) for suffix in ['c','js']})
(ROOT/'build/resolver-file-result.json').write_text(json.dumps(r,indent=2)+'\n')

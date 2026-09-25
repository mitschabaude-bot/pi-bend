"""Linux resolver open-error defaults, lazy hostname and strict failure boundaries."""
import errno
import hashlib
import json
import os
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import socket
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
bun = Path.home() / '.bun/bin/bun'
compiler = TOOLCHAIN
for suffix in ['c', 'js']:
    subprocess.run(['python3', 'scripts/run-rss-guarded.py', '--limit-gib', '16', '--stats', f'build/resolver-system-linux-{suffix}-build.json', '--', str(bun), str(compiler / 'main.ts'), 'tests/resolver-system-linux.bend', '-o', f'build/resolver-system-linux.{suffix}'], cwd=ROOT, check=True)
# Count only descriptors owned by this test's temporary filesystem tree.
audit = r'''
#include <unistd.h>
static void __attribute__((destructor)) audit(void) {
  const char *root=getenv("PI_BEND_FILE_TEST_ROOT"); unsigned live=0;
  if(root) for(int fd=3;fd<512;fd++) {
    char link[64], target[4096];
    snprintf(link,sizeof(link),"/proc/self/fd/%d",fd);
    ssize_t n=readlink(link,target,sizeof(target)-1);
    if(n>=0) {
      target[n]=0; size_t len=strlen(root);
      if(!strncmp(target,root,len) && (target[len]==0 || target[len]=='/')) live++;
    }
  }
  fprintf(stderr,"FILES %u\n",live);
}
'''
(ROOT/'build/resolver-system-linux-audit.c').write_text((ROOT/'build/resolver-system-linux.c').read_text()+audit)
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'clang','-std=c11','-fbracket-depth=2048','-O1','build/resolver-system-linux-audit.c','-lpthread','-lm','-o','build/resolver-system-linux'],cwd=ROOT,check=True)

allowed = {errno.EPERM, errno.ENOENT, errno.EACCES, errno.ENOTDIR, errno.EISDIR, errno.ELOOP}
def fields(values): return ''.join(f'{len(x)}:{x}' for x in values)
def settings(local, fail, unavailable, *, name='host.example', explicit=False, real=False):
    lookup = local is None and not explicit
    domains = ['file.test'] if explicit else ([name.partition('.')[2]] if lookup and not fail and '.' in name else [])
    if local is not None: domains = [''] if local == '' else ['env.test']
    return ((['called'] if lookup and not real else []) + ['4:2130706433', 'search:'+fields(domains),
        'options:'+fields((['ndots:3'] if explicit else [])+['rotate']), 'sort:', 'invalid:', 'unknown:',
        'failure:5:hostname unavailable' if lookup and fail else 'none', unavailable])

checks=[]
with tempfile.TemporaryDirectory(prefix='pi-bend-resolver-linux-') as temp:
    root=Path(temp); regular=root/'regular'; regular.write_text('search file.test\noptions ndots:3')
    empty=root/'empty'; empty.touch()
    denied=root/'denied'; denied.write_text('search hidden'); denied.chmod(0)
    loop=root/'loop'; loop.symlink_to(loop.name)
    cases=[]
    def add(args, local, want):
        env={k:v for k,v in os.environ.items() if k not in ['LOCALDOMAIN','RES_OPTIONS']}
        env.update(RES_OPTIONS='rotate',PI_BEND_FILE_TEST_ROOT=temp)
        if local is not None: env['LOCALDOMAIN']=local
        cases.append((args, env, want))
    for local in [None,'','env.test']:
        for fail in [False,True]:
            tail=['1','4096','fail' if fail else 'ok','host.example']
            for code in [*range(65),75,255,4294967295]:
                add(['open',str(code),*tail],local,settings(local,fail,f'file:unavailable:{code}:marker') if code in allowed else [f'open:{code}'])
                add(['read',str(code),*tail],local,[f'read:{code}'])
            for mode,want in [('size',['size']),('large',['large']),('decode',['decode:marker']),('success',settings(local,fail,'file:present',explicit=True))]:
                add([mode,'0',*tail],local,want)
            for path,code in [(root/'missing',errno.ENOENT),(regular/'child',errno.ENOTDIR),(denied,errno.EACCES),(loop,errno.ELOOP)]:
                add(['file',str(path),*tail],local,settings(local,fail,f'file:unavailable:{code}:os'))
            add(['file',str(root),*tail],local,[f'read:{errno.EISDIR}'])
            add(['file',str(regular),*tail],local,settings(local,fail,'file:present',explicit=True))
            add(['file',str(empty),'1','0',*tail[2:]],local,settings(local,fail,'file:present'))
            add(['file',str(regular),'1','0',*tail[2:]],local,['large'])
            add(['file',str(root/'missing'),'0','0',*tail[2:]],local,['size'])
            add(['env-fail',str(loop),*tail],local,['environment:LOCALDOMAIN:13'])
        add(['system',str(root/'missing'),'7','4096','ok','unused'],local,
            settings(local,False,f'file:unavailable:{errno.ENOENT}:os',name=socket.gethostname(),real=True))
    for backend,command in [('native 1',['build/resolver-system-linux','--threads','1']),('native 4',['build/resolver-system-linux','--threads','4']),('Bun',[str(bun),'build/resolver-system-linux.js'])]:
        for index,(args,env,want) in enumerate(cases):
            run=subprocess.run([*command,*args],cwd=ROOT,env=env,capture_output=True,timeout=20)
            assert run.returncode==0 and run.stderr==(b'FILES 0\n' if backend!='Bun' else b'') and run.stdout==('\n'.join(want)+'\n').encode(),(backend,index,args,run,want)
        checks.append(dict(backend=backend,cases=len(cases),fixture_owned_fds_after=0 if backend!='Bun' else None))
        print(f'{backend}: {len(cases)} Linux resolver fallback cases PASS',flush=True)
    denied.chmod(0o600)
paths=['packages/runtime/src/resolver-config.bend','tests/resolver-system-linux.bend','tests/resolver_system_linux_check.py']
result=dict(scope=__doc__,reference='https://raw.githubusercontent.com/bminor/glibc/glibc-2.39/resolv/res_init.c',checks=checks,sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},builds={suffix:json.loads((ROOT/f'build/resolver-system-linux-{suffix}-build.json').read_text()) for suffix in ['c','js']})
(ROOT/'build/resolver-system-linux-result.json').write_text(json.dumps(result,indent=2)+'\n')

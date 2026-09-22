"""Raw HOME, empty/unset HOME, passwd fallback and typed OS failures."""
import os
from pathlib import Path
import pwd
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PREFIX = ROOT / 'build/filesystem-paths'
C = r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <pwd.h>
#include <stdlib.h>
#include <unistd.h>
int getpwuid_r(uid_t uid,struct passwd *pw,char *buf,size_t size,struct passwd **out) {
  int (*real)(uid_t,struct passwd*,char*,size_t,struct passwd**)=dlsym(RTLD_NEXT,"getpwuid_r");
  if(uid!=geteuid()) return 22;
  int fault=atoi(getenv("BEND_HOME_FAULT"));
  if(fault==5) return 5;
  if(fault==2) { *out=NULL; return 0; }
  static int calls;
  if(fault==34 && calls++==0) return 34;
  return real(uid,pw,buf,size,out);
}
'''
JS = r'''
const ffi=require('bun:ffi'), dlopen=ffi.dlopen;
ffi.dlopen=function(...args) {
  const lib=dlopen(...args);
  if(!args[1].getpwuid_r) return lib;
  let calls=0;
  return {...lib,symbols:{...lib.symbols,getpwuid_r(uid,pw,buf,size,out) {
    if(uid!==process.geteuid()) return 22;
    const fault=Number(process.env.BEND_HOME_FAULT);
    if(fault===5) return 5;
    if(fault===2) { new BigUint64Array(ffi.toArrayBuffer(out,0,8))[0]=0n; return 0; }
    if(fault===34 && calls++===0) return 34;
    return lib.symbols.getpwuid_r(uid,pw,buf,size,out);
  }}};
};
'''
with tempfile.TemporaryDirectory(prefix='bend-home-') as directory:
    root=Path(directory)
    (root/'fault.c').write_text(C)
    (root/'fault.cjs').write_text(JS)
    subprocess.run(['cc','-shared','-fPIC',str(root/'fault.c'),'-ldl','-o',str(root/'fault.so')],check=True)
    expected=os.fsencode(pwd.getpwuid(os.geteuid()).pw_dir)
    homes=[b'',b'/',b'relative/../home/',os.fsencode(root/'nonexistent/é漢😀'),
           os.fsencode(root/'literal-�'),os.fsencode(root)+b'/raw-\xff',b'long/'+b'x'*8192,None]
    for name,command in [('bun',['bun',str(PREFIX)+'.js']),
                         ('native-1',[str(PREFIX),'--threads','1']),
                         ('native-4',[str(PREFIX),'--threads','4'])]:
        def run(home,operation,fault=0):
            env=os.environb.copy()
            env.pop(b'HOME',None)
            if home is not None: env[b'HOME']=home
            cmd=command.copy()
            if fault:
                env[b'BEND_HOME_FAULT']=str(fault).encode()
                if name=='bun': cmd[1:1]=['--preload',str(root/'fault.cjs')]
                else: env[b'LD_PRELOAD']=os.fsencode(root/'fault.so')
            p=subprocess.run(cmd+[operation],env=env,cwd=root,capture_output=True,text=True,timeout=20)
            assert p.returncode==0 and not p.stderr,(name,p.returncode,p.stderr)
            return p.stdout.strip()
        for home in homes:
            # Bun 1.4.0 panics parsing this generated fixture with oversized HOME.
            if name == 'bun' and home is not None and len(home) > 4095:
                continue
            value=expected if home is None else home
            assert run(home,'home-bytes')=='ok:'+','.join(map(str,value)),(name,home)
            try: result='ok:'+','.join(str(ord(c)) for c in value.decode())
            except UnicodeDecodeError: result='encoding'
            assert run(home,'home')==result,(name,home)
        for fault in [2,5]:
            assert run(None,'home-bytes',fault)==f'error:{fault}'
            assert run(None,'home',fault)==f'error:{fault}'
            assert run(b'','home-bytes',fault)=='ok:' # HOME takes precedence.
        assert run(None,'home-bytes',34)=='ok:'+','.join(map(str,expected))
        print(f'{name}: raw/empty/unset HOME, literal replacement character, passwd and errors PASS',flush=True)

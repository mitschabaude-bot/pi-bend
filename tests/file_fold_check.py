"""Owned chunked file fold: exact bytes, EOF/stop/errors, retained affine state."""
import errno
import hashlib
import json
import os
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import subprocess
import tempfile
import threading

ROOT=Path(__file__).resolve().parents[1]
BUN=Path.home()/'.bun/bin/bun'
COMPILER=TOOLCHAIN
for suffix in ['c','js']:
    subprocess.run(['python3','scripts/run-rss-guarded.py','--limit-gib','8','--stats',f'build/file-fold-{suffix}-build.json','--',str(BUN),str(COMPILER/'main.ts'),'tests/file-fold.bend','-o',f'build/file-fold.{suffix}'],cwd=ROOT,check=True)
audit = r"""
#include <unistd.h>
static void __attribute__((destructor)) audit(void) {
  const char* root=getenv("PI_BEND_FILE_TEST_ROOT");
  unsigned live=0;
  if(root) for(int fd=3;fd<512;fd++) {
    char link[64], target[4096];
    snprintf(link,sizeof(link),"/proc/self/fd/%d",fd);
    ssize_t n=readlink(link,target,sizeof(target)-1);
    if(n>=0) {
      target[n]=0;
      size_t len=strlen(root);
      if(!strncmp(target,root,len) && (target[len]==0 || target[len]=='/')) live++;
    }
  }
  fprintf(stderr,"FILES %u\n",live);
}
"""
(ROOT/'build/file-fold-audit.c').write_text((ROOT/'build/file-fold.c').read_text()+audit)
subprocess.run(['clang','-std=c11','-fbracket-depth=2048','-O1','build/file-fold-audit.c','-lpthread','-lm','-o','build/file-fold'],cwd=ROOT,check=True)

def rendered(status,chunks,data=b''):
    return status+':'+str(chunks)+':999,'+''.join(str(v)+',' for v in data)
checks=[]
with tempfile.TemporaryDirectory(prefix='pi-bend-file-fold-') as temp:
    root=Path(temp);cases=[]
    environment={**os.environ,'PI_BEND_FILE_TEST_ROOT':temp}
    for length in [0,1,2,7,31,1024,8192]:
        data=bytes(i%256 for i in range(length));p=root/str(length);p.write_bytes(data)
        for size in [1,2,7,256,4096]:
            for stop in [0,1,2]:
                chunks=(length+size-1)//size
                stopped=stop>0 and chunks>=stop
                read=min(length,size*stop) if stopped else length
                want=rendered('stopped' if stopped else 'eof',stop if stopped else chunks,data[:read])
                cases.append(([str(p),str(size),str(stop)],want))
    cases += [([str(root/'missing'),'7','0'],rendered('open:'+str(errno.ENOENT),0)),([str(root),'7','0'],rendered('read:'+str(errno.EISDIR),0)),([str(root/'8192'),'0','0'],rendered('size',0)),([str(root/'missing'),'0','0'],rendered('size',0))]
    cases += [([str(root/'31'),'7','1'],rendered('stopped',1,bytes(range(7))))]*256
    for backend,command in [('native 1',['build/file-fold','--threads','1']),('native 4',['build/file-fold','--threads','4']),('Bun',[str(BUN),'build/file-fold.js'])]:
        expected_stderr='FILES 0\n' if backend!='Bun' else ''
        for start in range(0,len(cases),16):
            batch=cases[start:start+16]
            run=subprocess.run([*command,*[arg for args,_ in batch for arg in args]],cwd=ROOT,env=environment,capture_output=True,text=True,timeout=30)
            assert run.returncode==0 and run.stderr==expected_stderr and run.stdout.splitlines()==[want for _,want in batch],(backend,start,run.returncode,run.stderr,run.stdout[:100])
        fifo=root/('fifo-'+backend.replace(' ','-'));os.mkfifo(fifo)
        release=threading.Event();written=threading.Event();errors=[]
        def writer():
            try:
                with fifo.open('wb',buffering=0) as out:
                    out.write(b'xy');written.set();release.wait(5)
            except BaseException as e:errors.append(repr(e))
        thread=threading.Thread(target=writer,daemon=True);thread.start()
        try:
            run=subprocess.run([*command,str(fifo),'1','2'],cwd=ROOT,env=environment,capture_output=True,text=True,timeout=3)
            assert written.is_set() and not errors and run.returncode==0 and run.stderr==expected_stderr and run.stdout.splitlines()==[rendered('stopped',2,b'xy')],(backend,run,errors)
        finally:
            release.set();thread.join(6)
        assert not thread.is_alive() and not errors,(backend,errors)
        checks.append(dict(backend=backend,file_cases=len(cases),early_stop_before_pipe_eof=True,native_fixture_fds_after=0 if backend!='Bun' else None))
        print(backend+': '+str(len(cases))+' file cases and live-pipe stop PASS',flush=True)
paths=['packages/runtime/src/file-fold.bend','tests/file-fold.bend','tests/file_fold_check.py']
r=dict(scope=__doc__,checks=checks,sha256={name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in paths},builds={suffix:json.loads((ROOT/f'build/file-fold-{suffix}-build.json').read_text()) for suffix in ['c','js']},compiler_sha256={name:hashlib.sha256((COMPILER/name).read_bytes()).hexdigest() for name in ['base.bend','comp.ts','bend.ts','main.ts']})
(ROOT/'build/file-fold-result.json').write_text(json.dumps(r,indent=2)+'\n')

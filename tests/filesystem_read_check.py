"""Raw filesystem reads and checked fold retirement under real OS failures.

Test-only hooks target temporary paths, close the real descriptor before
reporting close failure, and audit exactly-once close with no live handles.
"""
import argparse
import errno
import os
from pathlib import Path
import resource
import subprocess
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[1]
C = r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
static unsigned closes, calls[256];
static int retired[256];
static int option(const char *name) { const char *s=getenv(name); return s?atoi(s):0; }
static int target(int fd) {
  char link[64],path[4096]; snprintf(link,sizeof(link),"/proc/self/fd/%d",fd);
  ssize_t n=readlink(link,path,sizeof(path)-1); if(n<0)return 0; path[n]=0;
  const char *wanted=getenv("BEND_READ_PATH"); return wanted&&!strcmp(path,wanted);
}
ssize_t read(int fd,void *buf,size_t n) {
  ssize_t (*real)(int,void*,size_t)=dlsym(RTLD_NEXT,"read");
  if(target(fd)) {
    if(fd<0||fd>=256) _exit(91);
    calls[fd]++; retired[fd]=0;
    if(option("BEND_READ_FAIL") && calls[fd]>= (unsigned)option("BEND_READ_FAIL")) { errno=EIO; return -1; }
    unsigned cap=option("BEND_READ_CAP"); if(cap&&n>cap)n=cap;
  }
  return real(fd,buf,n);
}
int close(int fd) {
  int (*real)(int)=dlsym(RTLD_NEXT,"close");
  int hit=target(fd), retry=fd>=0&&fd<256&&retired[fd];
  int result=real(fd);
  if(hit||retry) {
    closes++; if(fd>=0&&fd<256) { retired[fd]=1; calls[fd]=0; }
    if(option("BEND_CLOSE_ERROR")) { errno=option("BEND_CLOSE_ERROR"); return -1; }
  }
  return result;
}
__attribute__((destructor)) static void audit(void) {
  unsigned live=0; for(int fd=0;fd<256;fd++)live+=target(fd);
  fprintf(stderr,"audit:%u:%u\n",closes,live);
}
'''
JS = r'''
const fs=require('fs');
const opened=new Set(), retired=new Set(), reads=new Map();
let closes=0;
const open=fs.openSync, close=fs.closeSync;
fs.openSync=function(path,...args) {
  const fd=open.call(this,path,...args);
  if(String(path)===process.env.BEND_READ_PATH) { opened.add(fd);retired.delete(fd);reads.set(fd,0); }
  return fd;
};
fs.closeSync=function(fd) {
  const hit=opened.delete(fd), retry=retired.has(fd);
  if(hit||retry) { closes++;retired.add(fd);reads.delete(fd); }
  const result=close.call(this,fd);
  if(hit&&Number(process.env.BEND_CLOSE_ERROR)) {
    const e=new Error('injected close failure');e.errno=-Number(process.env.BEND_CLOSE_ERROR);throw e;
  }
  return result;
};
// File.read_bytes uses libc through BEND_SYS, whereas checked close uses fs.
// Intercept initialization, preserving all real OS operations except the
// requested target read fault/short read and its corresponding errno.
let system;
Object.defineProperty(globalThis,'BEND_SYS',{configurable:true,get(){return system},set(value){
  system=value;const read=value.read, errno=value.errno;let injected=false;
  value.read=function(fd,ptr,n){
    injected=false;
    if(opened.has(fd)) {
      const count=(reads.get(fd)||0)+1;reads.set(fd,count);
      if(Number(process.env.BEND_READ_FAIL)&&count>=Number(process.env.BEND_READ_FAIL)) { injected=true;return -1; }
      if(Number(process.env.BEND_READ_CAP))n=Math.min(Number(n),Number(process.env.BEND_READ_CAP));
    }
    return read(fd,ptr,n);
  };
  value.errno=()=>injected?5:errno();
}});
process.on('exit',()=>process.stderr.write(`audit:${closes}:${opened.size}\n`));
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend', type=Path)
    parser.add_argument('--no-build', action='store_true')
    args = parser.parse_args()
    prefix = ROOT / 'build/filesystem-read'
    compiler = args.bend or Path(os.environ.get('BEND', str(ROOT / 'build/bend-native-toolchain/bend2/main.ts')))
    if not args.no_build:
        subprocess.run(['sh', 'scripts/build-pure.sh', 'tests/filesystem-read.bend', str(prefix)], cwd=ROOT,
                       env=dict(os.environ, BEND=str(compiler)), check=True)
        subprocess.run([str(compiler), 'tests/filesystem-read.bend', '-o', str(prefix)+'.js'], cwd=ROOT, check=True)
    with tempfile.TemporaryDirectory(prefix='bend-read-') as directory:
        root = Path(directory)
        (root/'fault.c').write_text(C)
        (root/'fault.cjs').write_text(JS)
        subprocess.run(['cc', '-shared', '-fPIC', '-O2', str(root/'fault.c'), '-ldl', '-o', str(root/'fault.so')], check=True)
        for backend, command in [('bun', ['bun', str(prefix)+'.js']),
                                 ('native-1', [str(prefix), '--threads', '1']),
                                 ('native-4', [str(prefix), '--threads', '4'])]:
            def run(path, mode='read', cap=0, read_fail=0, close_error=0, repeat=1):
                env = dict(os.environ, BEND_READ_PATH=str(path), BEND_READ_CAP=str(cap),
                           BEND_READ_FAIL=str(read_fail), BEND_CLOSE_ERROR=str(close_error))
                cmd = command.copy()
                if backend == 'bun':
                    cmd[1:1] = ['--preload', str(root/'fault.cjs')]
                else:
                    env['LD_PRELOAD'] = str(root/'fault.so')
                cmd += [mode, str(path)] * repeat
                def setup():
                    resource.setrlimit(resource.RLIMIT_NOFILE, (64, 64))
                result = subprocess.run(cmd, env=env, preexec_fn=setup, capture_output=True, text=True, timeout=30)
                assert result.returncode == 0, (backend, mode, result.returncode, result.stdout[:200], result.stderr)
                count = repeat if path.exists() else 0
                assert result.stderr == f'audit:{count}:0\n', (backend, mode, result.stderr)
                return result.stdout.splitlines()

            for length in [0, 1, 255, 65535, 65536, 65537, 131073]:
                data = bytes(i % 256 for i in range(length))
                path = root/f'{backend}-{length}'
                path.write_bytes(data)
                assert run(path) == ['ok:'+data.hex()]
            assert run(root/'missing') == ['error:'+str(errno.ENOENT)]
            assert run(root) == ['error:'+str(errno.EISDIR)]
            data = bytes(range(19))
            path = root/f'{backend}-fault'
            path.write_bytes(data)
            assert run(path, cap=2) == ['ok:'+data.hex()]
            # Failure after two nonempty short reads must still retire the file.
            for close_error in [0, errno.EIO, errno.EINTR]:
                read_status = 'error:5' if not close_error else f'read-close:5:{close_error}'
                assert run(path, cap=2, read_fail=3, close_error=close_error, repeat=128) == [read_status]*128
                fold_status = 'read:5' if not close_error else f'read-close:5:{close_error}'
                assert run(path, 'fold', cap=2, read_fail=3, close_error=close_error) == [f'{fold_status}:2:fa'+data[:4].hex()]
            for close_error in [errno.EIO, errno.EINTR]:
                assert run(path, close_error=close_error, repeat=128) == [f'error:{close_error}']*128
                assert run(path, 'fold', close_error=close_error) == [f'close:{close_error}:3:fa'+data.hex()]
                assert run(path, 'stop', close_error=close_error) == [f'close:{close_error}:1:fa'+data[:7].hex()]
            assert run(path, 'fold') == ['eof:3:fa'+data.hex()]
            assert run(path, 'stop') == ['stopped:1:fa'+data[:7].hex()]

            fifo = root/f'{backend}-pipe'
            os.mkfifo(fifo)
            errors = []
            def writer():
                try:
                    with fifo.open('wb', buffering=0) as stream:
                        for chunk in [b'\x00\xff', b'abc', bytes(range(64))]:
                            stream.write(chunk)
                except BaseException as error:
                    errors.append(repr(error))
            thread = threading.Thread(target=writer, daemon=True)
            thread.start()
            got = run(fifo, cap=2)
            thread.join(5)
            assert not thread.is_alive() and not errors, (backend, errors)
            assert got == ['ok:'+(b'\x00\xffabc'+bytes(range(64))).hex()]
            print(f'{backend}: exact bytes/EOF/boundaries/pipe, retained fold state, read+close errors and 640 failure retirements PASS', flush=True)


if __name__ == '__main__':
    main()

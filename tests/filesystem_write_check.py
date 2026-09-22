"""Filesystem write policy, umask parity, and injected OS close failures.

Faults close the real descriptor before reporting EIO/EINTR, ensuring callers
never retry a consumed handle. Hooks are test-only and target temporary files.
"""
import errno
import os
from pathlib import Path
import resource
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PREFIX = ROOT / 'build/filesystem-paths'
C = r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
static unsigned closes;
static int owned[64];
static int target(int fd) {
  char link[64], path[4096];
  snprintf(link,sizeof(link),"/proc/self/fd/%d",fd);
  ssize_t n=readlink(link,path,sizeof(path)-1);
  if(n<0) return 0;
  path[n]=0;
  const char *wanted=getenv("BEND_FAULT_PATH");
  return wanted && !strcmp(path,wanted);
}
ssize_t write(int fd,const void *buf,size_t n) {
  ssize_t (*real)(int,const void*,size_t)=dlsym(RTLD_NEXT,"write");
  if(target(fd) && atoi(getenv("BEND_FAULT"))==3) { errno=ENOSPC; return -1; }
  return real(fd,buf,n);
}
int close(int fd) {
  int (*real)(int)=dlsym(RTLD_NEXT,"close");
  int hit=target(fd),result=real(fd);
  if(hit && fd<64) owned[fd]=1;
  if(hit || (fd>=0 && fd<64 && owned[fd])) { closes++; errno=atoi(getenv("BEND_FAULT"))==2?EINTR:EIO; return -1; }
  return result;
}
__attribute__((destructor)) static void audit(void) {
  unsigned live=0;
  for(int fd=0;fd<64;fd++) live+=target(fd);
  fprintf(stderr,"audit:%u:%u\n",closes,live);
}
'''
JS = r'''
const fs = require('fs');
const opened = new Set();
let closes = 0;
const open = fs.openSync, close = fs.closeSync, write = fs.writeSync;
fs.openSync = function(path,...args) {
  const fd = open.call(this,path,...args);
  if(String(path) === process.env.BEND_FAULT_PATH) opened.add(fd);
  return fd;
};
function fail(code) { const e = new Error('injected OS failure'); e.errno = -code; throw e; }
fs.writeSync = function(fd,...args) {
  if(opened.has(fd) && process.env.BEND_FAULT === '3') fail(28);
  return write.call(this,fd,...args);
};
fs.closeSync = function(fd) {
  const hit = opened.delete(fd);
  const result = close.call(this,fd);
  if(hit) { closes++; fail(process.env.BEND_FAULT === '2' ? 4 : 5); }
  return result;
};
process.on('exit',() => process.stderr.write(`audit:${closes}:${opened.size}\n`));
'''

with tempfile.TemporaryDirectory(prefix='bend-write-') as directory:
    root = Path(directory)
    (root/'fault.c').write_text(C)
    (root/'fault.cjs').write_text(JS)
    subprocess.run(['cc','-shared','-fPIC','-O2',str(root/'fault.c'),'-ldl','-o',str(root/'fault.so')],check=True)
    for name,command in [('bun',['bun',str(PREFIX)+'.js']),
                         ('native-1',[str(PREFIX),'--threads','1']),
                         ('native-4',[str(PREFIX),'--threads','4'])]:
        def run(path, mask=0o027, fault=None, repeat=False):
            def setup():
                resource.setrlimit(resource.RLIMIT_NOFILE,(64,64))
                os.umask(mask)
            env=os.environ.copy()
            cmd=command.copy()
            if fault:
                env.update(BEND_FAULT_PATH=str(path),BEND_FAULT=str(fault))
                if name=='bun': cmd[1:1]=['--preload',str(root/'fault.cjs')]
                else: env['LD_PRELOAD']=str(root/'fault.so')
            cmd+=['repeat',str(path)] if repeat else ['write',str(path),'hello']
            p=subprocess.run(cmd,env=env,preexec_fn=setup,capture_output=True,text=True,timeout=30)
            assert p.returncode==0,(name,p.returncode,p.stdout,p.stderr)
            assert p.stderr==(f'audit:{128 if repeat else 1}:0\n' if fault else ''),(name,p.stderr)
            return p.stdout.splitlines()
        for mask in [0o002,0o027]:
            path=root/f'{name}-{mask}'
            assert run(path,mask)==['ok']
            assert path.stat().st_mode & 0o777 == 0o666 & ~mask
            path.chmod(0o604)
            assert run(path,mask)==['ok']
            assert path.stat().st_mode & 0o777 == 0o604
            assert path.read_text()=='hello'
        for fault,expected in [(1,'error:5'),(2,'error:4'),(3,'write-close:28:5')]:
            path=root/f'{name}-fault-{fault}'
            assert run(path,fault=fault,repeat=True)==[expected]*128
            assert path.read_bytes()==(b'' if fault==3 else b'x')
        print(f'{name}: creation modes, preserved permissions, checked close and dual failure PASS',flush=True)

#!/usr/bin/env python3
import argparse,errno,os,pathlib,subprocess,tempfile,threading
p=argparse.ArgumentParser();p.add_argument('command',nargs=argparse.REMAINDER);a=p.parse_args();command=a.command
if command[:1]==['--']:command=command[1:]
def run(*args):
 value=subprocess.run(command+list(map(str,args)),text=True,capture_output=True,timeout=30)
 assert value.returncode==0,value.stderr
 return value.stdout.splitlines()
with tempfile.TemporaryDirectory(prefix='bend-file-bytes-') as directory:
 root=pathlib.Path(directory);empty=root/'empty';empty.touch();binary=root/'β binary';binary.write_bytes(bytes(range(256)))
 for path in [empty,binary,root,pathlib.Path('/proc/self/status')]:
  n=path.stat().st_size;assert run('size',path)==[f'{n>>32}:{n&0xffffffff}']
 link=root/'link';link.symlink_to(binary);assert run('size',link)==['0:256']
 sparse=root/'sparse'
 with sparse.open('wb') as file:file.truncate(2**35+17)
 assert run('size',sparse)==['8:17']
 assert run('size',root/'missing')==[f'error:{errno.ENOENT}']
 assert run('nul',binary)==[f'error:{errno.EILSEQ}']
 for count in [0,1,255,256,65537,1048576]:
  assert run('write',binary,'w',count)==['ok','ok']
  assert binary.read_bytes()==bytes(range(256))*(count//256)+bytes(range(count%256))
 assert run('retain',binary)==[f'error:{errno.EINVAL}','ok','ok'];assert binary.read_bytes()==b'\0\xff\xc3'
 assert run('write',binary,'r',3)==[f'error:{errno.EBADF}','ok'];assert binary.read_bytes()==b'\0\xff\xc3'
 assert run('write','/dev/full','w',3)==[f'error:{errno.ENOSPC}','ok']
 exclusive=root/'exclusive'
 assert run('write',exclusive,'wx',3)==['ok','ok'];assert exclusive.read_bytes()==b'\0\1\2'
 assert run('write',exclusive,'wx',5)==[f'open:{errno.EEXIST}'];assert exclusive.read_bytes()==b'\0\1\2'
 assert exclusive.stat().st_mode&0o777==0o600
 # A real pipe drains far more than its capacity, preserving arbitrary bytes.
 fifo=root/'fifo';os.mkfifo(fifo);received=bytearray()
 def read_fifo():
  with fifo.open('rb',buffering=0) as file:
   while chunk:=file.read(997):received.extend(chunk)
 thread=threading.Thread(target=read_fifo);thread.start()
 assert run('write',fifo,'w',1048576)==['ok','ok'];thread.join(10);assert not thread.is_alive()
 assert received==bytes(range(256))*4096
 # Deterministic OS-boundary short-write/EINTR/zero-progress behavior.
 shim=pathlib.Path('build/filesystem-write-fragments.so').resolve()
 subprocess.run(['clang','-shared','-fPIC','tests/filesystem-write-fragments.c','-ldl','-o',str(shim)],check=True)
 fault_command=command[:]
 is_bun=pathlib.Path(command[0]).name=='bun'
 if is_bun:fault_command[1:1]=['--preload',str(pathlib.Path('tests/filesystem-write-fragments.cjs').resolve())]
 for zero in [False,True]:
  target=root/'fragmented';environment=os.environ.copy();environment['BEND_TEST_WRITE_PATH']=str(target)
  if not is_bun:environment['LD_PRELOAD']=str(shim)
  if zero:environment['BEND_TEST_WRITE_ZERO']='1'
  value=subprocess.run(fault_command+['write',str(target),'w','256'],text=True,capture_output=True,env=environment,timeout=30)
  assert value.returncode==0,value.stderr
  assert value.stdout.splitlines()==([f'error:{errno.EIO}','ok'] if zero else ['ok','ok']),value.stdout
  assert target.read_bytes()==(b'' if zero else bytes(range(256)))
print('PASS exact stat sizes, binary writes, empty/large/FIFO, errors with retained handles, exclusive creation, and partial/EINTR/zero-progress writes')

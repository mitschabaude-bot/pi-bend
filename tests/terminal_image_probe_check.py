#!/usr/bin/env python3
"""Native stdout selection, real tmux probing and owned process retirement."""
import argparse,base64,os,subprocess,tempfile,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--probe',type=Path,default=ROOT/'build/terminal-image-state');p.add_argument('--child',type=Path,default=ROOT/'build/image-child-execute');a=p.parse_args()
for threads in [1,4]:
 child=[str(a.child.resolve()),'--threads',str(threads)]
 def run(command,timeout='none',count=1):
  start=time.monotonic();r=subprocess.run(child+['stdout',timeout,'0','/bin/sh','/tmp',command,str(count)],text=True,capture_output=True,timeout=8)
  assert r.returncode==0 and not r.stderr,(r.stdout,r.stderr)
  lines=r.stdout.splitlines();out=b''.join(base64.b64decode(x[5:]) for x in lines if x.startswith('data '));outcomes=[x[7:] for x in lines if x.startswith('result ')]
  return out,outcomes,time.monotonic()-start
 assert run('printf stdout; printf stderr >&2; exit 7')[:2]==(b'stdout',['exit:7'])
 assert run('head -c 131072 /dev/zero >&2; printf ready')[:2]==(b'ready',['exit:0'])
 assert run("printf '\\000\\377'; printf ignored >&2")[:2]==(b'\0\xff',['exit:0'])
 assert run('printf ignored >&2')[:2]==(b'',['exit:0'])
 assert run('while :; do printf ignored >&2; done',timeout='0.03')[1]==['timeout']
 out,status,elapsed=run('(i=0; while [ "$i" -lt 8 ]; do printf ignored >&2; i=$((i+1)); sleep .04; done; sleep .5) & exit 0')
 assert out==b'' and status==['exit:0'] and .25<elapsed<.75,elapsed
 assert run('printf x; printf y >&2',count=50)[:2]==(b'x'*50,['exit:0']*50)
 with tempfile.TemporaryDirectory(prefix='pi-bend-tmux-') as d:
  directory=Path(d);script=directory/'tmux';env={**os.environ,'PATH':d+':/usr/bin:/bin'}
  cases=[("printf 'RGB,hyperlinks,clipboard'",True),("printf 'RGB'; printf ',hyperlinks' >&2",False),("printf ' hyper'; sleep .02; printf 'links \\n'",True),("printf 'RGB,\\302\\240hyperlinks\\302\\240'",True),("printf 'not-hyperlinks,hyperlinks-extra'",False),("printf hyperlinks; exit 1",False),("sleep 1; printf hyperlinks",False),("head -c 131072 /dev/zero >&2; printf hyperlinks",True),("printf '\\377,hyperlinks'",False),("head -c 1048577 /dev/zero; printf ,hyperlinks",False)]
  for body,expected in cases:
   script.write_text('#!/bin/sh\n'+body+'\n');script.chmod(0o700)
   start=time.monotonic();r=subprocess.run([str(a.probe.resolve()),'--threads',str(threads),'probe',d],env=env,text=True,capture_output=True,timeout=3)
   assert r.returncode==0 and not r.stderr,(body,r.stdout,r.stderr)
   assert r.stdout.strip()==str(expected).lower(),(body,r.stdout,expected)
   assert time.monotonic()-start<1.0,body
  script.unlink()
  r=subprocess.run([str(a.probe.resolve()),'--threads',str(threads),'probe',d],env={**env,'PATH':d},text=True,capture_output=True,timeout=3)
  assert r.returncode==0 and r.stdout.strip()=='false' and not r.stderr
 print(f'native-{threads}: 7 stdout-selection scenarios (50 repeats), 11 real tmux probe cases passed')

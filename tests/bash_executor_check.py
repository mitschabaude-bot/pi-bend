"""User Bash execution oracle, stream-boundary corrections and owned cleanup."""
import argparse,json,os,random,subprocess,tempfile
from pathlib import Path
from output_accumulator_fault_check import hooks
ROOT=Path(__file__).resolve().parents[1]
def text(s):return ','.join(str(ord(c)) for c in s)
def unwire(s):return ''.join(chr(int(x)) for x in s.split(',') if x)
def chunks_arg(chunks):return ';'.join(','.join(map(str,b)) for b in chunks)
def main():
 p=argparse.ArgumentParser();p.add_argument('--runner',required=True);p.add_argument('--threads',default='1');a=p.parse_args()
 runner=['bun',a.runner] if a.runner.endswith('.js') else [a.runner,'--threads',a.threads]
 rng=random.Random(754);cases=[]
 for value in ['', 'plain','\x1b[31mred\x1b[0m\r\n','a\x00b\x01c\t\n','\ufeffBOM','\x1b[31m\ufefftext','\x1b]8;;link\x07name\x1b]8;;\x07','é🐍\ufff9\r\n']:
  for mode,exit in [('normal','0'),('normal','7'),('normal','none'),('normal','fail'),('cancel','0'),('cancel','fail')]:cases.append(dict(mode=mode,exit=exit,chunks=[list(value.encode())]))
 for _ in range(35):
  value=''.join(rng.choices(['abc','é🐍','\x1b[31mcolor\x1b[0m','\r\n','\x00'],k=12))
  cases.append(dict(mode='normal',exit='0',chunks=[list(value.encode())]))
 with tempfile.TemporaryDirectory() as tmp:
  env=dict(os.environ,TMPDIR=tmp);path=Path(tmp)/'cases.json';path.write_text(json.dumps(cases))
  expected=[json.loads(x) for x in subprocess.check_output(['bun',str(ROOT/'tests/bash_executor_reference.ts'),str(ROOT.parent/'pi-mono/packages/coding-agent/src'),str(path)],text=True,env=env).splitlines()]
  def run(mode,exit,chunks):
   arg=chunks if isinstance(chunks,str) else chunks_arg(chunks)
   r=subprocess.run([*runner,mode,exit,arg],capture_output=True,text=True,env=env,timeout=60)
   assert r.returncode==0 and not r.stderr,(mode,arg[:100],r.returncode,r.stdout[:1000],r.stderr)
   rows=r.stdout.splitlines();assert len(rows)==2,rows[:5]
   f=rows[0].split('|');seen=unwire(rows[1].removeprefix('chunks|'))
   if f[0]=='ok':
    full=None
    if f[5]!='none':
     name=Path(unwire(f[5]));full=name.read_text();assert name.stat().st_mode&0o777==0o600;name.unlink()
    return dict(output=unwire(f[1]),exit=None if f[2]=='none' else int(f[2]),cancelled=f[3]=='1',truncated=f[4]=='1',full=full,chunks=seen)
   return dict(error=unwire(f[1]),chunks=seen,kind=f[0])
  for c,e in zip(cases,expected):
   got=run(c['mode'],c['exit'],c['chunks']);got.pop('kind',None);assert got==e,(c,got,e)
  # Partition invariance: ANSI and UTF8 sequences may span every byte boundary.
  value='start\x1b[38:2::1:2:3mredé🐍\x1b[0m\x1b]8;;url\x1b\\link\x1b]8;;\x07\r\n'
  raw=value.encode();clean='startredé🐍link\n'
  partitions=len(raw)+1
  for cut in range(partitions):
   got=run('normal','0',[list(raw[:cut]),list(raw[cut:])]);assert got['output']==clean and got['chunks']==clean,got
  got=run('normal','0',[[b] for b in raw]);assert got['output']==clean and got['chunks']==clean,got
  for raw,want in [(b'abc\xf0\x9f','abc\ufffd'),(b'a\x1b]unfinished','a]unfinished'),(b'a\x1b[123','a[123')]:
   got=run('normal','0',[[b] for b in raw]);assert got['output']==want and got['chunks']==want,got
  for mode in ['normal','silent','cancel']:
   got=run(mode,'0','lines');assert got['output']==('line\n'*2000).rstrip('\n') and got['full']=='line\n'*3000 and got['truncated'],got
   assert got['chunks']==('' if mode=='silent' else 'line\n'*3000)
  got=run('normal','0','ansi-large');assert got['output']=='' and got['full']=='' and not got['truncated'] and got['chunks']=='',got
  got=run('normal','0','large');assert got['full']=='abcd\n'*15000 and got['output']==('abcd\n'*2000).rstrip('\n') and got['truncated'],got
  got=run('normal','0',[[9]*51201]);assert got['output']=='\t'*51200 and got['full']=='\t'*51201 and got['truncated'] and got['chunks']==got['full']
  got=run('reentry','0',[[65]]);assert got['output']=='A'+'R'*1000 and got['chunks']==got['output'],got
  got=run('normal','0',[[256]]);assert got['kind']=='output' and 'Invalid output byte' in got['error'],got
  local_cases=[] if a.runner.endswith('.js') else [("printf '\\033[31mred\\033[0m\\r\\n'",'red\n'),('seq 3000',None)]
  for shell_command,wanted in local_cases:
   proc=subprocess.run([*runner,'native',shell_command],capture_output=True,text=True,env=env,timeout=30)
   assert proc.returncode==0 and not proc.stderr,(proc.returncode,proc.stderr)
   f=proc.stdout.splitlines()[0].split('|');assert f[0]=='ok' and f[2]=='0',f[:1]
   if wanted is not None:assert unwire(f[1])==wanted,unwire(f[1])
   else:
    assert f[4]=='1' and unwire(f[1])=='\n'.join(map(str,range(1001,3001)))
    path=Path(unwire(f[5]));assert path.read_text()==''.join(str(n)+'\n' for n in range(1,3001));path.unlink()
  c,js=hooks();base=Path(tmp);(base/'fault.c').write_text(c);(base/'fault.cjs').write_text(js)
  subprocess.run(['cc','-shared','-fPIC','-O2',str(base/'fault.c'),'-ldl','-o',str(base/'fault.so')],check=True)
  for fault in ['1','2','3']:
   fault_env=dict(env,BEND_FAULT_PATH=tmp+'/pi-bash-',BEND_FAULT=fault);command=runner.copy()
   if a.runner.endswith('.js'):command[1:1]=['--preload',str(base/'fault.cjs')]
   else:fault_env['LD_PRELOAD']=str(base/'fault.so')
   proc=subprocess.run([*command,'silent','0','large'],capture_output=True,text=True,env=fault_env,timeout=30)
   assert proc.returncode==0 and proc.stderr=='audit:1:0\n',(proc.returncode,proc.stderr)
   failure=proc.stdout.splitlines()[0].split('|');assert failure[0]=='output',failure
   message=unwire(failure[1]);assert ('close:' in message if fault=='3' else ('(5)' if fault=='1' else '(4)') in message),message
   paths=list(base.glob('pi-bash-*.log'));assert len(paths)==1,paths
   assert paths[0].read_bytes()==(b'' if fault=='3' else b'abcd\n'*15000);paths[0].unlink()
  before=set(base.glob('pi-bash-*.log'))
  failed=run('silent','fail','lines');assert failed['kind']=='exec',failed
  assert set(base.glob('pi-bash-*.log'))==before
  missing=dict(env,TMPDIR=tmp+'/missing')
  proc=subprocess.run([*runner,'silent','fail','large'],capture_output=True,text=True,env=missing,timeout=30)
  assert proc.returncode==0 and proc.stdout.startswith('both|') and not proc.stderr,(proc.returncode,proc.stdout,proc.stderr)
 print(f'{len(cases)} pinned cases; {partitions} partition variants, EOF, sanitized spill, cancellation, reentry and late-alias checks passed')
if __name__=='__main__':main()

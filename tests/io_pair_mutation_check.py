"""Ensure barrier and resource audits detect typed sequential and unjoined-channel mutations."""
from channel_audit import instrument
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
bun=Path.home()/'.bun/bin/bun';compiler=Path.home()/'.bend/current/bend2'
sources=set()
def imports(path):
 path=path.resolve()
 if path in sources:return
 sources.add(path)
 for relative in re.findall(r'^import (\.[^\s]+)',path.read_text(),re.M):imports(path.parent/relative)
imports(ROOT/'tests/io-pair.bend')
original=(ROOT/'packages/runtime/src/io-pair.bend').read_text()
sequential=original[:original.index('  do IO<Left & Right>:')]+'''  do IO<Left & Right>:
    leftValue : Left <- left
    rightValue : Right <- right
    return (leftValue, rightValue)
'''
helper='''def taken(-A: Type, value: Maybe<&1, A>) -> IO(A):
  match value:
    case Some{value}: IO.pure(A, value)
    case None{}: IO.die(A, 1, "closed child")

def receive(-A: Type, channel: Chan(A)) -> IO(A):
  do IO<A>:
    value : Maybe<&1, A> <- Chan.recv(A, channel)
    taken(A, value)

'''
leak=original.replace('def both(',helper+'def both(',1).replace('IO.join(Right, rightTask)','receive(Right, rightTask)')
rows=[]
with tempfile.TemporaryDirectory(prefix='io-pair-mutations-',dir=ROOT/'build') as temporary:
 directory=Path(temporary)
 for source in sources:
  destination=directory/source.relative_to(ROOT);destination.parent.mkdir(parents=True,exist_ok=True);destination.write_bytes(source.read_bytes())
 for label,mutation in [('sequential',sequential),('unclosed-child-channel',leak)]:
  (directory/'packages/runtime/src/io-pair.bend').write_text(mutation)
  check=subprocess.run([str(bun),str(compiler/'main.ts'),'packages/runtime/src/io-pair.bend'],cwd=directory,capture_output=True,text=True,timeout=30)
  assert check.returncode==0 and 'All terms check' in check.stdout,(label,check)
  for suffix in ['c','js']:
   with (ROOT/f'build/io-pair-mutation-{label}-{suffix}.log').open('w') as log:
    subprocess.run(['python3',str(ROOT/'scripts/run-rss-guarded.py'),'--limit-gib','8','--stats',str(ROOT/f'build/io-pair-mutation-{label}-{suffix}-build.json'),'--',str(bun),str(compiler/'main.ts'),'tests/io-pair.bend','-o',f'pair.{suffix}'],cwd=directory,check=True,stdout=log,stderr=subprocess.STDOUT)
  with (directory/'pair.c').open('a') as output:output.write('''\nstatic void __attribute__((destructor)) pair_audit(void) {unsigned live=0;for(u32 i=0;i<chan_len;i++)live+=chan_rows[i].live;fprintf(stderr,"AUDIT %u\\n",live);}\n''')
  subprocess.run(['clang','-std=c11','-fbracket-depth=2048','-O1','pair.c','-lpthread','-lm','-o','pair'],cwd=directory,check=True)
  (directory/'pair.js').write_text(instrument((directory/'pair.js').read_text()))
  for backend,command in [('native 1',[str(directory/'pair'),'--threads','1']),('native 4',[str(directory/'pair'),'--threads','4']),('Bun',[str(bun),str(directory/'pair.js')])]:
   try:run=subprocess.run([*command,'L','ok','fail'],cwd=directory,capture_output=True,text=True,timeout=2)
   except subprocess.TimeoutExpired:
    assert label=='sequential',backend
    rows.append(dict(mutation=label,backend=backend,rejection='barrier timeout',module_check=check.stdout.strip()))
   else:
    if label=='sequential':
     assert run.returncode!=0 and not run.stdout and 'deadlock' in run.stderr,(backend,run)
     rows.append(dict(mutation=label,backend=backend,rejection='runtime deadlock diagnostic',stderr=run.stderr,module_check=check.stdout.strip()))
     continue
    assert label=='unclosed-child-channel',(label,backend,run.stdout,run.stderr)
    assert run.returncode==0 and run.stdout.splitlines()==['value:L/error:73','LR'],(backend,run)
    assert run.stderr==('AUDIT 1 0 0\n' if backend=='Bun' else 'AUDIT 1\n'),(backend,run.stderr)
    rows.append(dict(mutation=label,backend=backend,rejection=run.stderr.strip(),module_check=check.stdout.strip()))
  print(label+': rejected on native one/four threads and Bun',flush=True)
paths=sorted(str(p.relative_to(ROOT)) for p in sources)+['tests/io_pair_mutation_check.py','tests/channel_audit.py']
(ROOT/'build/io-pair-mutation-result.json').write_text(json.dumps(dict(scope=__doc__,checks=rows,mutations={'sequential':sequential,'unclosed-child-channel':leak},sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths},compiler_sha256={p:hashlib.sha256((compiler/p).read_bytes()).hexdigest() for p in ['main.ts','bend.ts','comp.ts','base.bend']}),indent=2)+'\n')

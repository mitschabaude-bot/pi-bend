"""Orphan repair, interruptions and system-message ordering against pinned Pi."""
import itertools,json,random,subprocess
from pathlib import Path
from schema_literals import string
ROOT=Path(__file__).resolve().parents[1];BUILD=ROOT/'build'
tokens=['u','s','a0','a1','a2','a12','a11','error','aborted','r1','r2','rx']
cases=[list(x) for length in range(3) for x in itertools.product(tokens,repeat=length)]
cases += [['a12','s','r1','s'],['a12','s','r2','r1','s','u'],['a1','s','error','r1'],['a1','s','aborted','u'],['r1','a1'],['a1','r1','a1'],['a12','r1','r1','s','u'],['s','a1','s','s','r1','s'],['a11','s','u'],['a11','r1'],['a1','s','rx','r1'],['a12','s','a2','s','r2']]
rng=random.Random(854412)
cases += [[rng.choice(tokens) for _ in range(rng.randrange(3,11))] for _ in range(240)]
expected=json.loads(subprocess.check_output(['node','tests/transform_tool_results_reference.mts'],input=json.dumps(cases),text=True,cwd=ROOT))
def values(items):return ' <> '.join([*[string(x) for x in items],'Nil{}'])
lines=['import Base','import ../packages/ai/test/api/transform-tool-results.bend as T']
for i,(case,result) in enumerate(zip(cases,expected,strict=True)):
    lines += [f'def case{i}() -> IO(Unit):',f'  T.check({values(case)}, {values(result)}, "repair {i}")']
groups=[]
for start in range(0,len(cases),60):
    name=f'group{start}';groups.append(name)
    lines += [f'def {name}() -> IO(Unit):','  do IO<Unit>:']+[f'    case{i}()' for i in range(start,min(start+60,len(cases)))]
lines += ['def main() -> IO(Unit):','  do IO<Unit>:']+[f'    {name}()' for name in groups]+[f'    IO.print("PASS {len(cases)} typed tool-result repair transcripts")']
src=BUILD/'transform-tool-results-check.bend';src.write_text('\n'.join(lines)+'\n');out=BUILD/'transform-tool-results-check'
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh','scripts/build-pure.sh',str(src),str(out)],cwd=ROOT,check=True)
for threads in ['1','4']:subprocess.run([str(out),'--threads',threads],cwd=ROOT,check=True,timeout=120)

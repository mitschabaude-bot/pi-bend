"""Sequential scheduling boundaries against the original executeToolCallsSequential."""
import itertools,json,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];BUILD=ROOT/'build'
cases=[]
for size in range(5):
    for flags in itertools.product([False,True],repeat=size):
        for stop in range(size+2):
            for fail in range(size+1):
                calls=[dict(id=i+1,terminate=flag,fail=(i+1==fail),immediate=(i%2==0)) for i,flag in enumerate(flags)]
                cases.append(dict(initial=10,calls=calls,stopAfter=stop))
expected=json.loads(subprocess.check_output(['node','tests/tool_batch_sequential_reference.mjs'],input=json.dumps(cases),text=True,cwd=ROOT))
def flag(v):return 'True{}' if v else 'False{}'
def seq(xs):return ''.join(str(x)+' <> ' for x in xs)+'Nil{}'
lines=['import Base','import ../packages/agent/src/agent-loop.bend as B','import ../packages/agent/test/tool-batch-sequential.bend as T']
for i,(c,e) in enumerate(zip(cases,expected,strict=True)):
    calls=seq('T.Call{'+str(v['id'])+', '+flag(v['terminate'])+', '+flag(v['fail'])+'}' for v in c['calls'])
    result='Done{B.Batch{'+str(e['state'])+', '+seq(e['messages'])+', '+flag(e['terminate'])+'}}' if e['ok'] else 'Fail{"delivery failed"}'
    lines += [f'def case{i}() -> IO(Unit):',f'  T.check({calls}, {c["initial"]}, {c["stopAfter"]}, {result}, {seq(e["visited"])}, {e["checks"]}, "case {i}")']
groups=[]
for start in range(0,len(cases),60):
    name=f'group{start}';groups.append(name)
    lines += [f'def {name}() -> IO(Unit):','  do IO<Unit>:']+[f'    case{i}()' for i in range(start,min(start+60,len(cases)))]
lines+=['def main() -> IO(Unit):','  do IO<Unit>:']+[f'    {name}()' for name in groups]+[f'    IO.print("PASS {len(cases)} sequential batch scheduling comparisons")']
source=BUILD/'tool-batch-sequential.bend';source.write_text('\n'.join(lines)+'\n');output=BUILD/'tool-batch-sequential'
for src,binary in [(source,output),('packages/agent/test/tool-batch-sequential-gated.bend',BUILD/'tool-batch-sequential-gated')]:
    subprocess.run(['sh','scripts/build-pure.sh',str(src),str(binary)],cwd=ROOT,check=True)
    for threads in ['1','4']:subprocess.run([str(binary),'--threads',threads],cwd=ROOT,check=True,timeout=120)

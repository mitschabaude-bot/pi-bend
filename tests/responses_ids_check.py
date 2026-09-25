"""Actual Responses ID normalization closure versus native typed helper."""
import itertools,json,random,subprocess
from pathlib import Path
from schema_literals import string
ROOT=Path(__file__).resolve().parents[1];BUILD=ROOT/'build'
ids=['','abc','___','call|item','call|fc_item','call|','|','|item','call|item|ignored','call|fc___','a b|i.t e-m','😀|🙈','\ud800|\udfff','x'*63+'😀z','x'*64+'z','call|'+'x'*70,'call|'+'fc_'+'x'*70]
rng=random.Random(80)
for _ in range(50):ids.append(''.join(rng.choice('abcXYZ09_-| .😀') for _ in range(rng.randrange(1,90))))
cases=[dict(id=id,allowed=allowed,foreignProvider=provider,foreignApi=api) for id in ids for allowed,provider,api in itertools.product([False,True],repeat=3)]
expected=json.loads(subprocess.check_output(['node','tests/responses_ids_reference.mts'],input=json.dumps(cases),text=True,cwd=ROOT))
def boolean(v):return 'True{}' if v else 'False{}'
lines=['import Base','import ../packages/ai/test/api/responses-ids.bend as T']
for i,(c,result) in enumerate(zip(cases,expected,strict=True)):
    lines += [f'def case{i}() -> IO(Unit):','  T.check('+', '.join([string(c['id']),boolean(c['allowed']),boolean(c['foreignProvider']),boolean(c['foreignApi']),string(result),f'"Responses ID {i}"'])+')']
groups=[]
for start in range(0,len(cases),40):
    name=f'group{start}';groups.append(name);lines += [f'def {name}() -> IO(Unit):','  do IO<Unit>:']+[f'    case{i}()' for i in range(start,min(start+40,len(cases)))]
lines += ['def main() -> IO(Unit):','  do IO<Unit>:']+[f'    {g}()' for g in groups]+[f'    IO.print("PASS {len(cases)} Responses tool-call ID source comparisons")']
src=BUILD/'responses-ids-check.bend';src.write_text('\n'.join(lines)+'\n');out=BUILD/'responses-ids-check'
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh','scripts/build-pure.sh',str(src),str(out)],cwd=ROOT,check=True)
for threads in ['1','4']:subprocess.run([str(out),'--threads',threads],cwd=ROOT,check=True,timeout=120)

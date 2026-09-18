"""Actual Responses text-signature codec versus native strict JSON decoder."""
import itertools,json,subprocess
from pathlib import Path
from schema_literals import string
ROOT=Path(__file__).resolve().parents[1];BUILD=ROOT/'build'
signatures=[None,'','plain-id',' ','null','[]','{"','{}','{"v":1,"id":"x"} trailing',' {"v":1,"id":"x"}','{"v":1,"id":"a","id":"b"}','{"v":2,"v":1,"id":"ok"}','{"v":1e0,"id":"ok"}','{"v":01,"id":"x"}']
for version,id,phase in itertools.product([None,0,1,2,True,'1'],[None,'','id😀',12],[None,'commentary','final_answer','unknown',True]):
    signatures.append(json.dumps(dict(v=version,id=id,phase=phase),ensure_ascii=True,separators=(',',':')))
encodings=[dict(id=id,phase=phase) for id,phase in itertools.product(['','id','msg_1','quote"\\','line\n','😀','\ud800','\ud83d\ude00'],[None,'commentary','final_answer'])]
expected=json.loads(subprocess.check_output(['node','tests/text_signature_reference.mts'],input=json.dumps(dict(signatures=signatures,encodings=encodings)),text=True,cwd=ROOT))
def optional(value,fn):return 'None{}' if value is None else 'Some{'+fn(value)+'}'
def phase(value):return optional(value,lambda v:'T.'+('Commentary' if v=='commentary' else 'FinalAnswer')+'{}')
def signature(value):return optional(value,lambda v:'T.TextSignatureV1{'+string(v['id'])+', '+phase(v.get('phase'))+'}')
lines=['import Base','import ../packages/ai/test/api/text-signature.bend as Check','import ../packages/ai/src/types.bend as T']
for i,(original,result) in enumerate(zip(signatures,expected['decoded'],strict=True)):
    lines += [f'def case{i}() -> IO(Unit):',f'  Check.decode({optional(original,string)}, {signature(result)}, "text signature {i}")']
for i,(original,result) in enumerate(zip(encodings,expected['encoded'],strict=True),len(signatures)):
    lines += [f'def case{i}() -> IO(Unit):',f'  Check.encode({string(original["id"])}, {phase(original["phase"])}, {string(result)}, "signature encode {i}")']
count=len(signatures)+len(encodings);groups=[]
for start in range(0,count,35):
    name=f'group{start}';groups.append(name);lines += [f'def {name}() -> IO(Unit):','  do IO<Unit>:']+[f'    case{i}()' for i in range(start,min(start+35,count))]
lines += ['def main() -> IO(Unit):','  do IO<Unit>:']+[f'    {g}()' for g in groups]+[f'    IO.print("PASS {len(signatures)} signature decodings and {len(encodings)} encodings/round trips")']
src=BUILD/'text-signature-check.bend';src.write_text('\n'.join(lines)+'\n');out=BUILD/'text-signature-check'
subprocess.run(['sh','scripts/build-pure.sh',str(src),str(out)],cwd=ROOT,check=True)
for threads in ['1','4']:subprocess.run([str(out),'--threads',threads],cwd=ROOT,check=True,timeout=120)

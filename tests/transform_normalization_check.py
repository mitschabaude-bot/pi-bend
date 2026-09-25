"""Public transform composition, stateful mappings and callback error behavior."""
from upstream_pin import UPSTREAM, check_sibling
check_sibling()
import json,subprocess
from pathlib import Path
from schema_literals import string
ROOT=Path(__file__).resolve().parents[1];BUILD=ROOT/'build'
sequences=[[],['a12'],['a12','s','r1'],['r1','a1','r1'],['a1','r1','a1','r1'],['a11','r1'],['error','r1','a1'],['a1','s','aborted','r1'],['a12','s','r2','r1','u'],['a12','i','ri'],['i','a1','ri'],['a1','s','ri','i'],['a12','rx','s'],['s','u','a0']]
variants=[(0,False,False),(0,True,True),(0,False,True),(1,False,True),(2,False,True),(3,False,True)]
cases=[dict(mode=mode,same=same,enabled=enabled,tags=tags) for tags in sequences for mode,same,enabled in variants]
cases += [dict(mode=4,same=False,enabled=True,tags=tags) for tags in [['a12'],['a1','s','a2'],['error','aborted']]]
expected=json.loads(subprocess.check_output(['node','tests/transform_normalization_reference.mts'],input=json.dumps(cases),text=True,cwd=ROOT))
def values(items):return ' <> '.join([*[string(x) for x in items],'Nil{}'])
def boolean(v):return 'True{}' if v else 'False{}'
lines=['import Base','import ../packages/ai/test/api/transform-normalization.bend as T']
for i,(case,result) in enumerate(zip(cases,expected,strict=True)):
    assert result['failure']==(case['mode']==4)
    lines += [f'def case{i}() -> IO(Unit):',f'  T.check({case["mode"]}, {boolean(case["same"])}, {boolean(case["enabled"])}, {values(case["tags"])}, {string(result["value"])}, {string(result["trace"])}, "normalization {i}")']
lines += ['def main() -> IO(Unit):','  do IO<Unit>:']+[f'    case{i}()' for i in range(len(cases))]+[f'    IO.print("PASS {len(cases)} public transform compositions and callback traces")']
src=BUILD/'transform-normalization-check.bend';src.write_text('\n'.join(lines)+'\n');out=BUILD/'transform-normalization-check'
subprocess.run(['sh','scripts/build-pure.sh',str(src),str(out)],cwd=ROOT,check=True)
for threads in ['1','4']:subprocess.run([str(out),'--threads',threads],cwd=ROOT,check=True,timeout=120)

# Preserve every original named assertion case and verify the executable reports it.
import re
upstream=UPSTREAM / 'packages/ai/test/transform-messages-copilot-openai-to-anthropic.test.ts'
names=re.findall(r'\bit\("([^"\n]+)"',upstream.read_text())
named=ROOT/'packages/ai/test/transform-messages-copilot-openai-to-anthropic.bend'
assert re.findall(r'IO.print\("PASS ([^"\n]+)"\)',named.read_text())==names
output=BUILD/'test-transform-messages'
subprocess.run(['sh','scripts/build-pure.sh',str(named),str(output)],cwd=ROOT,check=True)
for threads in ['1','4']:
    result=subprocess.check_output([str(output),'--threads',threads],cwd=ROOT,text=True,timeout=120)
    assert result.splitlines()==['PASS '+name for name in names],result
    print(result,end='')

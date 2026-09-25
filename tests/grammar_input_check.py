"""Cumulative grammar input -> immutable JSON-delta transitions against Pi."""
import itertools,json,subprocess
from pathlib import Path
from schema_literals import string,value,seq
ROOT=Path(__file__).resolve().parents[1];BUILD=ROOT/'build'
def initial():return dict(input='',started=False,closed=False)
def step(next,close=False,property='payload'):return dict(next=next,close=close,property=property)
sequences=[]
for prop,parts in itertools.product(['payload','','quote"key','line\nkey','😀','__proto__'],[['','a','ab'],['a"','a"\nb'],['\ud83d','😀','😀x'],['😀','\ud83d\ude00z'],['\ud800','\ud800x'],['\\','\\\t\x00'],['','']]):
    steps=[step(p,property=prop) for p in parts]
    steps += [step(parts[-1],True,prop),step(parts[-1],True,prop),step(parts[-1],False,prop),step('changed',True,prop)]
    sequences.append(dict(buffer=initial(),steps=steps))
# Invalid replacements cannot advance the state; later valid appends still work.
for old,new in [('abc','ab'),('abc','xbc'),('😀','\ud83d'),('','a'),('abc','abc')]:
    for started,closed in itertools.product([False,True],repeat=2):
        sequences.append(dict(buffer=dict(input=old,started=started,closed=closed),steps=[step(new),step(old+'tail',True),step(old+'tail',True)]))
# Cover every control escape and complete/split surrogate boundaries.
for char in [chr(i) for i in range(32)]+['"','\\','\ud800','\udfff','\u2028','\u2029','é','e\u0301']:
    sequences.append(dict(buffer=initial(),steps=[step(char),step(char+'end',True)]))
arguments=[]
for prop,item in itertools.product(['payload','','😀','__proto__'],[None,False,True,0,1,'','hello😀',[],{},['text']]):
    arguments.append(dict(name='sample"tool',property=prop,arguments={prop:item}))
for prop in ['payload','toString','constructor']:arguments.append(dict(name='sample_tool',property=prop,arguments={}))
expected=json.loads(subprocess.check_output(['node','tests/grammar_input_reference.mts'],input=json.dumps(dict(sequences=sequences,arguments=arguments)),text=True,cwd=ROOT))
def boolean(x):return 'True{}' if x else 'False{}'
def buffer(b):return 'C.GrammarToolInputJsonBuffer{'+string(b['input'])+', '+boolean(b['started'])+', '+boolean(b['closed'])+'}'
def outcome(r):return ('Done{'+('None{}' if r['delta'] is None else 'Some{'+string(r['delta'])+'}')+'}') if r['ok'] else 'Fail{'+string(r['error'])+'}'
lines=['import Base','import ../packages/ai/test/api/grammar-input.bend as T','import ../packages/ai/src/api/constrained-sampling.bend as C','import ../packages/runtime/src/schema-value.bend as V','import ../packages/runtime/src/record.bend as R','import ../packages/runtime/src/f64.bend as F']
for i,(case,results) in enumerate(zip(sequences,expected['sequences'],strict=True)):
    steps=seq('T.Step{'+', '.join([string(s['property']),string(s['next']),boolean(s['close']),outcome(r),buffer(r['buffer'])])+'}' for s,r in zip(case['steps'],results,strict=True))
    lines += [f'def case{i}() -> IO(Unit):',f'  T.transitions({steps}, {buffer(case["buffer"])}, "grammar sequence {i}")']
for i,(case,result) in enumerate(zip(arguments,expected['arguments'],strict=True),len(sequences)):
    expectedResult='Done{'+string(result['value'])+'}' if result['ok'] else 'Fail{'+string(result['error'])+'}'
    args=value(case['arguments'])[len('V.ObjectValue{'):-1]
    lines += [f'def case{i}() -> IO(Unit):','  T.argument('+', '.join([string(case['name']),args,string(case['property']),expectedResult,f'"grammar argument {i}"'])+')']
count=len(sequences)+len(arguments);groups=[]
for start in range(0,count,25):
    name=f'group{start}';groups.append(name);lines += [f'def {name}() -> IO(Unit):','  do IO<Unit>:']+[f'    case{i}()' for i in range(start,min(start+25,count))]
transitions=sum(len(c['steps']) for c in sequences)
lines += ['def main() -> IO(Unit):','  do IO<Unit>:']+[f'    {g}()' for g in groups]+[f'    IO.print("PASS {len(sequences)} grammar sequences/{transitions} transitions and {len(arguments)} argument checks")']
src=BUILD/'grammar-input-check.bend';src.write_text('\n'.join(lines)+'\n');out=BUILD/'grammar-input-check'
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'sh','scripts/build-pure.sh',str(src),str(out)],cwd=ROOT,check=True)
for threads in ['1','4']:subprocess.run([str(out),'--threads',threads],cwd=ROOT,check=True,timeout=120)

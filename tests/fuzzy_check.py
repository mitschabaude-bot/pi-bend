"""Original named fuzzy tests, complete scores/order, generated and native Unicode cases."""
import json,pathlib,random,struct,subprocess,sys
from upstream_pin import PIN
ROOT=pathlib.Path(__file__).resolve().parents[1]
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT.parent/'pi-mono',text=True).strip()==PIN
rng=random.Random(1409); alphabet='abcXYZ012_-./: '
def word(n):return ''.join(rng.choices(alphabet,k=n))
extra=[{'kind':'match','query':word(rng.randrange(9)),'text':word(rng.randrange(35))} for _ in range(1800)]
extra += [{'kind':'filter','query':word(rng.randrange(7)),'items':[word(rng.randrange(25)) for _ in range(15)]} for _ in range(160)]
for query in ['codex52','52codex','a12','12a','a1b','1a2','////','\u2003a\u00a0b','A','abc']:
 extra += [{'kind':'filter','query':query,'items':['gpt-5.2-codex','codex52','52codex','a12','12a','a1b','1a2','a','a','a b','abc','ABC','A_B_C']}]
reference=json.loads(subprocess.check_output(['node','tests/fuzzy_reference.mts'],input=json.dumps(extra),text=True,cwd=ROOT))
for backend,command in [('bun',['bun','build/fuzzy.js']),('native-1',['build/fuzzy','--threads','1']),('native-4',['build/fuzzy','--threads','4'])]:
 if len(sys.argv)>1 and backend not in sys.argv[1:]:continue
 def run(cases):
  r=subprocess.run(command+[json.dumps(c,ensure_ascii=False) for c in cases],cwd=ROOT,capture_output=True,text=True,timeout=120)
  assert r.returncode==0,(backend,r.stderr)
  return [json.loads(line) for line in r.stdout.splitlines()]
 def score(value):return struct.unpack('>d',struct.pack('>II',*value[1:]))[0]
 for start in range(0,len(reference['cases']),12):
  batch=reference['cases'][start:start+12]; actual=run(batch);assert len(actual)==len(batch)
  for c,v in zip(batch,actual):
   if c['kind']=='match':assert (v[0],score(v))==(c['expected']['matches'],c['expected']['score']),(backend,c,v,score(v))
   else:assert [c['items'][i] for i in v]==c['expected'],(backend,c,v)
 native=[{'kind':'match','query':q,'text':t} for q,t in [('Σ','ς'),('É','é'),('𐐀','𐐨'),('😀','😀')]]
 for value in run(native):assert value[0] and score(value)==-115,(backend,value)
 long=[{'kind':'match','query':'z','text':'a'*50000},{'kind':'match','query':'a'*20000,'text':'a'*20000}]
 values=run(long);assert not values[0][0] and values[1][0]
 print(f"{backend}: {len(reference['names'])} original tests/{reference['originalCalls']} calls, {len(reference['cases'])} comparisons, Unicode and long-input checks passed",flush=True)

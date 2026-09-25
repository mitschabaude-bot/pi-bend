"""Differential terminal framing with explicit flush; real timer ownership is separate."""
import json,pathlib,random,subprocess,sys
from upstream_pin import PIN, UPSTREAM, check_sibling
check_sibling()
ROOT=pathlib.Path(__file__).resolve().parents[1]
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=UPSTREAM,text=True).strip()==PIN
esc='\x1b'
sequences=['a','hello 世界',esc,esc+'[A',esc+'[1;5D',esc+'OP',esc+'x',esc+'[<35;20;5m',esc+'[<0;1;1M',esc+'[Mabc',esc+']title\x07',esc+']title'+esc+'\\',esc+'P>|version'+esc+'\\',esc+'_Gok'+esc+'\\',esc+'[97u'+'a',esc+'[97:65u'+'a',esc+'[97:u'+'a',esc+'[97::65u'+'a',esc+'[97;2u'+'a',esc+esc+'[27;1:3u',esc+'[200~hello\n世界'+esc+'[201~z']
original=json.loads(subprocess.check_output(['node','tests/stdin_buffer_original.mts'],text=True,cwd=ROOT))
scenarios=original['scenarios'][:]
for text in sequences:
 for cut in range(len(text)+1):
  # Empty input is a distinct event; don't invent it at split boundaries.
  scenarios.append([['process',part] for part in [text[:cut],text[cut:]] if part]+[['flush']])
 scenarios.append([['process',char] for char in text]+[['flush']])
scenarios += [[['process','']], [['process',esc+'[<'],['clear'],['process','x']], [['process',esc+'[200~'],['flush'],['process','text'+esc+'[201~']]]
rng=random.Random(320)
for _ in range(150):
 text=''.join(rng.choices(sequences[:18],k=4));steps=[]
 while text:
  n=rng.randrange(1,8);steps.append(['process',text[:n]]);text=text[n:]
 scenarios.append(steps+[['flush']])
expected=json.loads(subprocess.check_output(['node','tests/stdin_buffer_reference.mts'],input=json.dumps(scenarios),text=True,cwd=ROOT))
for backend,command in [('bun',['bun','build/stdin-buffer.js']),('native-1',['build/stdin-buffer','--threads','1']),('native-4',['build/stdin-buffer','--threads','4'])]:
 if len(sys.argv)>1 and backend not in sys.argv[1:]:continue
 for start in range(0,len(scenarios),12):
  cases=scenarios[start:start+12]
  result=subprocess.run(command+[json.dumps(x,ensure_ascii=False) for x in cases],capture_output=True,text=True,cwd=ROOT,timeout=120)
  assert result.returncode==0,(backend,result.stderr)
  actual=[json.loads(x) for x in result.stdout.splitlines()]
  assert len(actual)==len(cases)
  for i,value in enumerate(actual):assert value==expected[start+i],(backend,cases[i],value,expected[start+i])
 # Unicode scalar events and large control/paste payloads are native checks.
 for text,kind,payload in [('😀','data','😀'),(esc+']'+'x'*50000+esc+'\\','data',esc+']'+'x'*50000+esc+'\\'),(esc+'[200~'+'x'*50000+esc+'[201~','paste','x'*50000)]:
  result=subprocess.run(command+[json.dumps([['process',text]],ensure_ascii=False)],capture_output=True,text=True,cwd=ROOT,timeout=30)
  assert result.returncode==0,(backend,result.stderr)
  assert json.loads(result.stdout)==[{'events':[[kind,payload]],'buffer':'','timeout':None}]
 print(f'{backend}: {len(original['names'])} original tests replayed as pure transitions; {len(scenarios)} input framing traces passed',flush=True)

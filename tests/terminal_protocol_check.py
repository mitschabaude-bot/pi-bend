import json,pathlib,random,subprocess,sys
ROOT=pathlib.Path(__file__).resolve().parents[1]
e='\x1b'
scenarios=[[[0,e+'[?7u'],None],[[0,e+'[?0u'],None],[[0,e+'[?1;2c'],None],[[0,'x'],[2,e+'[?7u'],None],[[0,e+'[?7'],[100,'u'],None],[[0,e+'['],149,150,None],[[0,e+'[?'],[20,'9'],[30,'x'],None],[[0,e+'[?0u'],[30,e+'[?7u'],None],[[0,e+'[?7u'],[30,e+'[?0u'],None]]
rng=random.Random(7320)
parts=['a',e+'[',e+'[?',e+'[?7u',e+'[?0u',e+'[?1;2c','7','u',';','c','x',e+'[A']
for _ in range(80):
 now=0;steps=[]
 for _ in range(12):
  now+=rng.randrange(0,35);steps.append([now,rng.choice(parts)])
  if rng.randrange(4)==0:now+=200;steps.append(now)
 steps.append(None);scenarios.append(steps)
scenarios.append([[0,e+'[?'+'1'*50000],151,None])
reference=json.loads(subprocess.check_output(['node','tests/terminal_protocol_reference.mts'],input=json.dumps(scenarios),text=True,cwd=ROOT))
original=json.loads(subprocess.check_output(['node','tests/terminal_original.mts'],cwd=ROOT,text=True))
helpers=[]
for call in original['calls']:
 if call['name']=='resolveEscapeTimeoutMs':
  env=call['args'][0];argument=['escape',env.get('PI_TUI_ESC_TIMEOUT',''),env.get('SSH_CONNECTION',''),env.get('SSH_TTY','')]
 else:argument=['normalize',*call['args']]
 helpers.append((argument,call['result']))
for name,command in [('bun',['bun','build/terminal-protocol.js']),('native1',['build/terminal-protocol','--threads','1']),('native4',['build/terminal-protocol','--threads','4'])]:
 if len(sys.argv)>1 and name not in sys.argv[1:]:continue
 for steps,wanted in zip(scenarios,reference):
  run=subprocess.run(command+[json.dumps(steps)],cwd=ROOT,text=True,capture_output=True,timeout=15)
  assert run.returncode==0,(name,run.stderr)
  actual=[json.loads(line) for line in run.stdout.splitlines()]
  assert actual==wanted,(name,steps,actual,wanted)
 for argument,wanted in helpers:
  actual=json.loads(subprocess.check_output(command+[json.dumps(argument)],cwd=ROOT,text=True))
  assert actual==wanted,(name,argument,actual,wanted)
 print(name,len(scenarios),'pinned negotiation traces +',len(helpers),'original helper calls passed;',len(original['names']),'original source tests executed',flush=True)

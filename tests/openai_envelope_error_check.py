"""Native envelope diagnostics and actual SDK timeout/authentication messages."""
import hashlib,json,re,struct,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
values=[0.0,-0.0,1.0,600000.0,-1.0,0.5,-0.5,1.5,1e20,1e100,float('nan'),float('inf'),-float('inf')]
words=[list(struct.unpack('>II',struct.pack('>d',x))) for x in values]
reference=json.loads(subprocess.check_output(['node','tests/openai_envelope_error_reference.mts'],cwd=ROOT,input=json.dumps(words),text=True))
expected=[reference['authentication'],'Invalid HTTP header name','Invalid HTTP header value','HTTP header value contains a non-byte character','Invalid URL','Invalid URL query name in field 0','Invalid URL query value in field 9','Request payload contains a non-finite number','Could not encode request payload as JSON']
runs=[]
prefix=ROOT/'build/openai-envelope-error'
for backend,command in [('native-1',[str(prefix),'--threads','1']),('native-4',[str(prefix),'--threads','4']),('bun',['bun',str(prefix)+'.js'])]:
 for bits,message in zip(words,reference['messages']):
  result=subprocess.run(command+['timeout',*map(str,bits)],cwd=ROOT,capture_output=True,text=True,check=True,timeout=10)
  assert not result.stderr and json.loads(result.stdout)==message,(backend,bits,message,result)
  runs.append(dict(backend=backend,bits=bits,message=message,reference='SDK validatePositiveInteger'))
 result=subprocess.run(command+['native'],cwd=ROOT,capture_output=True,text=True,check=True,timeout=10)
 assert not result.stderr and [json.loads(x) for x in result.stdout.splitlines()]==expected,(backend,result)
 runs.append(dict(backend=backend,messages=expected,reference='SDK authentication diagnostic; other messages native validation policy'))
 print(backend,'13 timeout cases and 9 envelope diagnostics PASS',flush=True)
pending=[ROOT/'tests/openai-envelope-error.bend'];seen=set()
while pending:
 path=pending.pop().resolve()
 if path in seen:continue
 seen.add(path);pending.extend(path.parent/n for n in re.findall(r'^import (\.[^\s]+)',path.read_text(),re.M))
sdk=Path('/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/openai')
seen.update([Path(__file__).resolve(),ROOT/'tests/openai_envelope_error_reference.mts',sdk/'package.json',sdk/'client.mjs',sdk/'internal/utils/values.mjs'])
h=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
record=dict(scope=__doc__,sdk=reference['version'],sources={str(p):h(p) for p in sorted(seen)},programs={str(p):h(p) for p in [Path(str(prefix)+s) for s in ['', '.c', '.js']]},runs=runs)
Path('build/openai-envelope-error-results.json').write_text(json.dumps(record,indent=2)+'\n')

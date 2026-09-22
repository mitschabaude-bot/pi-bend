"""Native Responses envelope versus actual SDK request preparation, no network."""
import hashlib
import json
import os
from pathlib import Path
from bend_toolchain import BEND, TOOLCHAIN
import re
import subprocess
import sys
from urllib.parse import unquote_to_bytes
ROOT=Path(__file__).resolve().parents[1]
SDK=Path('/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/openai')
assert json.loads((SDK/'package.json').read_text())['version']=='6.40.0'
base=dict(baseUrl='https://api.openai.com/v1',apiKey='fixture-key',userAgent='pi-bend-test',payload={'model':'fixture','input':[],'stream':True},client={})
rows=[]
payloads=[None,False,True,0,-0.0,1,-1,1.5,'','hé🙂',[],{},[None,False,0,'x'],{'s':'\u0000\n🙂','array':[1,True,None]}, {'input':[{'role':'user','content':'hello'}],'stream':True}]
clients=[{}, {'content-type':'text/plain'}, {'Content-Type':None}, {'authorization':None}, {'authorization':''}, {'authorization':'', 'api-key':'proxy'}, {'x-note':'  value  ','x-byte':'ÿ'}, {'bad name':'x'}, {'x-note':'\n'}]
for payload in payloads:
 for client in clients:rows.append({**base,'payload':payload,'client':client})
for timeout in [0,1,999,1000,1001,600000,-1,0.5]:
 for mode in ['', 'nan','infinity','negative-infinity','nested-nan']:
  rows.append({**base,'timeout':timeout,'payloadMode':mode})
for mode in ['nan','nested-nan']:
 for client in clients:rows.append({**base,'payloadMode':mode,'client':client})
for url in ['','/v1','https://example.test/v1/','https://例え.テスト/v1','http://[::1]:8080/v1','https://example.test/v1?x=a+b&x=second','https://example.test/v1?x=%FF','https://example.test/v1?%GG=x','https://example.test/v1#fragment']:
 for timeout in [0,-1,1001]:rows.append({**base,'baseUrl':url,'timeout':timeout})
for org in [None,'','org-test']:
 for project in [None,'','project-test']:rows.append({**base,'organization':org,'project':project})
observations=json.loads(subprocess.check_output(['node','tests/openai_responses_envelope_reference.mjs'],cwd=ROOT,input=json.dumps(rows),text=True,env={k:v for k,v in os.environ.items() if not k.startswith('OPENAI_')}))

def query_error(query):
 for i,field in enumerate(query.split('&')):
  if not field:continue
  name,_,value=field.partition('=')
  for label,part in [('name',name),('value',value)]:
   if re.search(r'%(?![0-9a-fA-F]{2})',part):return 'query-'+label+':'+str(i)
   try:unquote_to_bytes(part.replace('+',' ')).decode('utf-8','strict')
   except UnicodeDecodeError:return 'query-'+label+':'+str(i)
 return None
expected=[];differences=[]
for row,observed in zip(rows,observations,strict=True):
 row['platform']=observed['platform']
 error='url' if observed.get('invalidURL') else query_error(observed.get('query',''))
 if not error and 'timeout' in row:
  value=row['timeout']
  if int(value)!=value:error='timeout-integer'
  elif value<0:error='timeout-negative'
 if not error and row.get('payloadMode'):error='nonfinite-payload'
 if error:want={'error':error}
 elif 'error' in observed:want={'error':observed['error']}
 else:
  want=observed['actual']
  # Only null/false/zero/empty string are falsy in the SDK's body dispatch.
  payload=row['payload']
  if payload is None or payload is False or payload==0 or payload=='':
   want={**observed['withJSONHeaders'],'body':json.dumps(payload,ensure_ascii=False,separators=(',',':'))}
   if isinstance(payload,float) and payload==0:want['body']='0'
 if want != observed.get('actual',{'error':observed.get('error')}):differences.append(dict(input=row,sdk=observed,native=want))
 expected.append(want)
if '--no-build' not in sys.argv:
 for suffix,command,limit in [('c',['sh','scripts/build-pure.sh','packages/ai/test/openai-responses-envelope.bend','build/openai-responses-envelope'],'24'),('js',[os.environ.get('BEND',str(ROOT/'build/bend-native-toolchain/bend2/main.ts') if (ROOT/'build/bend-native-toolchain/bend2/main.ts').is_file() else str(Path(BEND))),'packages/ai/test/openai-responses-envelope.bend','-o','build/openai-responses-envelope.js'],'12')]:
  subprocess.run([sys.executable,'scripts/run-rss-guarded.py','--limit-gib',limit,'--stats','build/envelope-rebuild-'+suffix+'.json','--',*command],cwd=ROOT,check=True)
def codes(value):return ','.join(str(ord(c)) for c in json.dumps(value,ensure_ascii=False,separators=(',',':')))
args=[part for row,want in zip(rows,expected,strict=True) for part in (codes(row),codes(want))]
commands=[('native 1',['build/openai-responses-envelope','--threads','1']),('native 4',['build/openai-responses-envelope','--threads','4']),('Bun',[str(Path.home()/'.bun/bin/bun'),'build/openai-responses-envelope.js'])]
if '--js-only' in sys.argv:commands=commands[-1:]
for label,command in commands:
 for i in range(0,len(rows),8):
  run=subprocess.run([*command,*args[2*i:2*(i+8)]],cwd=ROOT,capture_output=True,text=True,timeout=60)
  assert run.returncode==0 and run.stdout=='PASS Responses request envelopes\n',(label,i,rows[i:i+8],expected[i:i+8],run.stdout,run.stderr)
 print(f'{label}: {len(rows)} Responses envelopes PASS',flush=True)
if '--js-only' not in sys.argv:
 def digest(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
 pending=[ROOT/'packages/ai/test/openai-responses-envelope.bend'];seen=set()
 while pending:
  path=pending.pop().resolve()
  if path in seen:continue
  seen.add(path);pending.extend(path.parent/n for n in re.findall(r'^import (\.[^\s]+)',path.read_text(),re.M))
 report=dict(sdk_version='6.40.0',sdk_sha256={p:digest(SDK/p) for p in ['client.mjs','internal/request-options.mjs','internal/headers.mjs','internal/detect-platform.mjs','internal/utils/query.mjs','internal/qs/stringify.mjs','internal/qs/utils.mjs']},cases=len(rows),comparisons=3*len(rows),source_sha256={str(p.relative_to(ROOT)):digest(p) for p in sorted(seen)},test_sha256={p:digest(p) for p in ['tests/openai_responses_envelope_check.py','tests/openai_responses_envelope_reference.mjs']},rows=rows,expected=expected,observations=observations,intentional_differences=differences,artifact_sha256={p:digest(p) for p in ['build/openai-responses-envelope','build/openai-responses-envelope.c','build/openai-responses-envelope.js']})
 (ROOT/'build/openai-responses-envelope-results.json').write_text(json.dumps(report,ensure_ascii=True,indent=2)+'\n')

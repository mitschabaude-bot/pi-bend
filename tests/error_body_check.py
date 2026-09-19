"""Compare native typed provider-error normalization with pinned pi's actual utility.

SDK shape/status extraction belongs to provider adapters; this checks body
selection, normalization and formatting after that explicit boundary.
"""
import itertools
import json
import re
from pathlib import Path
import subprocess
import sys
ROOT=Path(__file__).resolve().parents[1]
cases=[]
names=[]
def add(name,status,message,bodies,prefix=None):
    names.append(name);cases.append([status,message,bodies,prefix])
# Original error-body.test.ts scenarios, adapted to typed transport data.
add('extracts status and body from a Mistral-shaped error',403,'Mistral request failed',[['text','{"error":"blocked by gateway WAF"}']])
add('reads the parsed body off an openai APIError when the message is opaque',403,'403 status code (no body)',[None,['json',{'error':'blocked by gateway WAF'}]])
add('preserves the message when @google/genai already folds the body into it',403,'{"error":{"code":403,"message":"Permission denied"}}',[])
add('extracts status and body from a Bedrock-shaped ServiceException',403,'UnknownError',[None,None,['text','{"message":"blocked by gateway WAF"}']])
add('ignores a Bedrock response stream instead of serializing its internals',400,"Invocation of model ID anthropic.claude-opus-5 with on-demand throughput isn't supported.",[None,None,['unread',None]])
add('ignores a class-instance response body without a pipe method instead of serializing it',400,'Input is too long for requested model.',[None,None,['private',None]])
add('ignores a class-instance `error` field instead of serializing it',502,'TLS handshake failed',[None,['private',None]])
add('still surfaces a plain parsed JSON body object',400,'400 status code (no body)',[None,['json',{'message':'schema validation failed','field':'tools[0]'}]])
names.append('JSON-stringifies a non-Error thrown value');cases.append(['value',{'reason':'boom'},None])
add('treats an empty parsed body object as no body',403,'403 status code (no body)',[None,['json',{}]])
add('truncates the body at the cap',500,'failed',[['text','x'*4050]])
add('sets messageCarriesBody when the message already contains the extracted body',500,'500: upstream exploded',[['text','upstream exploded']])
add('surfaces status and body without a prefix',403,'403 status code (no body)',[None,['json',{'error':'blocked by gateway WAF'}]])
add('applies a provider prefix with status and body',403,'403 status code (no body)',[None,['json',{'error':'blocked by gateway WAF'}]],'OpenAI API error')
add('preserves the message (with prefix + status) when it already carries the body',403,'{"error":{"message":"Permission denied"}}',[],'OpenAI API error')
names.append('returns the bare message for a non-Error value');cases.append(['value',{'reason':'boom'},None])
original_names=re.findall(r'it\("([^"\n]+)"', (ROOT/'../pi-mono/packages/ai/test/error-body.test.ts').read_text())
assert names==original_names, 'Original named scenario mapping changed'
# Supported source shapes, ordered precedence, empty-first suppression, trim,
# truncation boundaries and message inclusion, including split surrogate pairs.
source_sets=[[],[['text','']], [['text',' \t\n']], [['text',' \ufeffblocked\u2029 ']], [None,['json',{}],['text','fallback']], [None,['json',[]],['text','fallback']], [None,['json',{'detail':['why',None,2.5]}],['text','fallback']], [['text',' '],['json',{'message':'must not win'}]], [None,None,['json',{'message':'body'}]], [None,None,['unread',None]], [None,None,['private',None]]]
for status,prefix,sources,message in itertools.product([None,0,400,503], [None,'','Provider API error'],source_sets,['opaque','prefix blocked suffix']):
    add('cross-product',status,message,sources,prefix)
for size,ending in itertools.product([3998,3999,4000,4001],['x','😀','\ud800','😀tail']):
    add('UTF-16 truncation boundary',500,'failed',[['text','x'*size+ending]],'Provider')
for value in [None,False,True,0,-0.0,'boom',[],{},[1,'😀'],{'nested':{'message':'failed'}}]:
    names.append('JSON-valued failure');cases.append(['value',value,'ignored'])
expected=json.loads(subprocess.check_output(['node','tests/error_body_reference.mts'],input=json.dumps(cases),cwd=ROOT,text=True))
if '--no-build' not in sys.argv:
    subprocess.run([sys.executable,'scripts/run-rss-guarded.py','--stats','build/error-body-build.json','--','sh','scripts/build-pure.sh','packages/ai/test/error-body-runner.bend','build/error-body-runner'],cwd=ROOT,check=True)
def encode(value):return ','.join(str(ord(c)) for c in json.dumps(value,ensure_ascii=True,separators=(',',':')))
# Private/unread handles are represented explicitly as unavailable native data.
native=[]
for c in cases:
    if len(c)==3:native.append(c);continue
    status,message,bodies,prefix=c
    native.append([status,message,[None if b is not None and b[0] in ['unread','private'] else b for b in bodies],prefix])
for threads in ['1','4']:
    for start in range(0,len(cases),12):
        args=[encode([c,e]) for c,e in zip(native[start:start+12],expected[start:start+12])]
        result=subprocess.run([str(ROOT/'build/error-body-runner'),'--threads',threads,*args],cwd=ROOT,text=True,capture_output=True,timeout=120)
        assert result.returncode==0,(threads,start,names[start:start+12],result.stdout,result.stderr)
    print(f'PASS {len(cases)} actual-pi provider-error comparisons on {threads} threads')

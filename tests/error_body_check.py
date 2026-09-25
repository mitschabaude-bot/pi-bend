"""Compare native typed provider-error normalization with pinned pi's actual utility.

SDK shape/status extraction belongs to provider adapters; this checks body
selection, normalization and formatting after that explicit boundary.
"""
from upstream_pin import UPSTREAM
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
original_names=re.findall(r'it\("([^"\n]+)"', (UPSTREAM / 'packages/ai/test/error-body.test.ts').read_text())
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
# Native strings retain whole characters at the UTF-16 display cap. Preserve
# all upstream expectations except the explicitly documented split-surrogate
# boundary; the original oracle result remains available in this audit record.
adaptations=[]
for index,(case,name) in enumerate(zip(cases,names)):
    if name!='UTF-16 truncation boundary':continue
    source=case[2][0][1]
    prefix=[];used=0
    for char in source:
        width=2 if ord(char)>0xffff else 1
        if used+width>4000:break
        prefix.append(char);used+=width
    total=sum(2 if ord(char)>0xffff else 1 for char in source)
    text=''.join(prefix)
    if used<total:text+=f'... [truncated {total-used} chars]'
    if text!=expected[index][1]:
        original=expected[index]
        expected[index]=[500,text,'failed',False,'Provider (500): '+text]
        adaptations.append({'case':index,'original':original,'native':expected[index],
                            'reason':'UTF-16 budget never splits a native character; omitted count includes the whole discarded character.'})
(ROOT/'build/error-body-scalar-boundaries.json').write_text(json.dumps(adaptations,indent=2)+'\n')

if '--no-build' not in sys.argv:
    subprocess.run(['flock', '/tmp/pi-bend-build.lock', sys.executable,'scripts/run-rss-guarded.py','--stats','build/error-body-build.json','--','sh','scripts/build-pure.sh','packages/ai/test/error-body-runner.bend','build/error-body-runner'],cwd=ROOT,check=True)
def encode(value):return ','.join(str(ord(c)) for c in json.dumps(value,ensure_ascii=True,separators=(',',':')))
# Private/unread handles are represented explicitly as unavailable native data.
native=[]
for c in cases:
    if len(c)==3:native.append(c);continue
    status,message,bodies,prefix=c
    native.append([status,message,[None if b is not None and b[0] in ['unread','private'] else b for b in bodies],prefix])
# Native strings hold Unicode scalars only, and the strict JSON decoder
# rejects lone surrogate escapes (2f7b589), so upstream inputs containing an
# isolated UTF-16 surrogate have no native counterpart. They are recorded,
# not run.
def lone_surrogate(value):
    return any(0xd800<=ord(ch)<=0xdfff for ch in json.dumps(value,ensure_ascii=False))
unrepresentable=[i for i,c in enumerate(cases) if lone_surrogate(c)]
(ROOT/'build/error-body-unrepresentable.json').write_text(json.dumps([{'case':i,'name':names[i],'upstream':expected[i]} for i in unrepresentable],indent=2)+'\n')
assert len(unrepresentable)==4 and all(names[i]=='UTF-16 truncation boundary' for i in unrepresentable), unrepresentable
runnable=[i for i in range(len(cases)) if i not in unrepresentable]
for threads in ['1','4']:
    for start in range(0,len(runnable),12):
        chunk=runnable[start:start+12]
        args=[encode([native[i],expected[i]]) for i in chunk]
        result=subprocess.run([str(ROOT/'build/error-body-runner'),'--threads',threads,*args],cwd=ROOT,text=True,capture_output=True,timeout=120)
        assert result.returncode==0,(threads,start,[names[i] for i in chunk],result.stdout,result.stderr)
    print(f'PASS {len(runnable)} actual-pi provider-error comparisons on {threads} threads ({len(unrepresentable)} lone-surrogate inputs not representable natively)')

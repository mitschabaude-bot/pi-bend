"""Full native request builder versus pinned buildParams with real converters."""
import argparse,itertools,json,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--prefix',default='build/responses-request')
parser.add_argument('--backends',nargs='+',choices=['bun','native-1','native-4'],default=['native-1','native-4'])
parser.add_argument('--no-build',action='store_true')
arguments=parser.parse_args()
fields=['supportsDeveloperRole','supportsMidConvoSystemMessages','sessionAffinityFormat','supportsLongCacheRetention','supportsStrictMode','supportsOpenAIGrammarTools','supportsAdditionalTools','supportsToolSearch','supportsExplicitPromptCacheMode','supportsMaxOutputTokens']
def tool(name,grammar=False):
    value=dict(name=name,description='A tool',parameters={'type':'object','properties':{'input':{'type':'string'}},'required':['input']})
    if grammar:value['constrainedSampling']={'type':'grammar','variants':{'openai_lark':'start: /[a-z]+/'}}
    return value
def system(content,**extra):return dict(role='system',content=content,timestamp=extra.pop('timestamp',1),**extra)
def user(content,timestamp=1):return dict(role='user',content=content,timestamp=timestamp)
cases=[]
modes=[]
for mode,mid,addition,search,strict,grammar in itertools.product(range(7),[False,True],[False,True],[False,True],[False,True],[False,True]):
    messages=[system('initial',**({} if mode==0 else {'toolsAdded':[tool('tool',mode==5)]})),user('hello')]
    if mode==2:messages.extend([system('updated',toolsAdded=[tool('later')],timestamp=2),user('again',3)])
    if mode==3:messages.append(system('updated',toolsRemoved=[{'name':'tool'}],timestamp=2))
    if mode==4:
        changed=tool('tool');changed['description']='Redefined'
        messages.append(system('updated',toolsAdded=[changed],timestamp=2))
    if mode==6:
        usage=dict(input=0,output=0,cacheRead=0,cacheWrite=0,totalTokens=0,cost=dict(input=0,output=0,cacheRead=0,cacheWrite=0,total=0))
        messages.extend([dict(role='assistant',api='openai-responses',provider='openai',model='target',content=[dict(type='toolCall',id='call_fixture',name='tool',arguments={'input':'hello'})],usage=usage,stopReason='toolUse',timestamp=2),dict(role='toolResult',toolCallId='call_fixture',toolName='tool',content=[dict(type='text',text='done')],isError=False,timestamp=3)])
    compat=dict(supportsMidConvoSystemMessages=mid,supportsAdditionalTools=addition,supportsToolSearch=search,supportsStrictMode=strict,supportsOpenAIGrammarTools=grammar)
    model=dict(id='target',api='openai-responses',provider='openai',baseUrl='https://example.test',reasoning=True,input=['text'],compat=compat)
    options=dict(maxTokens=1,temperature=0,serviceTier='priority',toolChoice='required',reasoningEffort='high',reasoningSummary='concise',sessionId='session',cacheRetention='long')
    cases.append(dict(model=model,messages=messages,options=options));modes.append(mode)
expected=json.loads(subprocess.check_output(['node','tests/responses_request_reference.mts'],input=json.dumps(cases),text=True,cwd=ROOT))
if not arguments.no_build:
    entry='packages/ai/test/openai-responses-request.bend'
    if any(name.startswith('native') for name in arguments.backends):
        subprocess.run([sys.executable,'scripts/run-rss-guarded.py','--stats',arguments.prefix+'-build.json','--','sh','scripts/build-pure.sh',entry,arguments.prefix],cwd=ROOT,check=True)
    if 'bun' in arguments.backends:
        subprocess.run(['build/bend-native-toolchain/bend2/main.ts',entry,'-o',arguments.prefix+'.js'],cwd=ROOT,check=True)
def encode(value):return ','.join(str(ord(c)) for c in json.dumps(value,ensure_ascii=True,separators=(',',':')))
for backend in arguments.backends:
    command=['bun',arguments.prefix+'.js'] if backend=='bun' else [arguments.prefix,'--threads',backend[-1]]
    for start in range(0,len(cases),8):
        args=[]
        for mode,case,result in zip(modes[start:start+8],cases[start:start+8],expected[start:start+8]):
            compat=case['model']['compat'];flags='.'.join('-' if f not in compat else str(int(compat[f])) for f in fields)
            args.extend([str(mode),flags,encode(result)])
        run=subprocess.run(command+args,cwd=ROOT,capture_output=True,text=True,timeout=120)
        assert run.returncode==0,(backend,start,cases[start:start+8],expected[start:start+8],run.stdout,run.stderr)
    print(f'PASS {len(cases)} full Responses request comparisons on {backend}')

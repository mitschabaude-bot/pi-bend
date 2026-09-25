"""Native Responses compatibility/cache policy versus extracted pinned helpers.

The oracle executes upstream createClient with a capturing SDK constructor;
no network, credentials, provider wrapper or HTTP header normalization is tested.
"""
from upstream_pin import UPSTREAM, check_sibling
check_sibling()
import itertools,json,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
fields=['supportsDeveloperRole','supportsMidConvoSystemMessages','sessionAffinityFormat','supportsLongCacheRetention','supportsStrictMode','supportsOpenAIGrammarTools','supportsAdditionalTools','supportsToolSearch','supportsExplicitPromptCacheMode','supportsMaxOutputTokens']
bools=[f for f in fields if f!='sessionAffinityFormat']
affinity={'openai':'a','openai-nosession':'n','openrouter':'r'}
# Confirm the actual public union spelling instead of accepting a made-up alias.
assert '"openai-nosession"' in (UPSTREAM / 'packages/ai/src/types.ts').read_text()
cases=[]
def add(**kwargs):
    case=dict(provider='openai',url='https://api.openai.com/v1',compat=None,retention=None,env=None,session='session')
    case.update(kwargs)
    cases.append(case)
add(compat={})
for provider,url in [('openai','https://api.openai.com/v1'),('openrouter','https://proxy.invalid'),('proxy','https://openrouter.ai/api/v1'),('proxy','https://OPENROUTER.AI/api'),('opencode','https://proxy.invalid'),('proxy','https://proxy.invalid/openrouter.ai')]:
    for retention,env,session in itertools.product([None,'none','short','long'],[None,'','long','short','LONG',' long '],[None,'','session','x'*65,'😀'*65,'x'*63+'😀tail','a'*63+'\ud800x']):
        add(provider=provider,url=url,retention=retention,env=env,session=session)
# Every boolean combination and explicit/default affinity selection; retention
# cycles independently to exercise the interacting long/explicit cache flags.
for values,fmt,retention in itertools.product(itertools.product([False,True],repeat=len(bools)),[None,*affinity],[None,'none','short','long']):
    compat=dict(zip(bools,values))
    if fmt is not None:compat['sessionAffinityFormat']=fmt
    add(compat=compat,retention=retention,env='long',session='key'+'😀'*70)
for field in bools:
    for flag in [False,True]:add(compat={field:flag})
results=json.loads(subprocess.check_output(['node','tests/responses_policy_reference.mts'],input=json.dumps(cases),text=True,cwd=ROOT))
def codes(text):return '-' if text is None else ','.join(str(ord(c)) for c in text)
def flags(compat):
    if compat is None:return '-'
    return '.'.join('-' if f not in compat else affinity[compat[f]] if f=='sessionAffinityFormat' else str(int(compat[f])) for f in fields)
def result(value):
    assert list(value['compat'])==fields
    option=value['options']
    return '|'.join([flags(value['compat']),value['retention'],codes(value['promptRetention']),'-' if option is None else 'explicit' if 'mode' in option else '30m',codes(value['session']),codes(value['key']),*[codes(h) for h in value['headers']]])
args=[';'.join([codes(c['provider']),codes(c['url']),flags(c['compat']),c['retention'] or '-',codes(c['env']),codes(c['session']),result(r)]) for c,r in zip(cases,results,strict=True)]
if '--no-build' not in sys.argv:
    subprocess.run([sys.executable,'scripts/run-rss-guarded.py','--stats','build/responses-policy-build.json','--','sh','scripts/build-pure.sh','packages/ai/test/openai-responses-policy-runner.bend','build/responses-policy-runner'],cwd=ROOT,check=True)
for threads in ['1','4']:
    for start in range(0,len(args),32):
        run=subprocess.run([str(ROOT/'build/responses-policy-runner'),'--threads',threads,*args[start:start+32]],cwd=ROOT,capture_output=True,text=True,timeout=60)
        assert run.returncode==0,(threads,start,cases[start:start+32],run.stdout,run.stderr)
    print(f'PASS {len(args)} upstream Responses policy comparisons on {threads} threads')

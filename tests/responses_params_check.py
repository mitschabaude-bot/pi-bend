"""Compare final Responses field assembly with the actual upstream buildParams.

Converters are substituted with preconverted values in this boundary oracle;
this is not a transcript/tool conversion or provider transport test.
"""
import itertools,json,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
fields=['supportsDeveloperRole','supportsMidConvoSystemMessages','sessionAffinityFormat','supportsLongCacheRetention','supportsStrictMode','supportsOpenAIGrammarTools','supportsAdditionalTools','supportsToolSearch','supportsExplicitPromptCacheMode','supportsMaxOutputTokens']
cases=[]
def add(provider='openai',reasoning=True,mapping=None,compat=None,options=None,input=None,tools=None):
    cases.append(dict(model=dict(id='model',provider=provider,baseUrl='',reasoning=reasoning,thinkingLevelMap=mapping,compat=compat),options=options or {},input=input or [],tools=tools or []))
for provider,reasoning,effort,summary in itertools.product(['openai','github-copilot','xai','proxy'],[False,True],[None,'minimal','low','medium','high','xhigh','max'],[None,'auto','detailed','concise','']):
    options={}
    if effort is not None:options['reasoningEffort']=effort
    if summary is not None:options['reasoningSummary']=summary
    add(provider=provider,reasoning=reasoning,options=options)
for provider,effort,mapped,off in itertools.product(['openai','github-copilot','xai'],[None,'low','max'],[None,'','mapped'],[None,'','disabled']):
    mapping={'off':off,'low':mapped,'max':mapped}
    options={'reasoningSummary':None}
    if effort is not None:options['reasoningEffort']=effort
    add(provider=provider,mapping=mapping,options=options)
for maxTokens,support,temperature,tier in itertools.product([None,-10,-0.0,0,1,15,15.5,16,17,2048,1e100],[None,False,True],[None,0,0.7],[None,'auto','flex','priority','']):
    options={}
    for key,value in [('maxTokens',maxTokens),('temperature',temperature),('serviceTier',tier)]:
        if value is not None:options[key]=value
    add(compat={} if support is None else {'supportsMaxOutputTokens':support},options=options)
for retention,longCache,explicit,session in itertools.product(['none','short','long'],[False,True],[False,True],[None,'','session','😀'*70]):
    options={'cacheRetention':retention}
    if session is not None:options['sessionId']=session
    add(compat={'supportsLongCacheRetention':longCache,'supportsExplicitPromptCacheMode':explicit},options=options)
for choice,sampling in itertools.product(['auto','none','required',{'type':'function','name':'tool'},{'type':'custom','name':'grammar'}],[{}, {'model':'override','input':None,'stream':False,'store':True,'max_output_tokens':2,'temperature':None,'service_tier':'custom','prompt_cache_key':None,'prompt_cache_retention':None,'prompt_cache_options':None,'tools':None,'tool_choice':'none','reasoning':None,'include':[],'custom':{'nested':[1,True]}}]):
    add(options={'toolChoice':choice,'reasoningEffort':'high','sessionId':'session','cacheRetention':'long','samplingParams':sampling},input=[{'role':'user','content':'hello'}],tools=[{'type':'function','name':'tool','parameters':{'type':'object'}}])
results=json.loads(subprocess.check_output(['node','tests/responses_params_reference.mts'],input=json.dumps(cases),text=True,cwd=ROOT))
def flags(value):
    return '.'.join('-' if name not in (value or {}) else str(int(value[name])) for name in fields)
def encode(c,result):
    model=c['model'];options=c['options']
    value=[model['id'],model['provider'],model['reasoning'],model['thinkingLevelMap'],options,flags(model['compat']),options.get('cacheRetention','short'),c['input'],c['tools'],result]
    return ','.join(str(ord(x)) for x in json.dumps(value,ensure_ascii=True,separators=(',',':')))
if '--no-build' not in sys.argv:
    subprocess.run([sys.executable,'scripts/run-rss-guarded.py','--stats','build/responses-params-build.json','--','sh','scripts/build-pure.sh','packages/ai/test/openai-responses-params-runner.bend','build/responses-params-runner'],cwd=ROOT,check=True)
for threads in ['1','4']:
    for start in range(0,len(cases),24):
        args=[encode(c,r) for c,r in zip(cases[start:start+24],results[start:start+24])]
        run=subprocess.run([str(ROOT/'build/responses-params-runner'),'--threads',threads,*args],cwd=ROOT,capture_output=True,text=True,timeout=120)
        assert run.returncode==0,(threads,start,cases[start:start+24],run.stdout,run.stderr)
    print(f'PASS {len(cases)} upstream Responses parameter comparisons on {threads} threads')

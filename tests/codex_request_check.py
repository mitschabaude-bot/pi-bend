"""Compare Codex body framing against the actual pinned pure request builder."""
import itertools, json, pathlib, subprocess, sys
from upstream_pin import PIN, UPSTREAM
ROOT=pathlib.Path(__file__).resolve().parents[1]
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=UPSTREAM,text=True).strip()==PIN
FIELDS=['supportsDeveloperRole','supportsMidConvoSystemMessages','sessionAffinityFormat','supportsLongCacheRetention','supportsStrictMode','supportsOpenAIGrammarTools','supportsAdditionalTools','supportsToolSearch','supportsExplicitPromptCacheMode','supportsMaxOutputTokens']
schema={'type':'object','properties':{'input':{'type':'string'}},'required':['input']}
def tool(name): return {'name':name,'description':'A tool','parameters':schema}
cases=[]; arguments=[]
for mode, flags in itertools.product(range(5),itertools.product([False,True],[None,False,True],[False,True],[False,True])):
    compat={key:value for key,value in zip(['supportsMidConvoSystemMessages','supportsStrictMode','supportsAdditionalTools','supportsToolSearch'],flags) if value is not None}
    first={'role':'system','content':'initial','timestamp':1}
    if mode: first['toolsAdded']=[tool('tool')]
    messages=[first,{'role':'user','content':'hello','timestamp':1}]
    if mode==2: messages += [{'role':'system','content':'updated','toolsAdded':[tool('later')],'timestamp':2},{'role':'user','content':'again','timestamp':3}]
    if mode==3: messages += [{'role':'system','content':'updated','toolsRemoved':[{'name':'tool'}],'timestamp':2}]
    if mode==4: messages += [{'role':'system','content':'updated','toolsAdded':[dict(tool('tool'),description='Redefined')],'timestamp':2}]
    # The fixture's model API is irrelevant to these message kinds; it selects
    # the Codex endpoint explicitly and exercises the same shared converters.
    cases.append({'model':{'id':'target','api':'openai-responses','provider':'openai','baseUrl':'https://example.test','input':['text'],'reasoning':True,'compat':compat},'messages':messages,'options':{'temperature':0,'maxTokens':1,'reasoningEffort':'high','reasoningSummary':'concise','serviceTier':'priority','toolChoice':'required'}})
    arguments.append([str(mode),'.'.join(str(int(compat[f])) if f in compat else '-' for f in FIELDS)])
expected=json.loads(subprocess.check_output(['node','tests/codex_request_reference.mts'],input=json.dumps(cases),text=True,cwd=ROOT))
for label,command in [('bun',['bun','build/codex-request.js']),('native-1',['build/codex-request','--threads','1']),('native-4',['build/codex-request','--threads','4'])]:
    if len(sys.argv)>1 and label not in sys.argv[1:]: continue
    for start in range(0,len(cases),8):
        args=[]
        for fields,want in zip(arguments[start:start+8],expected[start:start+8]):
            args += fields+[','.join(str(ord(c)) for c in json.dumps(want,separators=(',',':')))]
        result=subprocess.run(command+args,cwd=ROOT,capture_output=True,text=True,timeout=120)
        assert result.returncode==0,(label,start,result.stdout,result.stderr,expected[start:start+8])
    print(f'{label}: {len(cases)} Codex request comparisons passed ({sum("output" in value for value in expected)} bodies, {sum("error" in value for value in expected)} errors)',flush=True)

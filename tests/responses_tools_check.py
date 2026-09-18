"""Typed Responses declarations, grammar selection and mappings versus actual Pi."""
import itertools,json,subprocess
from pathlib import Path
from schema_literals import value,string,seq
ROOT=Path(__file__).resolve().parents[1];BUILD=ROOT/'build'
schema={'type':'object','properties':{'payload':{'type':'string'}},'required':['payload'],'additionalProperties':False}
def tool(config=None,parameters=schema,name='sample_tool'):
    return dict(name=name,description='Sample tool',parameters=parameters,**({} if config is None else dict(constrainedSampling=config)))
def grammar(**variants):return dict(type='grammar',variants=variants)
configs=[None,False,dict(type='json_schema',strict='prefer'),dict(type='json_schema',strict='require'),grammar(openai_lark='start: /[a-z]+/'),grammar(openai_regex='[a-z]+'),grammar(openai_lark='  lark  ',openai_regex='regex'),grammar(openai_lark='\u00a0\n',openai_regex='regex'),grammar(),grammar(openai_lark='\ufeff\u2029',openai_regex='\t')]
cases=[]
for config,supports,strict in itertools.product(configs,[False,True],['absent',None,False,True]):
    options=dict(supportsOpenAIGrammarTools=supports,supportsStrictMode=supports,toolSearchResult=supports)
    if strict!='absent':options['strict']=strict
    cases.append(dict(tools=[tool(config)],options=options))
for config in configs:cases.append(dict(tools=[tool(config)],options=None))
# Capabilities are independent, including explicit strict on a non-strict model.
for sg,ss,search in itertools.product([False,True],repeat=3):
    for config in configs[:6]:cases.append(dict(tools=[tool(config)],options=dict(supportsOpenAIGrammarTools=sg,supportsStrictMode=ss,toolSearchResult=search,strict=True)))
invalid=[{'type':'string'},{'type':'object'},{'type':'object','required':[]},{'type':'object','required':[1]},{'type':'object','required':['a','b']},{'type':'object','required':['payload']},{'type':'object','required':['payload'],'properties':{}},{'type':'object','required':['payload'],'properties':{'payload':{'type':'number'}}},{'type':'object','required':['payload'],'properties':{'payload':{'type':['string','null']}}}]
for parameters in invalid:
    for supported in [False,True]:cases.append(dict(tools=[tool(grammar(openai_lark='lark'),parameters)],options=dict(supportsOpenAIGrammarTools=supported)))
for parameters in [{'type':'object','allOf':[]},{'type':'object','properties':{'child':{'$ref':'x'}}},{'type':'object','properties':{'extra':{'type':'object','additionalProperties':True}}}]:
    for strict in ['prefer','require']:cases.append(dict(tools=[tool(dict(type='json_schema',strict=strict),parameters)],options=None))
second={'type':'object','properties':{'other':{'type':'string'}},'required':['other']}
a=tool(grammar(openai_lark='lark'));b=tool(grammar(openai_regex='regex'),second);bad=tool(grammar(),name='bad')
for tools in [[],[a,b],[a,tool(False)],[tool(False),a],[a,bad,b],[bad,a], [tool(name='one'),a,tool(name='two')]]:
    for support in [False,True]:cases.append(dict(tools=tools,options=dict(supportsOpenAIGrammarTools=support)))
cases.append(dict(tools=None,options=None))
results=json.loads(subprocess.check_output(['node','tests/responses_tools_reference.mts'],input=json.dumps(cases),text=True,cwd=ROOT))
def maybe(v,fn):return 'None{}' if v is None else 'Some{'+fn(v)+'}'
def boolean(v):return 'True{}' if v else 'False{}'
def config(v):
    if v is None:return 'None{}'
    if v is False:return 'Some{T.SamplingDisabled{}}'
    if v['type']=='json_schema':return 'Some{T.SamplingConfigured{T.JsonSchemaSampling{T.'+('Prefer' if v['strict']=='prefer' else 'Require')+'{}}}}'
    return 'Some{T.SamplingConfigured{T.GrammarSampling{T.GrammarVariants{'+maybe(v['variants'].get('openai_lark'),string)+', '+maybe(v['variants'].get('openai_regex'),string)+'}}}}'
def nativeTool(t):return 'T.Tool{'+', '.join([string(t['name']),string(t['description']),value(t['parameters']),config(t.get('constrainedSampling'))])+'}'
def opts(o):
    if o is None:return 'None{}'
    strict='None{}' if 'strict' not in o else 'Some{T.NullValue{}}' if o['strict'] is None else 'Some{T.PresentValue{'+boolean(o['strict'])+'}}'
    return 'Some{O.ConvertResponsesToolsOptions{'+', '.join([strict]+[maybe(o.get(k),boolean) for k in ['supportsStrictMode','supportsOpenAIGrammarTools','toolSearchResult']])+'}}'
def result(r,fn):return 'Done{'+fn(r['value'])+'}' if r['ok'] else 'Fail{'+string(r['error'])+'}'
def grammarResult(r):return result(r,lambda v:maybe(v,lambda x:string(json.dumps(x,separators=(',',':'),ensure_ascii=False))))
lines=['import Base','import ../packages/ai/test/api/responses-tools.bend as Check','import ../packages/ai/src/api/openai-responses-shared.bend as O','import ../packages/ai/src/types.bend as T','import ../packages/runtime/src/schema-value.bend as V','import ../packages/runtime/src/record.bend as R','import ../packages/runtime/src/f64.bend as F']
for i,(c,r) in enumerate(zip(cases,results,strict=True)):
    lines += [f'def case{i}() -> IO(Unit):','  Check.check('+', '.join([seq(nativeTool(t) for t in c['tools'] or []),opts(c['options']),result(r['converted'],string),result(r['properties'],value),seq(grammarResult(g) for g in r['grammars']),f'"Responses tools {i}"'])+')']
groups=[]
for start in range(0,len(cases),25):
    name=f'group{start}';groups.append(name);lines += [f'def {name}() -> IO(Unit):','  do IO<Unit>:']+[f'    case{i}()' for i in range(start,min(start+25,len(cases)))]
lines += ['def main() -> IO(Unit):','  do IO<Unit>:','    Check.nativeErrors()']+[f'    {g}()' for g in groups]+[f'    IO.print("PASS {len(cases)} Responses tool conversions, grammar selections and declaration mappings")']
src=BUILD/'responses-tools-check.bend';src.write_text('\n'.join(lines)+'\n');out=BUILD/'responses-tools-check'
subprocess.run(['sh','scripts/build-pure.sh',str(src),str(out)],cwd=ROOT,check=True)
for threads in ['1','4']:subprocess.run([str(out),'--threads',threads],cwd=ROOT,check=True,timeout=120)

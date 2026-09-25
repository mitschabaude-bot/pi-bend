"""Copilot message policies and Responses integration against actual pi source."""
import itertools
import json
import random
import subprocess
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
alphabet='subietjka'
cases=[''.join(items) for n in range(4) for items in itertools.product(alphabet,repeat=n)]
rng=random.Random(19841)
cases += [''.join(rng.choices(alphabet,k=rng.randrange(4,80))) for _ in range(500)]
# Images in early history must survive long text-only tails.
cases += ['i'+'u'*256, 'j'+'a'*256, 'u'*256, 't'*256]
script=r'''
const fs=require('fs');const {stripTypeScriptTypes}=require('node:module');
const source=stripTypeScriptTypes(fs.readFileSync(process.env.PI_MONO+'/packages/ai/src/api/github-copilot-headers.ts','utf8')).replace(/^export /gm,'');
const {inferCopilotInitiator,hasCopilotVisionInput,buildCopilotDynamicHeaders}=new Function(source+';return {inferCopilotInitiator,hasCopilotVisionInput,buildCopilotDynamicHeaders};')();
const responses=stripTypeScriptTypes(fs.readFileSync(process.env.PI_MONO+'/packages/ai/src/api/openai-responses.ts','utf8'));
const start=responses.indexOf('function createClient('),end=responses.indexOf('\nfunction buildParams(',start);
if(start<0||end<0)throw Error('createClient extraction failed');
const create=new Function('getCompat','getPiUserAgent','hasCopilotVisionInput','buildCopilotDynamicHeaders','OpenAI',responses.slice(start,end)+';return createClient;')(()=>({sessionAffinityFormat:'openai'}),()=>'pi/test',hasCopilotVisionInput,buildCopilotDynamicHeaders,class{constructor(options){this.options=options}});
const blocks=image=>image?[{type:'text',text:'before'},{type:'image',data:'',mimeType:'image/png'},{type:'text',text:'after'}]:[{type:'text',text:'text'}];
function message(code){
 if(code==='s')return {role:'system',content:'system'};
 if(code==='u')return {role:'user',content:'text'};
 if(code==='b'||code==='i'||code==='e')return {role:'user',content:code==='e'?[]:blocks(code==='i')};
 if(code==='t'||code==='j'||code==='k')return {role:'toolResult',content:code==='k'?[]:blocks(code==='j')};
 return {role:'assistant',content:[]};
}
const codes=s=>Array.from(s,c=>c.codePointAt(0)).join(',');
const encoded=o=>Object.entries(o).map(([k,v])=>codes(k)+';'+(v===null?'~':codes(v))).join('|');
const shown=o=>Object.entries(o).map(([k,v])=>k+'='+v+';').join('');
function assembled(messages,provider,override){
 return encoded(create({provider,headers:{'X-Initiator':'model'},baseUrl:'https://example.invalid'},{messages},'test',override?{'X-Initiator':'caller','Copilot-Vision-Request':null}:undefined,undefined,'session').options.defaultHeaders);
}
console.log(JSON.stringify(JSON.parse(fs.readFileSync(0,'utf8')).map(input=>{
 const messages=Array.from(input,message);
 return [inferCopilotInitiator(messages),String(hasCopilotVisionInput(messages)),shown(buildCopilotDynamicHeaders({messages,hasImages:false})),shown(buildCopilotDynamicHeaders({messages,hasImages:true})),assembled(messages,'github-copilot',false),assembled(messages,'github-copilot',true),assembled(messages,'openai',false)].join('#');
})));
'''
expected=json.loads(subprocess.check_output(['node','--disable-warning=ExperimentalWarning','-e',script],input=json.dumps(cases),cwd=ROOT,text=True))
if '--no-build' not in sys.argv:subprocess.run(['sh','scripts/build-pure.sh','packages/ai/test/copilot-headers.bend','build/copilot-headers'],cwd=ROOT,check=True)
for threads in ['1','4']:
    for start in range(0,len(cases),32):
        result=subprocess.run([str(ROOT/'build/copilot-headers'),'--threads',threads,*cases[start:start+32]],cwd=ROOT,text=True,capture_output=True,check=True,timeout=30)
        actual=result.stdout.splitlines()
        assert actual==expected[start:start+32],(threads,start,actual,expected[start:start+32])
        assert not result.stderr,result.stderr
    print(threads,'threads:',len(cases),'Copilot policies and Responses integration cases PASS')

import fs from 'node:fs';
const source=fs.readFileSync('../pi-mono/packages/agent/src/agent-loop.ts','utf8');
const begin=source.indexOf('async function executeToolCalls(');
const start=source.indexOf('const toolCalls =',begin),end=source.indexOf('\n}',start);
if(begin<0||start<0||end<=start)throw new Error('tool selection body missing');
const AsyncFunction=Object.getPrototypeOf(async function(){}).constructor;
const select=new AsyncFunction('currentContext','assistantMessage','config','signal','emit','executeToolCallsSequential','executeToolCallsParallel',source.slice(start,end));
const patterns=[[],['text'],['a'],['b'],['a','b'],['text','a','thinking','b','a'],['b','text','b']];
const sets=[undefined,[{name:'a',executionMode:'sequential'}],[{name:'b',executionMode:'parallel'},{name:'b',executionMode:'sequential'}],[{name:'a',executionMode:'parallel'},{name:'b',executionMode:'sequential'}]];
const cases=[];
for(let pattern=0;pattern<patterns.length;pattern++)for(let tools=0;tools<sets.length;tools++)for(let global=0;global<3;global++){
  const a={type:'toolCall',id:'a',name:'a'},b={type:'toolCall',id:'b',name:'b'};
  const content=patterns[pattern].map(tag=>tag==='a'?a:tag==='b'?b:{type:tag});
  const context={tools:sets[tools]},assistant={content},config={toolExecution:[undefined,'parallel','sequential'][global]};
  const dispatch=mode=>(ctx,message,calls,cfg)=>{if(ctx!==context||message!==assistant||cfg!==config||calls===content)throw new Error('selection identity changed');return {mode,calls};};
  const result=await select(context,assistant,config,undefined,undefined,dispatch('sequential'),dispatch('parallel'));
  const ids=result.calls.map(call=>call.id).join('|');
  content.length=0;a.name='changed';
  if(result.calls.map(call=>call.id).join('|')!==ids||result.calls.some(call=>call.id==='a'&&call.name!=='changed'))throw new Error('filter snapshot/element identity changed');
  cases.push({pattern,tools,global,mode:result.mode,ids});
}
console.log(JSON.stringify({cases,patterns}));

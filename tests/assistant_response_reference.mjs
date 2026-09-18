import fs from 'node:fs';
const source=fs.readFileSync('../pi-mono/packages/agent/src/agent-loop.ts','utf8');
const start=source.indexOf('let partialMessage: AssistantMessage | null = null;');
const end=source.indexOf('\n}\n',start);
if(start<0 || end<=start) throw new Error('upstream response consumer missing');
const body=source.slice(start,end).replace(': AssistantMessage | null','');
const AsyncFunction=Object.getPrototypeOf(async function(){}).constructor;
const consume=new AsyncFunction('context','response','emit',body);
const cases=[];
for(let mode=0;mode<9;mode++) for(const failAt of [-1,0,1]) {
  const p={id:'p'},u={id:'u'},f={id:'f'},context={messages:[]},trace=[];
  const updates=['text_start','text_delta','text_end','thinking_start','thinking_delta','thinking_end','toolcall_start','toolcall_delta','toolcall_end'].map(type=>({type,partial:u}));
  let events= mode===0?[]:mode===2?[updates[0]]:mode===4?[]:[{type:'start',partial:p}];
  if(mode===3) events.push(...updates);
  if(mode===6) events.push({type:'start',partial:u});
  if(mode===8) events.push(updates[0]);
  if(mode!==4 && mode!==5) events.push({type:mode===7?'error':'done',message:f,error:f});
  const response={async *[Symbol.asyncIterator](){yield*events;},async result(){return f;}};
  let count=0;
  const emit=async event=>{
    const original=event.message.id==='p'?p:event.message.id==='u'?u:f;
    if(event.message!==original && event.type==='message_end') throw new Error('end copied');
    if(event.message===original && event.type!=='message_end') throw new Error('partial not copied');
    trace.push(event.type+':'+event.message.id);
    const current=count++;
    if(mode===8 && current===0) context.messages.push({id:'extra'});
    if(current===failAt) throw 'listener failure';
  };
  let result;
  try {result=(await consume(context,response,emit))===f?'final':'bad result';} catch(error) {result=error;}
  cases.push({mode,failAt,result,trace:trace.join('|'),messages:context.messages.map(m=>m.id).join('|'),count});
}
const prefixStart=source.indexOf('let messages = context.messages;');
const prefixEnd=source.indexOf('let partialMessage: AssistantMessage | null',prefixStart);
if(prefixStart<0 || prefixEnd<=prefixStart) throw new Error('upstream request prefix missing');
const prepare=new AsyncFunction('context','config','signal','streamFunction','normalizeContext',source.slice(prefixStart,prefixEnd)+'return response;');
let conversionCalls=0, conversionFailure;
const forbidden=()=>{throw new Error('conversion failure must skip normalization/provider');};
try {
  await prepare({messages:[]},{convertToLlm:async()=>{conversionCalls++;throw 'conversion failure';}},undefined,forbidden,forbidden);
} catch(error) {conversionFailure=error;}
if(conversionCalls!==1 || conversionFailure!=='conversion failure') throw new Error('unexpected failed conversion behavior');
console.log(JSON.stringify({cases,conversionFailure}));

import { UPSTREAM } from "./upstream_pin.mjs";
import fs from 'node:fs';
const source=fs.readFileSync(UPSTREAM + '/packages/agent/src/agent-loop.ts','utf8');
const start=source.indexOf('newMessages.push(message);',source.indexOf('// Stream assistant response'));
const end=source.indexOf('// Check for tool calls',start);
if(start<0 || end<=start) throw new Error('upstream post-response failure block missing');
const AsyncFunction=Object.getPrototypeOf(async function(){}).constructor;
const run=new AsyncFunction('message','newMessages','emit','config','signal','currentContext','let lastCompletedTurn;'+source.slice(start,end)+'return false;');
const cases=[];
for(const reason of ['pending','stop','length','toolUse','deferred','error','aborted']) for(const failAt of [-1,0,1]) for(const finishFails of [false,true]) {
  const message={stopReason:reason},extra={},messages=[extra],trace=[];let calls=0;
  const emit=async event=>{
    trace.push(event.type);
    if(event.type==='turn_end') {
      if(event.message.stopReason!==reason || event.toolResults.length!==0 || messages.length!==2) throw new Error('turn event/order changed');
    } else if(event.messages.length!==2) throw new Error('agent end history changed');
    if(calls++===failAt) throw 'listener failure';
  };
  const config={finishTurn:async completed=>{
    if(completed.message!==message || completed.toolResults.length!==0 || completed.newMessages.length!==2) throw new Error('finishTurn context changed');
    trace.push('finish');
    if(finishFails) throw 'finish failure';
    return {action:'continue'};
  }};
  let result;
  try {result=(await run(message,messages,emit,config,undefined,{messages:[]}))===false?'continue':'ended';} catch(error) {result=error;}
  cases.push({reason,failAt,finishFails,result,calls,trace:trace.join('|'),length:messages.length});
}
console.log(JSON.stringify({cases}));

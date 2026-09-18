import fs from 'node:fs';
const source=fs.readFileSync('../pi-mono/packages/agent/src/agent-loop.ts','utf8');
const start=source.indexOf('newMessages.push(message);',source.indexOf('// Stream assistant response'));
const end=source.indexOf('// Check for tool calls',start);
if(start<0 || end<=start) throw new Error('upstream post-response failure block missing');
const AsyncFunction=Object.getPrototypeOf(async function(){}).constructor;
const run=new AsyncFunction('message','newMessages','emit',source.slice(start,end)+'return false;');
const cases=[];
for(const reason of ['pending','stop','length','toolUse','deferred','error','aborted']) for(const failAt of [-1,0,1]) {
  const message={stopReason:reason},extra={},messages=[extra],trace=[];let calls=0;
  const emit=async event=>{
    trace.push(event.type);
    if(event.type==='turn_end') {
      if(event.message!==message || event.toolResults.length!==0 || messages[1]!==message) throw new Error('turn event identity/order changed');
      messages.push(extra);message.stopReason='stop';
    } else if(event.messages!==messages || messages.length!==3) throw new Error('agent end array changed');
    if(calls++===failAt) throw 'listener failure';
  };
  let result;
  try {result=(await run(message,messages,emit))===false?'continue':'ended';} catch(error) {result=error;}
  cases.push({reason,failAt,result,calls,trace:trace.join('|'),length:messages.length});
}
console.log(JSON.stringify({cases}));

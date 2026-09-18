import fs from 'node:fs';
const source=fs.readFileSync('../pi-mono/packages/agent/src/agent-loop.ts','utf8');
function body(name){const start=source.indexOf('function '+name+'(');const begin=source.indexOf('{\n',start);const end=source.indexOf('\n}',begin);if(start<0||begin<0||end<begin)throw new Error('missing '+name);return source.slice(begin+1,end);}
const AsyncFunction=Object.getPrototypeOf(async function(){}).constructor;
const createError=new Function('message',body('createErrorToolResult'));
const emitEnd=new AsyncFunction('finalized','emit',body('emitToolExecutionEnd'));
const createMessage=new Function('finalized',body('createToolResultMessage'));
const emitMessage=new AsyncFunction('toolResultMessage','emit',body('emitToolResultMessage'));
const run=new AsyncFunction('toolCalls','emit','createErrorToolResult','emitToolExecutionEnd','createToolResultMessage','emitToolResultMessage',body('failToolCallsFromTruncatedMessage').replace('const messages: ToolResultMessage[]','const messages').replace('const finalized: FinalizedToolCallOutcome','const finalized'));
const cases=[];
for(let count=0;count<=2;count++)for(let mode=0;mode<3;mode++)for(const failAt of [-1,0,1,2,3,4]) {
  if(count===0 && (mode!==0||failAt!==-1))continue;
  const all=['a','b','c'].map(id=>({id,name:id,arguments:'args'})),calls=all.slice(0,count),trace=[],texts=[];
  let index=0,lastDetails,lastMessage;
  const emit=async event=>{
    trace.push(event.type+':'+(event.toolCallId??event.message.toolCallId));
    if(event.type==='tool_execution_start' && index===0){if(mode===1)all[0].name='changed';if(mode===2)calls.push(all[2]);}
    if(event.type==='tool_execution_end'){
      if(!event.isError||event.result.details===lastDetails||Object.keys(event.result.details).length)throw new Error('error details not fresh');
      texts.push(event.result.content[0].text);lastDetails=event.result.details;lastDetails.seen=true;
    }
    if(event.type==='message_start'||event.type==='message_end'){
      if(event.message.details!==lastDetails||!event.message.isError||!event.message.details.seen)throw new Error('message payload identity changed');
      if(event.type==='message_start')lastMessage=event.message;else if(event.message!==lastMessage)throw new Error('message identity changed');
    }
    if(index++===failAt)throw 'listener failure';
  };
  let result,ids=[];
  try{const batch=await run(calls,emit,createError,emitEnd,createMessage,emitMessage);if(batch.terminate!==false)throw new Error('truncated batch terminated');result='done';ids=batch.messages.map(m=>m.toolCallId);}catch(error){if(error!=='listener failure')throw error;result=error;}
  cases.push({count,mode,failAt,result,trace:trace.join('|'),texts,ids:ids.join('|'),events:index});
}
console.log(JSON.stringify({cases}));

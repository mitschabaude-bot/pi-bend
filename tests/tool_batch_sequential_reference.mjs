import { UPSTREAM } from "./upstream_pin.mjs";
import fs from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const source=fs.readFileSync(UPSTREAM + '/packages/agent/src/agent-loop.ts','utf8');
const body=source.slice(source.indexOf('async function executeToolCallsSequential('),source.indexOf('async function executeToolCallsParallel('));
const termination=source.match(/function shouldTerminateToolBatch\([^\n]*\)\s*:\s*boolean \{([\s\S]*?)\n\}/)[1];
const shouldTerminate=new Function('finalizedCalls',termination);
let text='';for await(const chunk of process.stdin)text+=chunk;
const results=[];
for(const fixture of JSON.parse(text)) {
  const context={state:fixture.initial};const visited=[];let checks=0;
  const signal={get aborted(){checks++;return visited.length>=fixture.stopAfter;}};
  const prepare=async(ctx,_assistant,call)=>{
    visited.push(call.id);ctx.state+=call.id;
    const result={message:ctx.state,terminate:call.terminate};
    return call.immediate?{kind:'immediate',result,isError:false}:{kind:'prepared',toolCall:call,result};
  };
  const execute=async p=>({result:p.result,isError:false});
  const finalize=async(_ctx,_a,p,executed)=>({toolCall:p.toolCall,...executed});
  const end=async f=>{if(f.toolCall.fail)throw new Error('delivery failed');};
  const makeMessage=f=>f.result.message;
  const run=new Function('prepareToolCall','executePreparedToolCall','finalizeExecutedToolCall','emitToolExecutionEnd','createToolResultMessage','emitToolResultMessage','shouldTerminateToolBatch',stripTypeScriptTypes(body)+';return executeToolCallsSequential;')(prepare,execute,finalize,end,makeMessage,async()=>{},shouldTerminate);
  try {const result=await run(context,{},fixture.calls,{},signal,async()=>{});results.push({ok:true,state:context.state,...result,visited,checks});}
  catch(error){results.push({ok:false,error:error.message,visited,checks});}
}
process.stdout.write(JSON.stringify(results));

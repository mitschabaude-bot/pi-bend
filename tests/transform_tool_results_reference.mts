import { UPSTREAM } from "./upstream_pin.mjs";
import fs from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
import assert from 'node:assert/strict';
const source=fs.readFileSync(UPSTREAM + '/packages/ai/src/api/transform-messages.ts','utf8');
const transform=new Function(stripTypeScriptTypes(source).replace(/^export /gm,'')+';return transformMessages;')();
const call=id=>({type:'toolCall',id,name:'tool-'+id,arguments:'args',thoughtSignature:'thought',namespace:'ns'});
const ids={a1:['1'],a2:['2'],a12:['1','2'],a11:['1','1'],error:['1'],aborted:['2']};
const result=id=>({role:'toolResult',toolCallId:id,toolName:'tool-'+id,content:[{type:'text',text:'ok',textSignature:'result-signature'}],details:'original',isError:false,timestamp:44});
function message(tag){
 if(tag==='u')return {role:'user',content:'user',timestamp:43};
 if(tag==='s')return {role:'system',content:'system',timestamp:45};
 if(tag.startsWith('r'))return result(tag.slice(1));
 return {role:'assistant',content:[{type:'text',text:tag,textSignature:'text-signature'},...(ids[tag]??[]).map(call)],api:'openai-responses',provider:'test-provider',model:'test',responseModel:'response-model',responseId:'response-id',providerThinkingLevel:'high',usage:{totalTokens:42},stopReason:['error','aborted'].includes(tag)?tag:'stop',errorMessage:'metadata',rawStopReason:'raw',endTurn:false,timestamp:17};
}
function describe(m){
 if(m.role==='assistant'){const tag=m.content[0].text;assert.deepEqual(m,message(tag));return tag;}
 if(m.role==='user'){assert.deepEqual(m,message('u'));return 'u';}
 if(m.role==='system'){assert.deepEqual(m,message('s'));return 's';}
 if(m.details==='original'){assert.deepEqual(m,result(m.toolCallId));return 'r'+m.toolCallId;}
 assert.deepEqual(m,{role:'toolResult',toolCallId:m.toolCallId,toolName:'tool-'+m.toolCallId,content:[{type:'text',text:'No result provided'}],isError:true,timestamp:1000});
 return 'm'+m.toolCallId;
}
let input='';for await(const chunk of process.stdin)input+=chunk;
const oldNow=Date.now;Date.now=()=>1000;
try{process.stdout.write(JSON.stringify(JSON.parse(input).map(tags=>transform(tags.map(message),{id:'test',api:'openai-responses',provider:'test-provider',input:['text','image']}).map(describe))));}finally{Date.now=oldNow;}

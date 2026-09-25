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
const oldMessage=message;
const imageBlocks=[{type:'image',data:'data',mimeType:'image/png'},{type:'image',data:'data',mimeType:'image/png'},{type:'text',text:'between',textSignature:'image-text'},{type:'image',data:'data',mimeType:'image/png'}];
const fixture=tag=>tag==='i'?{role:'user',content:structuredClone(imageBlocks),timestamp:1}:tag==='ri'?{role:'toolResult',toolCallId:'1',toolName:'tool-1',content:structuredClone(imageBlocks),details:'images',isError:false,timestamp:2}:oldMessage(tag);
const optional=x=>x===undefined?'-':'='+x;
const blocks=xs=>xs.map(x=>x.type==='text'?'t:'+x.text+':'+optional(x.textSignature)+';':x.type==='toolCall'?'c:'+x.id+':'+x.name+':'+x.arguments+':'+optional(x.thoughtSignature)+':'+optional(x.namespace)+';':x.type==='image'?'i:'+x.data+':'+x.mimeType+';':'h:'+x.thinking+':'+optional(x.thinkingSignature)+';').join('');
const describe=xs=>xs.map(x=>x.role==='assistant'?'a['+blocks(x.content)+']':x.role==='toolResult'?'r['+x.toolCallId+':'+x.toolName+':'+(x.isError?'error':'ok')+':'+optional(x.details)+':'+blocks(x.content)+']':x.role==='user'?'u['+(typeof x.content==='string'?x.content:blocks(x.content))+']':'s').join('');
let input='';for await(const chunk of process.stdin)input+=chunk;
const oldNow=Date.now;Date.now=()=>1000;
try{process.stdout.write(JSON.stringify(JSON.parse(input).map(({mode,same,enabled,tags})=>{
 let trace='',count=0;
 const normalize=(id,model,source)=>{
  assert.equal(model.id,'foreign');assert.equal(source.content[0].textSignature,'text-signature');
  trace+=id+'@'+source.content[0].text+';';const index=count++;
  if(mode===4&&index===1)throw Error('normalization failed');
  return mode===1?id:mode===2&&index>0?id:mode===3?'':'n-'+id;
 };
 try{return {value:describe(transform(tags.map(fixture),{id:same?'test':'foreign',api:'openai-responses',provider:'test-provider',input:['text']},enabled?normalize:undefined)),trace,failure:false};}
 catch(error){assert.equal(error.message,'normalization failed');return {value:'',trace,failure:true};}
})));}finally{Date.now=oldNow;}

// The oracle runs the actual pinned processResponsesStream, cloning each event
// as emitted (the approved immutable-snapshot adaptation).
import fs from 'node:fs';
import {createRequire,stripTypeScriptTypes} from 'node:module';
const require=createRequire(import.meta.url);
const base='../pi-mono/packages/ai/src/';
const partialPath=process.env.PI_PARTIAL_JSON_PACKAGE??'/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/partial-json';
if(JSON.parse(fs.readFileSync(partialPath+'/package.json','utf8')).version!=='0.1.7')throw Error('partial-json version mismatch');
const partialParse=require(partialPath+'/dist/index.js').parse;
const strip=s=>stripTypeScriptTypes(s).replace(/^import .*;$/gm,'').replace(/^export /gm,'');
const parseStreamingJson=new Function('partialParse',strip(fs.readFileSync(base+'utils/json-parse.ts','utf8'))+';return parseStreamingJson;')(partialParse);
const source=fs.readFileSync(base+'api/openai-responses-shared.ts','utf8');
const sampling=fs.readFileSync(base+'api/constrained-sampling.ts','utf8');
const grammar=sampling.slice(sampling.indexOf('export function appendGrammarToolInputJsonDelta('),sampling.indexOf('function inferGrammarInputProperty('));
const signatures=source.slice(source.indexOf('function encodeTextSignatureV1('),source.indexOf('type ToolResultOutputContent'));
const processing=source.slice(source.indexOf('type StreamingToolCall ='));
const processStream=new Function('parseStreamingJson',strip(grammar+'\n'+signatures+'\n'+processing)+';return processResponsesStream;')(parseStreamingJson);
function clean(c){
 const value=c.type==='toolCall'?{type:c.type,id:c.id,name:c.name,arguments:structuredClone(c.arguments)}:c.type==='text'?{type:c.type,text:c.text}:{type:c.type,thinking:c.thinking};
 for(const field of ['namespace','textSignature','thinkingSignature'])if(c[field]!==undefined)value[field]=c[field];
 return value;
}
let input='';for await(const chunk of process.stdin)input+=chunk;
const results=[];
for(const c of JSON.parse(input)){
 const output={content:[]};const signals=[];
 const stream={push(event){const item=clean(event.partial.content[event.contentIndex]);const value={kind:event.type.endsWith('_start')?'started':event.type.endsWith('_end')?'ended':'delta',content:item};if(event.delta!==undefined)value.delta=event.delta;signals.push(value);}};
 const events=[{type:'response.output_item.added',output_index:0,item:c.item},...c.events.map(e=>({...e,output_index:0}))];
 let error;
 try{await processStream((async function*(){yield*events;})(),output,stream,{}, {grammarToolInputProperties:new Map(Object.entries(c.properties))});}
 catch(e){if(e.message!=='OpenAI Responses stream ended before a terminal response event')error=e.message;}
 const result=output.content.length?{content:clean(output.content[0]),signals}:null;
 if(error)result.error=error;
 results.push(JSON.stringify(result));
}
process.stdout.write(JSON.stringify(results));

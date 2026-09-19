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
export const processStream=new Function('parseStreamingJson',strip(grammar+'\n'+signatures+'\n'+processing)+';return processResponsesStream;')(parseStreamingJson);
export function clean(c){
 const value=c.type==='toolCall'?{type:c.type,id:c.id,name:c.name,arguments:structuredClone(c.arguments)}:c.type==='text'?{type:c.type,text:c.text}:{type:c.type,thinking:c.thinking};
 for(const field of ['namespace','textSignature','thinkingSignature'])if(c[field]!==undefined)value[field]=c[field];
 return value;
}

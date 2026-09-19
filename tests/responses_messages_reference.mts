import fs from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const root='../pi-mono/packages/ai/src/';
const shared=fs.readFileSync(root+'api/openai-responses-shared.ts','utf8');
const parts=['utils/hash.ts','utils/sanitize-unicode.ts','utils/text.ts','utils/transcript.ts','api/constrained-sampling.ts','api/transform-messages.ts'].map(p=>fs.readFileSync(root+p,'utf8'));
parts.push(shared.slice(shared.indexOf('function encodeTextSignatureV1('),shared.indexOf('// Stream processing')));
const code=parts.map(p=>stripTypeScriptTypes(p).replace(/^import .*;$/gm,'').replace(/^export /gm,'')).join('\n');
const convert=new Function(code+';return convertResponsesMessages;')();
let input='';for await(const chunk of process.stdin)input+=chunk;
const oldNow=Date.now;Date.now=()=>1000;
try{process.stdout.write(JSON.stringify(JSON.parse(input).map(c=>{
 const options={...c.options};if(options.grammarToolInputProperties)options.grammarToolInputProperties=new Map(Object.entries(options.grammarToolInputProperties));
 try{return {output:JSON.stringify(convert(c.model,{messages:c.messages},new Set(c.allowed),options))};}
 catch(e){return {error:e instanceof SyntaxError?'reasoning':e.message};}
})));}finally{Date.now=oldNow;}

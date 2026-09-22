import fs from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const root='../pi-mono/packages/ai/src/';
const shared=fs.readFileSync(root+'api/openai-responses-shared.ts','utf8');
const sources=['utils/hash.ts','utils/sanitize-unicode.ts','utils/text.ts','utils/transcript.ts','api/constrained-sampling.ts','api/transform-messages.ts'].map(p=>fs.readFileSync(root+p,'utf8'));
sources.push(shared.slice(shared.indexOf('function encodeTextSignatureV1('),shared.indexOf('// Stream processing')));
const provider=fs.readFileSync(root+'api/openai-codex-responses.ts','utf8');
sources.push(provider.slice(provider.indexOf('function buildRequestBody('),provider.indexOf('\nfunction getServiceTierCostMultiplier(')));
const code=sources.map(p=>stripTypeScriptTypes(p).replace(/^import .*;$/gm,'').replace(/^export /gm,'')).join('\n');
const api=new Function(`const CODEX_TOOL_CALL_PROVIDERS=new Set(['openai','openai-codex','opencode']);\n${code}\nreturn (model,context,options)=>buildRequestBody(model,context,options,'session',new Map());`)();
console.log(JSON.stringify(JSON.parse(fs.readFileSync(0,'utf8')).map(c=>{
 try{return {output:api(c.model,{messages:c.messages},c.options)}}
 catch(error){return {error:error.message}}
})));

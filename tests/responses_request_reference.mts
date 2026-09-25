import { UPSTREAM } from "./upstream_pin.mjs";
import fs from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const root=UPSTREAM + '/packages/ai/src/';
const shared=fs.readFileSync(root+'api/openai-responses-shared.ts','utf8');
const sources=['utils/hash.ts','utils/sanitize-unicode.ts','utils/text.ts','utils/transcript.ts','api/constrained-sampling.ts','api/transform-messages.ts','api/openai-prompt-cache.ts'].map(p=>fs.readFileSync(root+p,'utf8'));
sources.push(shared.slice(shared.indexOf('function encodeTextSignatureV1('),shared.indexOf('// Stream processing')));
const provider=fs.readFileSync(root+'api/openai-responses.ts','utf8');
sources.push(provider.slice(provider.indexOf('function detectSessionAffinityFormat('),provider.indexOf('// OpenAI Responses-specific options')));
sources.push(provider.slice(provider.indexOf('function buildParams('),provider.indexOf('\nfunction getServiceTierCostMultiplier(')));
const code=sources.map(p=>stripTypeScriptTypes(p).replace(/^import .*;$/gm,'').replace(/^export /gm,'')).join('\n');
const api=new Function(`const OPENAI_TOOL_CALL_PROVIDERS=new Set(['openai','openai-codex','opencode']); const OPENAI_RESPONSES_MIN_OUTPUT_TOKENS=16; const getProviderEnvValue=()=>undefined; ${code}; return {buildParams,getCompat};`)();
console.log(JSON.stringify(JSON.parse(fs.readFileSync(0,'utf8')).map(c=>{
 try{return {output:api.buildParams(c.model,{messages:c.messages},c.options,api.getCompat(c.model),new Map())};}
 catch(error){return {error:error.message};}
})));

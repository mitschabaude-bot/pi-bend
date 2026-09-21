import fs from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const root='../pi-mono/packages/ai/src/';
const shared=fs.readFileSync(root+'api/openai-responses-shared.ts','utf8');
const sources=['utils/hash.ts','utils/sanitize-unicode.ts','utils/text.ts','utils/transcript.ts','api/constrained-sampling.ts','api/transform-messages.ts','api/openai-prompt-cache.ts','api/github-copilot-headers.ts'].map(p=>fs.readFileSync(root+p,'utf8'));
sources.push(shared.slice(shared.indexOf('function encodeTextSignatureV1('),shared.indexOf('// Stream processing')));
const provider=fs.readFileSync(root+'api/openai-responses.ts','utf8');
sources.push(provider.slice(provider.indexOf('function hasHeader('),provider.indexOf('// OpenAI Responses-specific options')));
sources.push(provider.slice(provider.indexOf('function createClient('),provider.indexOf('\nfunction getServiceTierCostMultiplier(')));
const prelude=provider.slice(provider.indexOf('const apiKey = getClientApiKey('),provider.indexOf('const nextParams = await options?.onPayload'));
const code=sources.map(p=>stripTypeScriptTypes(p).replace(/^import .*;$/gm,'').replace(/^export /gm,'')).join('\n');
const api=new Function(`
const OPENAI_TOOL_CALL_PROVIDERS=new Set(['openai','openai-codex','opencode']);
const OPENAI_RESPONSES_MIN_OUTPUT_TOKENS=16;
const getProviderEnvValue=(name,env)=>env?.[name] || process.env[name];
const getPiUserAgent=()=> 'test-agent';
class OpenAI {constructor(options){this.options=options;}}
${code}
return (model,context,options)=>{
const normalizedContext=resolveTranscript(context,getCompat(model).supportsMidConvoSystemMessages);
${stripTypeScriptTypes(prelude)}
return {apiKey,baseUrl:client.options.baseURL,headers:client.options.defaultHeaders,payload:params,compat,grammar:Object.fromEntries(grammarToolInputProperties),retention:cacheRetention};
};`)();
const fields=['supportsDeveloperRole','supportsMidConvoSystemMessages','sessionAffinityFormat','supportsLongCacheRetention','supportsStrictMode','supportsOpenAIGrammarTools','supportsAdditionalTools','supportsToolSearch','supportsExplicitPromptCacheMode','supportsMaxOutputTokens'];
console.log(JSON.stringify(JSON.parse(fs.readFileSync(0,'utf8')).map(c=>{
 try{const out=api(c.model,{messages:c.messages},c.options);out.compat=fields.map(f=>f==='sessionAffinityFormat'?({openai:'a',openrouter:'r','openai-no-session':'n'}[out.compat[f]]):Number(out.compat[f])).join('.');return out;}
 catch(error){return {error:error.message};}
})));

import fs from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
const source = stripTypeScriptTypes(fs.readFileSync('../pi-mono/packages/ai/src/api/openai-responses.ts','utf8'));
const policy = source.slice(source.indexOf('function detectSessionAffinityFormat('), source.indexOf('// OpenAI Responses-specific options'));
const client = source.slice(source.indexOf('function createClient('), source.indexOf('\nfunction buildParams('));
const cacheKey = stripTypeScriptTypes(fs.readFileSync('../pi-mono/packages/ai/src/api/openai-prompt-cache.ts','utf8')).replace(/^export /gm,'');
const helpers = new Function('getProviderEnvValue', `
class OpenAI { constructor(options) { this.options=options; } }
function getPiUserAgent() { return 'test-agent'; }
${policy}\n${client}\n${cacheKey}
return { getCompat, resolveCacheRetention, getPromptCacheRetention, getPromptCacheOptions, createClient, clampOpenAIPromptCacheKey };
`)((name, env) => env?.[name]);
const cases=JSON.parse(fs.readFileSync(0,'utf8'));
console.log(JSON.stringify(cases.map(c=>{
  const model={provider:c.provider,baseUrl:c.url,compat:c.compat??undefined};
  const compat=helpers.getCompat(model);
  const retention=helpers.resolveCacheRetention(c.retention??undefined, {PI_CACHE_RETENTION:c.env??undefined});
  const session=retention==='none'?undefined:c.session??undefined;
  const headers=helpers.createClient(model,{},'test-key',undefined,undefined,session).options.defaultHeaders;
  return {compat,retention,promptRetention:helpers.getPromptCacheRetention(compat,retention)??null,
    options:helpers.getPromptCacheOptions(compat,retention)??null,session:session??null,
    key:helpers.clampOpenAIPromptCacheKey(session)??null,
    headers:['session_id','x-client-request-id','x-session-id'].map(k=>headers[k]??null)};
})));

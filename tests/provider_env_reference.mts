import fs from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { getProviderEnvValue } from '../../pi-mono/packages/ai/src/utils/provider-env.ts';
const source=stripTypeScriptTypes(fs.readFileSync('../pi-mono/packages/ai/src/api/openai-responses.ts','utf8'));
const helpers=source.slice(source.indexOf('function detectSessionAffinityFormat('),source.indexOf('// OpenAI Responses-specific options'));
const resolve=new Function('getProviderEnvValue',helpers+';return resolveCacheRetention;')(getProviderEnvValue);
console.log(JSON.stringify(JSON.parse(fs.readFileSync(0,'utf8')).map(([ambient,override,explicit])=>{
  if(ambient===null) delete process.env.PI_CACHE_RETENTION;
  else process.env.PI_CACHE_RETENTION=ambient;
  const env=override===null?undefined:{PI_CACHE_RETENTION:override};
  return [getProviderEnvValue('PI_CACHE_RETENTION',env)??null,resolve(explicit??undefined,env)];
})));

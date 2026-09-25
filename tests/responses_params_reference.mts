import { UPSTREAM } from "./upstream_pin.mjs";
import fs from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
const source=stripTypeScriptTypes(fs.readFileSync(UPSTREAM + '/packages/ai/src/api/openai-responses.ts','utf8'));
const policy=source.slice(source.indexOf('function detectSessionAffinityFormat('),source.indexOf('// OpenAI Responses-specific options'));
const build=source.slice(source.indexOf('function buildParams('),source.indexOf('\nfunction getServiceTierCostMultiplier('));
const key=stripTypeScriptTypes(fs.readFileSync(UPSTREAM + '/packages/ai/src/api/openai-prompt-cache.ts','utf8')).replace(/^export /gm,'');
// Only the already-converted input/tool boundary is substituted here. The
// separate request-integration test must exercise the actual converters.
const helpers=new Function(`
const OPENAI_TOOL_CALL_PROVIDERS=new Set(['openai','openai-codex','opencode']);
const OPENAI_RESPONSES_MIN_OUTPUT_TOKENS=16;
const getProviderEnvValue=()=>undefined;
const resolveTranscriptTools=messages=>({requestTools:messages});
const convertResponsesMessages=(model,context)=>context.input;
const convertResponsesTools=tools=>tools;
${policy}\n${key}\n${build}
return {buildParams,getCompat};`)();
console.log(JSON.stringify(JSON.parse(fs.readFileSync(0,'utf8')).map(c=>helpers.buildParams(c.model,{messages:c.tools,input:c.input},c.options,helpers.getCompat(c.model),new Map()))));

import fs from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const root='/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/openai/';
const version=JSON.parse(fs.readFileSync(root+'package.json','utf8')).version;
if(version!=='6.40.0')throw Error(`Unexpected SDK version: ${version}`);
const client=fs.readFileSync(root+'src/client.ts','utf8');
const headers=fs.readFileSync(root+'src/internal/headers.ts','utf8');
const utilities=fs.readFileSync(root+'src/internal/utils/values.ts','utf8');
const validation=utilities.slice(utilities.indexOf('export const validatePositiveInteger'),utilities.indexOf('export const coerceInteger'));
const methods=client.slice(client.indexOf('  protected validateHeaders('),client.indexOf('  protected stringifyQuery('))+client.slice(client.indexOf('  private async buildHeaders('),client.indexOf('  private _makeAbort('));
const code=stripTypeScriptTypes(headers).replace(/^import .*;$/gm,'').replace(/^export /gm,'')+'\n'+stripTypeScriptTypes(validation).replace(/^export /gm,'')+'\n'+stripTypeScriptTypes(`class Harness {${methods}}`);
const run=new Function('config',`
const isReadonlyArray=Array.isArray;
class OpenAIError extends Error {}
const getPlatformHeaders=()=>config.platform;
${code}
const subject=new Harness();subject.apiKey=config.apiKey;subject.organization=config.organization??null;subject.project=config.project??null;subject.getUserAgent=()=>config.userAgent;subject._options={defaultHeaders:config.client};
const timeout=config.timeout??600000;validatePositiveInteger('timeout',timeout);
return subject.buildHeaders({options:{timeout,headers:config.request},method:'post',bodyHeaders:config.body,retryCount:config.retryCount});
`);
const inputs=JSON.parse(fs.readFileSync(0,'utf8'));
const results=[];
for(const input of inputs){
 try{const fields=await run(input);results.push({headers:Object.fromEntries(fields.entries())});}
 catch(error){
 const message=String(error.message);
 const kind=message==='timeout must be an integer'?'timeout-integer':message==='timeout must be a positive integer'?'timeout-negative':message.startsWith('Could not resolve authentication method.')?'authentication':'header';
 results.push({error:kind,diagnostic:message});
 }
}
console.log(JSON.stringify(results));

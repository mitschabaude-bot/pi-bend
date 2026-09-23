// Classifies the JSON cases of argv[3] with the pinned pi-ai retry and
// overflow utilities; tests/retry-classify.bend answers the same lines.
import {readFileSync} from 'node:fs';
const root=process.argv[2];const rows=readFileSync(process.argv[3],'utf8').split('\n').filter(l=>l.trim());
const retry=await import(root+'/src/utils/retry.ts');
const overflow=await import(root+'/src/utils/overflow.ts');
for(const row of rows){const c=JSON.parse(row);
const usage={input:c.input,output:c.output,cacheRead:c.cacheRead,cacheWrite:0,totalTokens:c.input+c.cacheRead+c.output,cost:{input:0,output:0,cacheRead:0,cacheWrite:0,total:0}};
const message:any={role:'assistant',content:[],api:'openai-completions',provider:c.provider,model:'faux-model',usage,stopReason:c.stopReason,timestamp:0};
if(c.errorMessage!==null)message.errorMessage=c.errorMessage;
const policy:any={baseDelayMs:c.baseDelayMs};if(c.maxAgentDelayMs!==null)policy.maxAgentDelayMs=c.maxAgentDelayMs;
console.log(JSON.stringify({retryable:retry.isRetryableAssistantError(message),overflow:overflow.isContextOverflow(message,c.contextWindow),recoverable:overflow.isRecoverableLength(message,c.desiredMaxOutput),delayMs:retry.retryDelayMs(policy,c.attempt)}));}
